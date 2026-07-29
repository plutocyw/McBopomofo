// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Foundation

enum LLMCloudAPI {
    private struct GoogleGenerateContentRequest: Encodable {
        struct Content: Encodable {
            struct Part: Encodable {
                let text: String
            }

            let parts: [Part]
        }

        struct SystemInstruction: Encodable {
            struct Part: Encodable {
                let text: String
            }

            let parts: [Part]
        }

        let systemInstruction: SystemInstruction
        let contents: [Content]
        let generationConfig: GoogleGenerateContentGenerationConfig
    }

    private struct GoogleGenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?
    }

    private struct OpenAIChatCompletionsRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct OpenAIChatCompletionsResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]?
    }

    static func normalizedGoogleModelName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if trimmed.hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    static func googleGenerateContentURL(
        baseEndpoint: String,
        modelName: String
    ) -> URL? {
        let trimmedBase = baseEndpoint.trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmedBase)/models/\(modelName):generateContent")
    }

    static func makeGoogleRequest(
        endpoint: URL,
        modelName: String,
        apiKey: String,
        prompt: String,
        thinkingLevel: LLMGoogleThinkingLevel,
        editActionCount: Int?,
        timeoutInterval: TimeInterval
    ) throws -> URLRequest {
        let systemInstruction =
            editActionCount == nil
            ? "You are an IME same-pronunciation correction engine. Output the corrected sentence exactly once. The output must have exactly the same character count as the input sentence. Do not repeat, add, or omit any character. Output no analysis, explanation, formatting, or chain-of-thought."
            : "You are a Traditional Chinese IME correction action selector for Taiwan. Compare every proposed action in its word and sentence context and select every necessary, mutually non-overlapping action. Return an empty array only when every proposed replacement is worse or provides no linguistic improvement. Return only a JSON array of integer action IDs. Do not explain your answer."
        let body = GoogleGenerateContentRequest(
            systemInstruction: .init(
                parts: [
                    .init(text: systemInstruction)
                ]),
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(
                modelName: modelName,
                thinkingLevel: thinkingLevel,
                actionCount: editActionCount
            )
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = timeoutInterval
        return request
    }

    static func googleResponseText(from data: Data) -> String? {
        guard
            let parsed = try? JSONDecoder().decode(
                GoogleGenerateContentResponse.self,
                from: data),
            let candidate = parsed.candidates?.first,
            let parts = candidate.content?.parts
        else {
            return nil
        }
        return parts.compactMap(\.text).joined()
    }

    static func makeOpenAIRequest(
        endpoint: URL,
        modelName: String,
        apiKey: String,
        prompt: String,
        usesEditActions: Bool,
        timeoutInterval: TimeInterval
    ) throws -> URLRequest {
        let systemInstruction =
            usesEditActions
            ? "You are a Traditional Chinese IME correction action selector for Taiwan. Compare every proposed action in its word and sentence context and select every necessary, mutually non-overlapping action. Return an empty array only when every proposed replacement is worse or provides no linguistic improvement. Return only a JSON array of integer action IDs. Do not explain your answer."
            : "You are an IME same-pronunciation correction engine. Output only the corrected sentence. Never output analysis or chain-of-thought."
        let body = OpenAIChatCompletionsRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemInstruction),
                .init(role: "user", content: prompt),
            ],
            temperature: 0
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = timeoutInterval
        return request
    }

    static func openAIResponseText(from data: Data) -> String? {
        guard
            let parsed = try? JSONDecoder().decode(
                OpenAIChatCompletionsResponse.self,
                from: data)
        else {
            return nil
        }
        return parsed.choices?.first?.message.content
    }
}

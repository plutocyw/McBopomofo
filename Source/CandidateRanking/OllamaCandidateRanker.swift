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

struct OllamaCandidateRanker: CandidateRanker {
    func rank(request: CandidateRankingRequest) -> CandidateRankingResult {
        let prompt = makePrompt(for: request)
        let startNs = DispatchTime.now().uptimeNanoseconds

        let endpointBase = Preferences.llmOllamaEndpoint.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let modelName = Preferences.llmOllamaModelName.trimmingCharacters(
            in: .whitespacesAndNewlines)

        guard !endpointBase.isEmpty, !modelName.isEmpty else {
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "Ollama",
                    prompt: prompt,
                    response: nil,
                    elapsedMs: 0,
                    fallbackReason: "emptyOllamaConfig",
                    errorDescription: nil
                )
            )
        }

        let trimmedBase = endpointBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: "\(trimmedBase)/api/generate") else {
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "Ollama",
                    prompt: prompt,
                    response: nil,
                    elapsedMs: 0,
                    fallbackReason: "invalidOllamaEndpoint",
                    errorDescription: nil
                )
            )
        }

        struct OllamaRequest: Encodable {
            let model: String
            let prompt: String
            let system: String
            let stream: Bool
            let options: OllamaOptions

            struct OllamaOptions: Encodable {
                let temperature: Double
                let top_p: Double
                let num_predict: Int
            }
        }

        struct OllamaResponse: Decodable {
            let response: String?
            let error: String?
        }

        let body = OllamaRequest(
            model: modelName,
            prompt: prompt,
            system:
                "You rank Traditional Chinese input method candidates. Return ONLY a comma-separated list of candidate indices in best-first order. Do not include any other text.",
            stream: false,
            options: .init(
                temperature: 0,
                top_p: 1,
                num_predict: 64
            )
        )

        guard let jsonData = try? JSONEncoder().encode(body) else {
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "Ollama",
                    prompt: prompt,
                    response: nil,
                    elapsedMs: 0,
                    fallbackReason: "jsonEncodeFailed",
                    errorDescription: nil
                )
            )
        }

        let timeout = max(0.05, Double(Preferences.llmCandidateRankingTimeoutMs) / 1000.0)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        URLSession.shared.dataTask(with: urlRequest) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()

        let wait = semaphore.wait(timeout: .now() + timeout + 0.05)
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)
        if wait == .timedOut {
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "Ollama",
                    prompt: prompt,
                    response: nil,
                    elapsedMs: elapsedMs,
                    fallbackReason: "requestTimeout",
                    errorDescription: nil
                )
            )
        }

        guard let responseData else {
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "Ollama",
                    prompt: prompt,
                    response: nil,
                    elapsedMs: elapsedMs,
                    fallbackReason: "emptyResponse",
                    errorDescription: responseError.map { "\($0)" }
                )
            )
        }

        let rawResponse = String(data: responseData, encoding: .utf8)
        let parsed = try? JSONDecoder().decode(OllamaResponse.self, from: responseData)
        guard let responseText = parsed?.response else {
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "Ollama",
                    prompt: prompt,
                    response: rawResponse,
                    elapsedMs: elapsedMs,
                    fallbackReason: parsed?.error != nil ? "ollamaError" : "invalidJSON",
                    errorDescription: parsed?.error
                )
            )
        }

        guard
            let orderedIndices = AppleOnDeviceCandidateRankingParser.parseOrderedIndices(
                from: responseText,
                candidateCount: request.candidates.count
            )
        else {
            CandidateRankingStats.record(.parserFallback)
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "Ollama",
                    prompt: prompt,
                    response: responseText,
                    elapsedMs: elapsedMs,
                    fallbackReason: "parserFallback",
                    errorDescription: nil
                )
            )
        }

        let result = CandidateRankingResult(
            token: request.token,
            orderedCandidateIndices: orderedIndices,
            debugTrace: CandidateRankingDebugTrace(
                provider: "Ollama",
                prompt: prompt,
                response: responseText,
                elapsedMs: elapsedMs,
                fallbackReason: nil,
                errorDescription: nil
            )
        )
        guard result.isValidPermutation(candidateCount: request.candidates.count) else {
            let trace = result.debugTrace?.withFallbackReason("invalidPermutation")
            return fallbackResult(for: request, debugTrace: trace)
        }
        return result
    }

    private func fallbackResult(
        for request: CandidateRankingRequest,
        debugTrace: CandidateRankingDebugTrace? = nil
    ) -> CandidateRankingResult {
        CandidateRankingResult(
            token: request.token,
            orderedCandidateIndices: Array(request.candidates.indices),
            debugTrace: debugTrace
        )
    }

    private func makePrompt(for request: CandidateRankingRequest) -> String {
        let header = """
            Task: Rank Traditional Chinese IME candidates for the current input context.
            Compose buffer: \(request.composingBuffer)
            Cursor index: \(request.cursorIndex)
            Candidate count: \(request.candidates.count)
            Selection priorities:
            1) Prefer common, contextually natural Traditional Chinese words.
            2) If uncertain, keep earlier baseline order.
            3) Avoid uncommon variants unless context clearly requires them.
            """

        let candidateLines = request.candidates.map { candidate in
            let displayLength = candidate.displayText.count
            let isSingleCharacter = displayLength == 1
            let rawMatchesValue = candidate.rawValue == candidate.value
            return """
                [\(candidate.originalIndex)] reading=\(candidate.reading) display=\(candidate.displayText) value=\(candidate.value) raw=\(candidate.rawValue) len=\(displayLength) single=\(isSingleCharacter) rawMatches=\(rawMatchesValue)
                """
        }.joined(separator: "\n")

        let outputRule = """
            Output format rule:
            - Return exactly one line with \(request.candidates.count) unique indices.
            - Use comma-separated integers only.
            - No explanation, no extra words.
            Example: \(Array(0..<request.candidates.count).map(String.init).joined(separator: ","))
            """
        return [header, "Candidates:", candidateLines, outputRule].joined(separator: "\n")
    }
}

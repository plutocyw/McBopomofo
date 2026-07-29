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

struct GoogleGenerateContentThinkingConfig: Encodable {
    let thinkingBudget: Int?
    let thinkingLevel: String?
}

struct GoogleGenerateContentIntegerSchema: Encodable {
    let type = "integer"
    let minimum: Int
    let maximum: Int
}

struct GoogleGenerateContentArraySchema: Encodable {
    let type = "array"
    let items: GoogleGenerateContentIntegerSchema
    let minItems: Int
    let maxItems: Int
}

struct GoogleGenerateContentGenerationConfig: Encodable {
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int
    let candidateCount: Int?
    let responseMimeType: String
    let responseJsonSchema: GoogleGenerateContentArraySchema?
    let thinkingConfig: GoogleGenerateContentThinkingConfig

    init(
        modelName: String,
        thinkingLevel: LLMGoogleThinkingLevel,
        actionCount: Int? = nil
    ) {
        // Gemini 3 thinking tokens share the response budget with the visible
        // answer. Leave enough headroom so a short rewrite is not truncated.
        if let actionCount, actionCount > 0 {
            maxOutputTokens = 64
            responseMimeType = "application/json"
            responseJsonSchema = .init(
                items: .init(minimum: 0, maximum: actionCount - 1),
                minItems: 0,
                maxItems: actionCount
            )
        } else {
            maxOutputTokens = 1024
            responseMimeType = "text/plain"
            responseJsonSchema = nil
        }

        let normalizedModelName = modelName.lowercased()
        let usesLatestRequestFormat =
            normalizedModelName.hasPrefix("gemini-3.6")
            || normalizedModelName == "gemini-3.5-flash-lite"
            || normalizedModelName == "gemini-flash-latest"
        if usesLatestRequestFormat {
            temperature = nil
            topP = nil
            candidateCount = nil
            thinkingConfig = .init(
                thinkingBudget: nil,
                thinkingLevel: thinkingLevel.thinkingLevel
            )
        } else {
            temperature = 0
            topP = 1
            candidateCount = 1
            thinkingConfig = .init(
                thinkingBudget: thinkingLevel.thinkingBudget,
                thinkingLevel: nil
            )
        }
    }
}

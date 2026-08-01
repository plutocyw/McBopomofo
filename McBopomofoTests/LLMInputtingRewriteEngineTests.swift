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
import Testing

@testable import McBopomofo

@Suite("LLM Inputting Rewrite Engine Tests")
struct LLMInputtingRewriteEngineTests {
    private func configuration(usesEditActions: Bool = false) -> LLMCloudProviderConfiguration {
        return .openAI(
            endpoint: "https://example.com/v1/chat/completions",
            modelName: "model-test",
            apiKey: "test-key",
            usesEditActions: usesEditActions)
    }

    private func makeEngine(
        responseText: String,
        readingProvider: @escaping LLMInputtingRewriteEngine.ReadingProvider
    ) throws -> LLMInputtingRewriteEngine {
        let responseObject: [String: Any] = [
            "choices": [
                ["message": ["content": responseText]]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseObject)
        let transport = LLMHTTPTransport { _, completion in
            completion(responseData, nil)
        }
        return LLMInputtingRewriteEngine(
            cloudClient: LLMCloudClient(transport: transport),
            readingProvider: readingProvider)
    }

    private func makeCandidateRequest() -> LLMInputtingRewriteRequest {
        return LLMInputtingRewriteRequest(
            composingBuffer: "你好",
            segments: [
                .init(
                    reading: "ㄋㄧˇ",
                    currentValue: "你",
                    candidates: ["你", "妳"]),
                .init(
                    reading: "ㄏㄠˇ",
                    currentValue: "好",
                    candidates: ["好", "號"]),
            ],
            editActions: nil)
    }

    @Test("Candidate rewrite maps provider text to segment selections")
    func candidateRewriteMapsSelections() throws {
        let engine = try makeEngine(
            responseText: "你號",
            readingProvider: { _ in "same-reading" })

        let result = engine.rewrite(
            request: makeCandidateRequest(),
            configuration: configuration(),
            timeout: 0.1)

        #expect(result.rewrittenBuffer == "你號")
        #expect(result.selections == [0, 1])
        #expect(result.fallbackReason == nil)
        #expect(result.prompt.contains("Segment 0"))
        #expect(result.prompt.contains("[1] 號"))
    }

    @Test("Candidate rewrite rejects a changed reading")
    func candidateRewriteRejectsChangedReading() throws {
        let engine = try makeEngine(
            responseText: "你號",
            readingProvider: { $0 })

        let result = engine.rewrite(
            request: makeCandidateRequest(),
            configuration: configuration(),
            timeout: 0.1)

        #expect(result.rewrittenBuffer == "你號")
        #expect(result.selections == nil)
        #expect(result.fallbackReason == "parserFallback")
    }

    @Test("Edit action rewrite parses embedded JSON action IDs")
    func editActionRewriteParsesActionIDs() throws {
        let action = LLMEditAction(
            start: 0,
            end: 1,
            replacement: "應",
            sourceRank: 1,
            sourceScore: 0,
            components: 1,
            localScoreDelta: nil)
        let request = LLMInputtingRewriteRequest(
            composingBuffer: "因該",
            segments: [],
            editActions: [action])
        let engine = try makeEngine(
            responseText: "選擇 [0]",
            readingProvider: { _ in nil })

        let result = engine.rewrite(
            request: request,
            configuration: configuration(usesEditActions: true),
            timeout: 0.1)

        #expect(result.rewrittenBuffer == "應該")
        #expect(result.actionIDs == [0])
        #expect(result.fallbackReason == nil)
        #expect(result.prompt.contains("[0] 第 1 字：因 -> 應"))
    }

    @Test("Rewrite forwards cloud transport failure diagnostics")
    func rewriteForwardsCloudFailure() {
        let transport = LLMHTTPTransport { _, completion in
            completion(nil, "network unavailable")
        }
        let engine = LLMInputtingRewriteEngine(
            cloudClient: LLMCloudClient(transport: transport),
            readingProvider: { _ in nil })

        let result = engine.rewrite(
            request: makeCandidateRequest(),
            configuration: configuration(),
            timeout: 0.1)

        #expect(result.rewrittenBuffer == nil)
        #expect(result.fallbackReason == "emptyResponse")
        #expect(result.errorDescription == "network unavailable")
        #expect(!result.prompt.isEmpty)
    }
}

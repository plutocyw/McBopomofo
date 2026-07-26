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

@Suite("Candidate Ranking Tests", .serialized)
struct CandidateRankingTests {
    private struct ReversingRanker: CandidateRanker {
        func rank(request: CandidateRankingRequest) -> CandidateRankingResult {
            CandidateRankingResult(
                token: request.token,
                orderedCandidateIndices: Array(request.candidates.indices.reversed())
            )
        }
    }

    private func makeRequest(token: CandidateRankingContextToken = .init()) -> CandidateRankingRequest {
        let candidates = [
            CandidateRankingCandidate(
                reading: "ㄓㄨㄥ",
                value: "中",
                displayText: "中",
                rawValue: "中",
                originalIndex: 0
            ),
            CandidateRankingCandidate(
                reading: "ㄓㄨㄥ",
                value: "鐘",
                displayText: "鐘",
                rawValue: "鐘",
                originalIndex: 1
            ),
        ]
        return CandidateRankingRequest(
            token: token,
            composingBuffer: "",
            cursorIndex: 0,
            candidates: candidates
        )
    }

    private func makeChoosingCandidateState(
        token: CandidateRankingContextToken = .init()
    ) -> InputState.ChoosingCandidate {
        let candidates = [
            InputState.Candidate(reading: "ㄓㄨㄥ", value: "中", displayText: "中", rawValue: "中"),
            InputState.Candidate(reading: "ㄓㄨㄥ", value: "鐘", displayText: "鐘", rawValue: "鐘"),
            InputState.Candidate(reading: "ㄓㄨㄥ", value: "終", displayText: "終", rawValue: "終"),
        ]
        return InputState.ChoosingCandidate(
            composingBuffer: "中",
            cursorIndex: 1,
            candidates: candidates,
            useVerticalMode: false,
            rankingContextToken: token
        )
    }

    @Test("No-op ranker keeps candidate ordering")
    func noOpRankingKeepsIdentityOrder() {
        let ranker = NoOpCandidateRanker()
        let request = makeRequest()

        let result = ranker.rank(request: request)

        #expect(result.orderedCandidateIndices == [0, 1])
        #expect(result.isValidPermutation(candidateCount: request.candidates.count))
    }

    @Test("No-op ranker preserves context token")
    func noOpRankingPreservesToken() {
        let token = CandidateRankingContextToken()
        let ranker = NoOpCandidateRanker()
        let request = makeRequest(token: token)

        let result = ranker.rank(request: request)

        #expect(result.token == token)
    }

    @Test("Permutation validation rejects duplicates")
    func invalidPermutationIsRejected() {
        let token = CandidateRankingContextToken()
        let invalidResult = CandidateRankingResult(
            token: token,
            orderedCandidateIndices: [0, 0]
        )

        #expect(invalidResult.isValidPermutation(candidateCount: 2) == false)
    }


    @Test("Factory returns no-op when disabled")
    func factoryReturnsNoOpWhenDisabled() {
        let ranker = CandidateRankerFactory.makeCandidateRanker(
            isEnabled: false
        )
        #expect(type(of: ranker) == NoOpCandidateRanker.self)
    }

    @Test("Factory returns no-op when enabled")
    func factoryReturnsNoOpWhenEnabled() {
        let ranker = CandidateRankerFactory.makeCandidateRanker(isEnabled: true)
        #expect(type(of: ranker) == NoOpCandidateRanker.self)
    }

    @Test("ChoosingCandidate gets unique ranking token by default")
    func choosingCandidateAssignsUniqueDefaultToken() {
        let candidates = [InputState.Candidate(reading: "ㄓㄨㄥ", value: "中", displayText: "中", rawValue: "中")]
        let first = InputState.ChoosingCandidate(
            composingBuffer: "中",
            cursorIndex: 1,
            candidates: candidates,
            useVerticalMode: false
        )
        let second = InputState.ChoosingCandidate(
            composingBuffer: "中",
            cursorIndex: 1,
            candidates: candidates,
            useVerticalMode: false
        )
        #expect(first.rankingContextToken != second.rankingContextToken)
    }

    @Test("ChoosingCandidate keeps injected ranking token")
    func choosingCandidateUsesInjectedToken() {
        let token = CandidateRankingContextToken()
        let candidates = [InputState.Candidate(reading: "ㄓㄨㄥ", value: "中", displayText: "中", rawValue: "中")]
        let state = InputState.ChoosingCandidate(
            composingBuffer: "中",
            cursorIndex: 1,
            candidates: candidates,
            useVerticalMode: false,
            rankingContextToken: token
        )
        #expect(state.rankingContextToken == token)
    }

    @Test("Pipeline request applies topN bound")
    func pipelineRequestRespectsTopN() {
        let state = makeChoosingCandidateState()
        let request = CandidateRankingPipeline.makeRequest(from: state, topN: 2)

        #expect(request != nil)
        #expect(request?.candidates.count == 2)
        #expect(request?.candidates.map(\.originalIndex) == [0, 1])
    }

    @Test("Pipeline reorder affects prefix only")
    func pipelineReorderOnlyTouchesRankedPrefix() {
        let state = makeChoosingCandidateState()
        let result = CandidateRankingResult(token: state.rankingContextToken, orderedCandidateIndices: [1, 0])
        let reordered = CandidateRankingPipeline.reorderedCandidates(
            from: state.candidates,
            result: result
        )

        #expect(reordered != nil)
        #expect(reordered?.map(\.displayText) == ["鐘", "中", "終"])
    }

    @Test("Pipeline reorder rejects invalid permutation")
    func pipelineRejectsInvalidPermutation() {
        let state = makeChoosingCandidateState()
        let result = CandidateRankingResult(token: state.rankingContextToken, orderedCandidateIndices: [0, 0])
        let reordered = CandidateRankingPipeline.reorderedCandidates(
            from: state.candidates,
            result: result
        )

        #expect(reordered == nil)
    }

    @Test("Timeout ranker keeps underlying result within timeout")
    func timeoutRankerKeepsResultWithinTimeout() {
        var ticks: [UInt64] = [0, 5_000_000]
        let ranker = TimeoutCandidateRanker(
            base: ReversingRanker(),
            timeoutMs: 10,
            timeProvider: { ticks.removeFirst() }
        )
        let request = makeRequest()

        let result = ranker.rank(request: request)

        #expect(result.orderedCandidateIndices == [1, 0])
        #expect(result.token == request.token)
    }

    @Test("Timeout ranker falls back to identity when timed out")
    func timeoutRankerFallsBackWhenTimedOut() {
        var ticks: [UInt64] = [0, 25_000_000]
        let ranker = TimeoutCandidateRanker(
            base: ReversingRanker(),
            timeoutMs: 10,
            timeProvider: { ticks.removeFirst() }
        )
        let request = makeRequest()

        let result = ranker.rank(request: request)

        #expect(result.orderedCandidateIndices == [0, 1])
        #expect(result.token == request.token)
    }

    @Test("Timeout ranker handles non-monotonic clock safely")
    func timeoutRankerHandlesNonMonotonicClock() {
        var ticks: [UInt64] = [20_000_000, 10_000_000]
        let ranker = TimeoutCandidateRanker(
            base: ReversingRanker(),
            timeoutMs: 10,
            timeProvider: { ticks.removeFirst() }
        )
        let request = makeRequest()

        let result = ranker.rank(request: request)

        #expect(result.orderedCandidateIndices == [1, 0])
    }

    @Test("Apple parser extracts valid ordering from plain csv")
    func appleParserParsesCSV() {
        let parsed = AppleOnDeviceCandidateRankingParser.parseOrderedIndices(
            from: "2,0,1",
            candidateCount: 3
        )
        #expect(parsed == [2, 0, 1])
    }

    @Test("Apple parser rejects incomplete ordering")
    func appleParserRejectsIncompleteOrdering() {
        let parsed = AppleOnDeviceCandidateRankingParser.parseOrderedIndices(
            from: "0,1",
            candidateCount: 3
        )
        #expect(parsed == nil)
    }

    @Test("Apple parser drops invalid and duplicate indices")
    func appleParserDropsInvalidAndDuplicateIndices() {
        let parsed = AppleOnDeviceCandidateRankingParser.parseOrderedIndices(
            from: "3,1,1,0,2",
            candidateCount: 3
        )
        #expect(parsed == [1, 0, 2])
    }

    @Test("Apple parser prefers dedicated order line over noisy numbers")
    func appleParserPrefersDedicatedOrderLine() {
        let parsed = AppleOnDeviceCandidateRankingParser.parseOrderedIndices(
            from: """
                Candidate 1 looks best, candidate 2 second.
                [2,0,1]
                """,
            candidateCount: 3
        )
        #expect(parsed == [2, 0, 1])
    }

    @Test("Apple parser accepts bracketed order line")
    func appleParserAcceptsBracketedLine() {
        let parsed = AppleOnDeviceCandidateRankingParser.parseOrderedIndices(
            from: "(1,0,2)",
            candidateCount: 3
        )
        #expect(parsed == [1, 0, 2])
    }

    @Test(
        "Gemini 3.6 request preserves thinking level",
        arguments: [
            (LLMGoogleThinkingLevel.off, "minimal"),
            (LLMGoogleThinkingLevel.low, "low"),
            (LLMGoogleThinkingLevel.medium, "medium"),
            (LLMGoogleThinkingLevel.high, "high"),
        ])
    func gemini36RequestPreservesThinkingLevel(
        thinkingLevel: LLMGoogleThinkingLevel,
        expectedThinkingLevel: String
    ) throws {
        let config = GoogleGenerateContentGenerationConfig(
            modelName: "gemini-3.6-flash",
            thinkingLevel: thinkingLevel
        )
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = object as? [String: Any]
        let thinkingConfig = json?["thinkingConfig"] as? [String: Any]

        #expect(json?["temperature"] == nil)
        #expect(json?["topP"] == nil)
        #expect(json?["candidateCount"] == nil)
        #expect(thinkingConfig?["thinkingBudget"] == nil)
        #expect(thinkingConfig?["thinkingLevel"] as? String == expectedThinkingLevel)
        #expect(json?["maxOutputTokens"] as? Int == 1024)
    }

    @Test("Gemini edit action request uses bounded JSON array schema")
    func geminiEditActionRequestUsesJSONSchema() throws {
        let config = GoogleGenerateContentGenerationConfig(
            modelName: "gemini-3.6-flash",
            thinkingLevel: .off,
            actionCount: 20
        )
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = object as? [String: Any]
        let schema = json?["responseJsonSchema"] as? [String: Any]
        let items = schema?["items"] as? [String: Any]

        #expect(json?["responseMimeType"] as? String == "application/json")
        #expect(json?["maxOutputTokens"] as? Int == 64)
        #expect(schema?["type"] as? String == "array")
        #expect(schema?["minItems"] as? Int == 0)
        #expect(schema?["maxItems"] as? Int == 20)
        #expect(items?["type"] as? String == "integer")
        #expect(items?["minimum"] as? Int == 0)
        #expect(items?["maximum"] as? Int == 19)
    }

    @Test("Gemini latest request uses thinking level")
    func geminiLatestRequestUsesThinkingLevel() throws {
        let config = GoogleGenerateContentGenerationConfig(
            modelName: "gemini-flash-latest",
            thinkingLevel: .high
        )
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = object as? [String: Any]
        let thinkingConfig = json?["thinkingConfig"] as? [String: Any]

        #expect(json?["temperature"] == nil)
        #expect(json?["topP"] == nil)
        #expect(json?["candidateCount"] == nil)
        #expect(thinkingConfig?["thinkingBudget"] == nil)
        #expect(thinkingConfig?["thinkingLevel"] as? String == "high")
    }

    @Test("Gemini 2.5 request keeps thinking budget")
    func gemini25RequestKeepsThinkingBudget() throws {
        let config = GoogleGenerateContentGenerationConfig(
            modelName: "gemini-2.5-flash",
            thinkingLevel: .medium
        )
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = object as? [String: Any]
        let thinkingConfig = json?["thinkingConfig"] as? [String: Any]

        #expect(json?["temperature"] as? Double == 0)
        #expect(json?["topP"] as? Double == 1)
        #expect(json?["candidateCount"] as? Int == 1)
        #expect(thinkingConfig?["thinkingBudget"] as? Int == 1024)
        #expect(thinkingConfig?["thinkingLevel"] == nil)
    }

    @Test("Stats record and reset")
    func candidateRankingStatsRecordAndReset() {
        CandidateRankingStats.reset()
        CandidateRankingStats.record(.scheduled)
        CandidateRankingStats.record(.applied)
        CandidateRankingStats.record(.staleDropped)
        CandidateRankingStats.record(.timeoutFallback)
        CandidateRankingStats.record(.invalidResultFallback)
        CandidateRankingStats.record(.parserFallback)

        let snapshot = CandidateRankingStats.currentSnapshot()
        #expect(snapshot.scheduled == 1)
        #expect(snapshot.applied == 1)
        #expect(snapshot.staleDropped == 1)
        #expect(snapshot.timeoutFallback == 1)
        #expect(snapshot.invalidResultFallback == 1)
        #expect(snapshot.parserFallback == 1)

        CandidateRankingStats.reset()
        let resetSnapshot = CandidateRankingStats.currentSnapshot()
        #expect(resetSnapshot == CandidateRankingStatsSnapshot())
    }
}

// Copyright (c) 2026 and onwards The McBopomofo Authors.
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

@Suite("User Adaptation Backend Tests")
struct UserAdaptationBackendTests {
    private let context = UserAdaptationContext(
        reading: "ㄧㄥ",
        currentValue: "因",
        leftReading: "ㄨㄛˇ",
        leftValue: "我")

    @Test("No-op backend is deterministic and side-effect free")
    func noOpBackend() throws {
        let backend = NoOpUserAdaptationBackend()
        let query = UserAdaptationQuery(
            context: context,
            candidateValues: ["因", "應"])
        let observation = UserAdaptationObservation(
            context: context,
            replacementValue: "應",
            outcome: .accepted,
            source: .acceptedLLMCorrection,
            weight: 0.25,
            timestamp: Date(timeIntervalSince1970: 1_000))

        #expect(try backend.suggestion(for: query) == nil)
        try backend.observe(observation)
        try backend.reset(.source(.acceptedLLMCorrection))
        #expect(try backend.suggestion(for: query) == nil)
    }

    @Test("Suggestion confidence is bounded")
    func suggestionConfidenceIsBounded() {
        let low = UserAdaptationSuggestion(
            replacementValue: "應",
            confidence: -1,
            tier: .shortTerm,
            source: .acceptedLLMCorrection)
        let high = UserAdaptationSuggestion(
            replacementValue: "應",
            confidence: 2,
            tier: .longTerm,
            source: .manualSelection)

        #expect(low.confidence == 0)
        #expect(high.confidence == 1)
    }

    @Test("Observation weight cannot be negative")
    func observationWeightIsBounded() {
        let observation = UserAdaptationObservation(
            context: context,
            replacementValue: "應",
            outcome: .rejected,
            source: .acceptedLLMCorrection,
            weight: -1,
            timestamp: Date(timeIntervalSince1970: 1_000))

        #expect(observation.weight == 0)
    }
}

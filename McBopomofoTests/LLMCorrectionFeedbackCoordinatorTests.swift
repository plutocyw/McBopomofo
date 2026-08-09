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

import Testing

@testable import McBopomofo

@Suite("LLM Correction Feedback Coordinator Tests")
struct LLMCorrectionFeedbackCoordinatorTests {
    private let emptyContext = LLMCorrectionContext(
        reading: nil,
        leftReading: nil,
        leftValue: nil)

    private func transaction(
        original: String,
        start: Int,
        originalValue: String,
        replacementValue: String
    ) throws -> LLMCorrectionTransaction {
        try #require(
            LLMCorrectionTransaction(
                originalBuffer: original,
                changes: [
                    .init(
                        start: start,
                        end: start + originalValue.count,
                        originalValue: originalValue,
                        replacementValue: replacementValue,
                        context: emptyContext)
                ]))
    }

    @Test("Coordinator accumulates corrections across LLM passes")
    func accumulatesCorrections() throws {
        var coordinator = LLMCorrectionFeedbackCoordinator()
        coordinator.begin(
            try transaction(
                original: "因該很好",
                start: 0,
                originalValue: "因",
                replacementValue: "應"))
        coordinator.begin(
            try transaction(
                original: "應該很好",
                start: 2,
                originalValue: "很",
                replacementValue: "狠"))

        let evidence = coordinator.finish(
            disposition: .committed,
            finalBuffer: "應該狠好")

        #expect(evidence.map(\.outcome) == [.accepted, .accepted])
        #expect(!coordinator.hasPendingCorrections)
    }

    @Test("Later LLM rewrite invalidates overlapping older evidence")
    func laterRewriteInvalidatesOlderEvidence() throws {
        var coordinator = LLMCorrectionFeedbackCoordinator()
        coordinator.begin(
            try transaction(
                original: "因該",
                start: 0,
                originalValue: "因",
                replacementValue: "應"))
        coordinator.begin(
            try transaction(
                original: "應該",
                start: 0,
                originalValue: "應",
                replacementValue: "硬"))

        let evidence = coordinator.finish(
            disposition: .committed,
            finalBuffer: "硬該")

        #expect(evidence.map(\.outcome) == [.neutral, .accepted])
    }

    @Test("Explicit user change rejects matching correction")
    func explicitUserChangeRejectsCorrection() throws {
        var coordinator = LLMCorrectionFeedbackCoordinator()
        coordinator.begin(
            try transaction(
                original: "因該",
                start: 0,
                originalValue: "因",
                replacementValue: "應"))

        coordinator.recordExplicitUserBuffer("因該")
        let evidence = coordinator.finish(
            disposition: .committed,
            finalBuffer: "因該")

        #expect(evidence.map(\.outcome) == [.rejected])
    }

    @Test("Cancellation clears pending corrections without feedback")
    func cancellationClearsPendingCorrections() throws {
        var coordinator = LLMCorrectionFeedbackCoordinator()
        coordinator.begin(
            try transaction(
                original: "因該",
                start: 0,
                originalValue: "因",
                replacementValue: "應"))

        let evidence = coordinator.finish(disposition: .cancelled)

        #expect(evidence.map(\.outcome) == [.neutral])
        #expect(!coordinator.hasPendingCorrections)
    }
}

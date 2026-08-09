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

@Suite("LLM Correction Transaction Tests")
struct LLMCorrectionTransactionTests {
    private let emptyContext = LLMCorrectionContext(
        reading: nil,
        leftReading: nil,
        leftValue: nil)

    @Test("Transaction builds the corrected buffer")
    func buildsCorrectedBuffer() throws {
        let transaction = try #require(
            LLMCorrectionTransaction(
                originalBuffer: "因該很好",
                changes: [
                    .init(
                        start: 0,
                        end: 1,
                        originalValue: "因",
                        replacementValue: "應",
                        context: emptyContext),
                    .init(
                        start: 2,
                        end: 3,
                        originalValue: "很",
                        replacementValue: "狠",
                        context: emptyContext),
                ]))

        #expect(transaction.correctedBuffer == "應該狠好")
        #expect(transaction.changes.map(\.start) == [0, 2])
    }

    @Test("Commit accepts unchanged corrections")
    func commitAcceptsUnchangedCorrections() throws {
        let transaction = try #require(
            LLMCorrectionTransaction(
                originalBuffer: "因該",
                changes: [
                    .init(
                        start: 0,
                        end: 1,
                        originalValue: "因",
                        replacementValue: "應",
                        context: emptyContext)
                ]))

        #expect(transaction.evidence(on: .committed).map(\.outcome) == [.accepted])
    }

    @Test("Manual replacement rejects only overlapping correction")
    func manualReplacementRejectsOverlappingCorrection() throws {
        let transaction = try #require(
            LLMCorrectionTransaction(
                originalBuffer: "因該很好",
                changes: [
                    .init(
                        start: 0,
                        end: 1,
                        originalValue: "因",
                        replacementValue: "應",
                        context: emptyContext),
                    .init(
                        start: 2,
                        end: 3,
                        originalValue: "很",
                        replacementValue: "狠",
                        context: emptyContext),
                ]))

        let updated = transaction.recordingUserReplacement(
            start: 2,
            end: 3,
            value: "很")

        #expect(updated.evidence(on: .committed).map(\.outcome) == [.accepted, .rejected])
    }

    @Test("Selecting the corrected value preserves acceptance")
    func correctedValuePreservesAcceptance() throws {
        let transaction = try #require(
            LLMCorrectionTransaction(
                originalBuffer: "因該",
                changes: [
                    .init(
                        start: 0,
                        end: 1,
                        originalValue: "因",
                        replacementValue: "應",
                        context: emptyContext)
                ]))

        let updated = transaction.recordingUserReplacement(
            start: 0,
            end: 1,
            value: "應")

        #expect(updated.evidence(on: .committed).map(\.outcome) == [.accepted])
    }

    @Test("Cancellation produces only neutral evidence")
    func cancellationIsNeutral() throws {
        let transaction = try #require(
            LLMCorrectionTransaction(
                originalBuffer: "因該",
                changes: [
                    .init(
                        start: 0,
                        end: 1,
                        originalValue: "因",
                        replacementValue: "應",
                        context: emptyContext)
                ])
        )
        .recordingUserReplacement(start: 0, end: 1, value: "因")

        #expect(transaction.evidence(on: .cancelled).map(\.outcome) == [.neutral])
    }

    @Test("Memory replay learns rejection without reinforcing acceptance")
    func memoryReplayDoesNotReinforceAcceptance() throws {
        let transaction = try #require(
            LLMCorrectionTransaction(
                originalBuffer: "因該",
                changes: [
                    .init(
                        start: 0,
                        end: 1,
                        originalValue: "因",
                        replacementValue: "應",
                        context: emptyContext)
                ],
                learnsAcceptance: false))

        let acceptedEvidence = transaction.evidence(on: .committed)
        #expect(acceptedEvidence.map(\.outcome) == [.neutral])
        #expect(acceptedEvidence.map(\.origin) == [.localMemory])
        let rejected = transaction.recordingUserReplacement(
            start: 0,
            end: 1,
            value: "因")
        let rejectedEvidence = rejected.evidence(on: .committed)
        #expect(rejectedEvidence.map(\.outcome) == [.rejected])
        #expect(rejectedEvidence.map(\.origin) == [.localMemory])
    }

    @Test("Transaction rejects overlapping changes")
    func rejectsOverlappingChanges() {
        let transaction = LLMCorrectionTransaction(
            originalBuffer: "因該",
            changes: [
                .init(
                    start: 0,
                    end: 2,
                    originalValue: "因該",
                    replacementValue: "應該",
                    context: emptyContext),
                .init(
                    start: 1,
                    end: 2,
                    originalValue: "該",
                    replacementValue: "概",
                    context: emptyContext),
            ])

        #expect(transaction == nil)
    }
}

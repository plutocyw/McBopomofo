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

@Suite("LLM Correction Evidence Store Tests")
struct LLMCorrectionEvidenceStoreTests {
    private final class ControlsBox {
        var value = LLMCorrectionEvidenceStoreControls.enabled
    }

    private let accepted = LLMCorrectionEvidence(
        change: LLMCorrectionChange(
            start: 0,
            end: 1,
            originalValue: "因",
            replacementValue: "應",
            context: LLMCorrectionContext(
                reading: "ㄧㄥ",
                leftReading: "ㄨㄛˇ",
                leftValue: "我")),
        outcome: .accepted)

    private func makeTemporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        return directory.appendingPathComponent("evidence.json")
    }

    @Test("Store aggregates accepted and rejected evidence atomically")
    func aggregatesEvidence() throws {
        let fileURL = try makeTemporaryFileURL()
        let firstDate = Date(timeIntervalSince1970: 1_000)
        var currentDate = firstDate
        let store = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            now: { currentDate })

        try store.record([accepted])
        currentDate = Date(timeIntervalSince1970: 2_000)
        try store.record([
            LLMCorrectionEvidence(change: accepted.change, outcome: .rejected)
        ])

        let records = try store.records()
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.acceptedCount == 1)
        #expect(record.rejectedCount == 1)
        #expect(record.firstSeenAt == firstDate)
        #expect(record.lastRejectedAt == currentDate)
        #expect(record.sessionIDs.count == 1)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Read and write bypasses are independent")
    func bypassesReadsAndWrites() throws {
        let fileURL = try makeTemporaryFileURL()
        let controls = ControlsBox()
        let store = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            controlsProvider: { controls.value })

        try store.record([accepted])
        controls.value.readsEnabled = false
        #expect(try store.records().isEmpty)

        try store.record([
            LLMCorrectionEvidence(change: accepted.change, outcome: .rejected)
        ])

        controls.value.readsEnabled = true
        var record = try #require(try store.records().first)
        #expect(record.acceptedCount == 1)
        #expect(record.rejectedCount == 1)

        controls.value.writesEnabled = false
        try store.record([accepted])
        record = try #require(try store.records().first)
        #expect(record.acceptedCount == 1)
        #expect(record.rejectedCount == 1)
    }

    @Test("LLM learning bypass preserves non-LLM evidence")
    func bypassesOnlyLLMLearning() throws {
        let fileURL = try makeTemporaryFileURL()
        let controls = ControlsBox()
        controls.value.llmLearningEnabled = false
        let store = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            controlsProvider: { controls.value })

        try store.record([accepted], source: .acceptedLLMCorrection)
        try store.record([accepted], source: .manualSelection)

        #expect(try store.records(source: .acceptedLLMCorrection).isEmpty)
        #expect(try store.records(source: .manualSelection).count == 1)
    }

    @Test("Reset removes only the requested provenance")
    func resetsBySource() throws {
        let fileURL = try makeTemporaryFileURL()
        let controls = ControlsBox()
        let store = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            controlsProvider: { controls.value })
        try store.record([accepted], source: .acceptedLLMCorrection)
        try store.record([accepted], source: .manualSelection)

        controls.value.writesEnabled = false
        try store.reset(source: .acceptedLLMCorrection)

        #expect(try store.records(source: .acceptedLLMCorrection).isEmpty)
        #expect(try store.records(source: .manualSelection).count == 1)
    }

    @Test("Distinct process sessions are retained for promotion policy")
    func retainsDistinctSessions() throws {
        let fileURL = try makeTemporaryFileURL()
        let firstStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let secondStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

        try firstStore.record([accepted])
        try secondStore.record([accepted])

        let record = try #require(try secondStore.records().first)
        #expect(record.acceptedCount == 2)
        #expect(record.sessionIDs.count == 2)
    }

    @Test("Rejected sessions do not count toward long-term promotion")
    func excludesRejectedSessionsFromPromotionCount() throws {
        let fileURL = try makeTemporaryFileURL()
        let firstStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let secondStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

        try firstStore.record([
            LLMCorrectionEvidence(change: accepted.change, outcome: .rejected)
        ])
        try secondStore.record([accepted])

        let record = try #require(try secondStore.records().first)
        #expect(record.acceptedCount == 1)
        #expect(record.rejectedCount == 1)
        #expect(record.sessionIDs.count == 1)
    }

    @Test("Malformed input is reported without being overwritten")
    func reportsMalformedInput() throws {
        let fileURL = try makeTemporaryFileURL()
        let malformedData = Data("not json".utf8)
        try malformedData.write(to: fileURL)
        let store = LLMCorrectionEvidenceStore(fileURL: fileURL)

        #expect(throws: LLMCorrectionEvidenceStoreError.malformedData) {
            try store.record([accepted])
        }
        #expect(try Data(contentsOf: fileURL) == malformedData)
    }

    @Test("Unsupported versions stop at the migration boundary")
    func reportsUnsupportedVersion() throws {
        let fileURL = try makeTemporaryFileURL()
        let futureData = Data(#"{"records":[],"version":99}"#.utf8)
        try futureData.write(to: fileURL)
        let store = LLMCorrectionEvidenceStore(fileURL: fileURL)

        #expect(throws: LLMCorrectionEvidenceStoreError.unsupportedVersion(99)) {
            try store.records()
        }
        #expect(try Data(contentsOf: fileURL) == futureData)
    }
}

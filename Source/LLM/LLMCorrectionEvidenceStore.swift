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

enum LLMCorrectionEvidenceSource: String, Codable, CaseIterable {
    case manualSelection
    case acceptedLLMCorrection
    case explicitAlwaysUse
}

struct LLMCorrectionEvidenceStoreControls: Equatable {
    var readsEnabled: Bool
    var writesEnabled: Bool
    var llmLearningEnabled: Bool

    static let enabled = LLMCorrectionEvidenceStoreControls(
        readsEnabled: true,
        writesEnabled: true,
        llmLearningEnabled: true)
}

struct LLMCorrectionEvidenceKey: Codable, Equatable, Hashable {
    let reading: String?
    let originalValue: String
    let replacementValue: String
    let leftReading: String?
    let leftValue: String?
}

struct LLMCorrectionEvidenceRecord: Codable, Equatable {
    let key: LLMCorrectionEvidenceKey
    let source: LLMCorrectionEvidenceSource
    var acceptedCount: Int
    var rejectedCount: Int
    var sessionIDs: [String]
    let firstSeenAt: Date
    var lastSeenAt: Date
    var lastAcceptedAt: Date?
    var lastRejectedAt: Date?
}

enum LLMCorrectionEvidenceStoreError: Error, Equatable {
    case malformedData
    case unsupportedVersion(Int)
}

/// Persists aggregate correction evidence separately from any ranking model.
/// The store deliberately retains only the corrected span and its immediate
/// left context, never the complete composing buffer.
final class LLMCorrectionEvidenceStore {
    private struct Envelope: Codable {
        let version: Int
        var records: [LLMCorrectionEvidenceRecord]
    }

    static let currentVersion = 1
    static let fileName = "llm-correction-evidence.json"

    static let shared = LLMCorrectionEvidenceStore(
        fileURL: URL(fileURLWithPath: LanguageModelManager.dataFolderPath)
            .appendingPathComponent(fileName),
        controlsProvider: {
            LLMCorrectionEvidenceStoreControls(
                readsEnabled: Preferences.llmCorrectionMemoryReadsEnabled,
                writesEnabled: Preferences.llmCorrectionMemoryWritesEnabled,
                llmLearningEnabled: Preferences.llmCorrectionLearningEnabled)
        })

    private let fileURL: URL
    private let fileManager: FileManager
    private let sessionID: String
    private let now: () -> Date
    private let controlsProvider: () -> LLMCorrectionEvidenceStoreControls
    private let lock = NSLock()
    private var cachedEnvelope: Envelope?

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        sessionID: UUID = UUID(),
        now: @escaping () -> Date = Date.init,
        controlsProvider: @escaping () -> LLMCorrectionEvidenceStoreControls = {
            .enabled
        }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.sessionID = sessionID.uuidString
        self.now = now
        self.controlsProvider = controlsProvider
    }

    func records(source: LLMCorrectionEvidenceSource? = nil) throws
        -> [LLMCorrectionEvidenceRecord]
    {
        lock.lock()
        defer { lock.unlock() }
        guard controlsProvider().readsEnabled else {
            return []
        }
        let records = try loadEnvelope().records
        guard let source else {
            return records
        }
        return records.filter { $0.source == source }
    }

    func record(
        _ evidence: [LLMCorrectionEvidence],
        source: LLMCorrectionEvidenceSource = .acceptedLLMCorrection,
        at timestamp: Date? = nil
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let controls = controlsProvider()
        guard controls.writesEnabled else {
            return
        }
        if source == .acceptedLLMCorrection && !controls.llmLearningEnabled {
            return
        }

        let meaningfulEvidence = evidence.filter { $0.outcome != .neutral }
        guard !meaningfulEvidence.isEmpty else {
            return
        }

        var envelope = try loadEnvelope()
        let timestamp = timestamp ?? now()
        for item in meaningfulEvidence {
            let key = LLMCorrectionEvidenceKey(
                reading: item.change.context.reading,
                originalValue: item.change.originalValue,
                replacementValue: item.change.replacementValue,
                leftReading: item.change.context.leftReading,
                leftValue: item.change.context.leftValue)
            if let index = envelope.records.firstIndex(where: {
                $0.key == key && $0.source == source
            }) {
                update(
                    record: &envelope.records[index],
                    outcome: item.outcome,
                    timestamp: timestamp)
            } else {
                envelope.records.append(
                    makeRecord(
                        key: key,
                        source: source,
                        outcome: item.outcome,
                        timestamp: timestamp))
            }
        }
        try save(envelope)
    }

    /// Removes evidence by provenance. Passing nil clears every evidence
    /// source, but does not touch manual phrase files or ranking-model files.
    func reset(source: LLMCorrectionEvidenceSource? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        var envelope = try loadEnvelope()
        if let source {
            envelope.records.removeAll { $0.source == source }
        } else {
            envelope.records.removeAll()
        }
        try save(envelope)
    }

    func removeRecords(
        where shouldRemove: (LLMCorrectionEvidenceRecord) -> Bool
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        var envelope = try loadEnvelope()
        envelope.records.removeAll(where: shouldRemove)
        try save(envelope)
    }

    private func makeRecord(
        key: LLMCorrectionEvidenceKey,
        source: LLMCorrectionEvidenceSource,
        outcome: LLMCorrectionOutcome,
        timestamp: Date
    ) -> LLMCorrectionEvidenceRecord {
        LLMCorrectionEvidenceRecord(
            key: key,
            source: source,
            acceptedCount: outcome == .accepted ? 1 : 0,
            rejectedCount: outcome == .rejected ? 1 : 0,
            sessionIDs: outcome == .accepted ? [sessionID] : [],
            firstSeenAt: timestamp,
            lastSeenAt: timestamp,
            lastAcceptedAt: outcome == .accepted ? timestamp : nil,
            lastRejectedAt: outcome == .rejected ? timestamp : nil)
    }

    private func update(
        record: inout LLMCorrectionEvidenceRecord,
        outcome: LLMCorrectionOutcome,
        timestamp: Date
    ) {
        switch outcome {
        case .accepted:
            record.acceptedCount += 1
            record.lastAcceptedAt = timestamp
            if !record.sessionIDs.contains(sessionID) {
                record.sessionIDs.append(sessionID)
                record.sessionIDs.sort()
            }
        case .rejected:
            record.rejectedCount += 1
            record.lastRejectedAt = timestamp
        case .neutral:
            return
        }
        record.lastSeenAt = timestamp
    }

    private func loadEnvelope() throws -> Envelope {
        if let cachedEnvelope {
            return cachedEnvelope
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Envelope(version: Self.currentVersion, records: [])
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw LLMCorrectionEvidenceStoreError.malformedData
        }
        let envelope: Envelope
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw LLMCorrectionEvidenceStoreError.malformedData
        }
        guard envelope.version == Self.currentVersion else {
            throw LLMCorrectionEvidenceStoreError.unsupportedVersion(envelope.version)
        }
        cachedEnvelope = envelope
        return envelope
    }

    private func save(_ envelope: Envelope) throws {
        let parentURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = envelope.records.sorted {
            let lhs = recordSortKey($0)
            let rhs = recordSortKey($1)
            return lhs < rhs
        }
        let data = try encoder.encode(
            Envelope(version: Self.currentVersion, records: sorted))
        try data.write(to: fileURL, options: .atomic)
        cachedEnvelope = Envelope(version: Self.currentVersion, records: sorted)
    }

    private func recordSortKey(_ record: LLMCorrectionEvidenceRecord) -> String {
        [
            record.source.rawValue,
            record.key.reading ?? "",
            record.key.originalValue,
            record.key.replacementValue,
            record.key.leftReading ?? "",
            record.key.leftValue ?? "",
        ].joined(separator: "\u{1F}")
    }
}

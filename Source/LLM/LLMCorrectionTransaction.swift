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

struct LLMCorrectionContext: Equatable {
    let reading: String?
    let leftReading: String?
    let leftValue: String?
}

struct LLMCorrectionChange: Equatable {
    let start: Int
    let end: Int
    let originalValue: String
    let replacementValue: String
    let context: LLMCorrectionContext
}

enum LLMCorrectionTransactionDisposition {
    case committed
    case cancelled
}

enum LLMCorrectionOutcome: Equatable {
    case accepted
    case rejected
    case neutral
}

enum LLMCorrectionBufferDifference {
    case contradiction
    case invalidation
}

enum LLMCorrectionEvidenceOrigin: Equatable {
    case llmCorrection
    case localMemory
}

struct LLMCorrectionEvidence: Equatable {
    let change: LLMCorrectionChange
    let outcome: LLMCorrectionOutcome
    let origin: LLMCorrectionEvidenceOrigin

    init(
        change: LLMCorrectionChange,
        outcome: LLMCorrectionOutcome,
        origin: LLMCorrectionEvidenceOrigin = .llmCorrection
    ) {
        self.change = change
        self.outcome = outcome
        self.origin = origin
    }
}

/// Tracks an applied LLM correction until the surrounding composition is
/// committed or cancelled. This type deliberately contains no persistence or
/// user-model code so that feedback policy remains independent of the ranking
/// backend.
struct LLMCorrectionTransaction: Equatable {
    private enum PendingState: Equatable {
        case unchanged
        case contradicted
        case invalidated
    }

    private struct TrackedChange: Equatable {
        let change: LLMCorrectionChange
        let state: PendingState
    }

    let originalBuffer: String
    let correctedBuffer: String
    private let learnsAcceptance: Bool
    private let evidenceOrigin: LLMCorrectionEvidenceOrigin
    private let trackedChanges: [TrackedChange]

    var changes: [LLMCorrectionChange] {
        trackedChanges.map(\.change)
    }

    init?(
        originalBuffer: String,
        changes: [LLMCorrectionChange],
        learnsAcceptance: Bool = true
    ) {
        guard !changes.isEmpty else {
            return nil
        }

        let originalCharacters = Array(originalBuffer)
        let orderedChanges = changes.sorted {
            ($0.start, $0.end) < ($1.start, $1.end)
        }
        var previousEnd = 0
        for change in orderedChanges {
            guard
                change.start >= previousEnd,
                change.start >= 0,
                change.end > change.start,
                change.end <= originalCharacters.count,
                change.originalValue != change.replacementValue,
                change.originalValue.count == change.end - change.start,
                change.replacementValue.count == change.end - change.start,
                String(originalCharacters[change.start..<change.end]) == change.originalValue
            else {
                return nil
            }
            previousEnd = change.end
        }

        var correctedCharacters = originalCharacters
        for change in orderedChanges.reversed() {
            correctedCharacters.replaceSubrange(
                change.start..<change.end,
                with: Array(change.replacementValue))
        }

        self.originalBuffer = originalBuffer
        correctedBuffer = String(correctedCharacters)
        self.learnsAcceptance = learnsAcceptance
        evidenceOrigin = learnsAcceptance ? .llmCorrection : .localMemory
        trackedChanges = orderedChanges.map {
            TrackedChange(change: $0, state: .unchanged)
        }
    }

    private init(
        originalBuffer: String,
        correctedBuffer: String,
        learnsAcceptance: Bool,
        evidenceOrigin: LLMCorrectionEvidenceOrigin,
        trackedChanges: [TrackedChange]
    ) {
        self.originalBuffer = originalBuffer
        self.correctedBuffer = correctedBuffer
        self.learnsAcceptance = learnsAcceptance
        self.evidenceOrigin = evidenceOrigin
        self.trackedChanges = trackedChanges
    }

    /// Returns a new transaction reflecting a manual replacement made while
    /// the LLM-corrected composition is active. A replacement that exactly
    /// preserves an LLM change leaves it pending; any other overlapping
    /// replacement contradicts that change.
    func recordingUserReplacement(start: Int, end: Int, value: String)
        -> LLMCorrectionTransaction
    {
        guard start >= 0, end > start else {
            return self
        }
        let updated = trackedChanges.map { tracked -> TrackedChange in
            let change = tracked.change
            guard start < change.end, end > change.start else {
                return tracked
            }
            let preservesCorrection =
                start == change.start && end == change.end
                && value == change.replacementValue
            return TrackedChange(
                change: change,
                state: preservesCorrection ? .unchanged : .contradicted)
        }
        return LLMCorrectionTransaction(
            originalBuffer: originalBuffer,
            correctedBuffer: correctedBuffer,
            learnsAcceptance: learnsAcceptance,
            evidenceOrigin: evidenceOrigin,
            trackedChanges: updated)
    }

    /// Reconciles fixed-position corrections with the current composing
    /// buffer. Explicit user changes are contradictions. Automatic rewrites,
    /// structural edits, and later LLM passes invalidate older evidence
    /// without counting as negative user feedback.
    func reconcilingCurrentBuffer(
        _ buffer: String,
        differences: LLMCorrectionBufferDifference
    ) -> LLMCorrectionTransaction {
        let characters = Array(buffer)
        let updated = trackedChanges.map { tracked -> TrackedChange in
            let change = tracked.change
            guard change.end <= characters.count else {
                return TrackedChange(change: change, state: .invalidated)
            }
            let currentValue = String(characters[change.start..<change.end])
            if currentValue == change.replacementValue {
                return TrackedChange(change: change, state: .unchanged)
            }
            if tracked.state == .contradicted {
                return tracked
            }
            return TrackedChange(
                change: change,
                state: differences == .contradiction ? .contradicted : .invalidated)
        }
        return LLMCorrectionTransaction(
            originalBuffer: originalBuffer,
            correctedBuffer: correctedBuffer,
            learnsAcceptance: learnsAcceptance,
            evidenceOrigin: evidenceOrigin,
            trackedChanges: updated)
    }

    func evidence(on disposition: LLMCorrectionTransactionDisposition)
        -> [LLMCorrectionEvidence]
    {
        trackedChanges.map { tracked in
            let outcome: LLMCorrectionOutcome
            switch disposition {
            case .cancelled:
                outcome = .neutral
            case .committed:
                switch tracked.state {
                case .unchanged:
                    outcome = learnsAcceptance ? .accepted : .neutral
                case .contradicted:
                    outcome = .rejected
                case .invalidated:
                    outcome = .neutral
                }
            }
            return LLMCorrectionEvidence(
                change: tracked.change,
                outcome: outcome,
                origin: evidenceOrigin)
        }
    }
}

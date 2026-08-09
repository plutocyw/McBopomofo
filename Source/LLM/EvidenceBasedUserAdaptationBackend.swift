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

enum UserAdaptationMetric: Equatable {
    case promotion
    case demotion
}

enum UserAdaptationSelectionPlanner {
    static func selections(
        currentValues: [String],
        candidateValues: [[String]],
        suggestions: [UserAdaptationSuggestion?],
        minimumConfidence: Double =
            EvidenceBasedUserAdaptationPolicy.minimumLocalApplicationConfidence
    ) -> [Int]? {
        guard
            currentValues.count == candidateValues.count,
            suggestions.count == candidateValues.count
        else {
            return nil
        }
        var changed = false
        var selections: [Int] = []
        for index in candidateValues.indices {
            let candidates = candidateValues[index]
            guard let currentIndex = candidates.firstIndex(of: currentValues[index]) else {
                return nil
            }
            guard
                let suggestion = suggestions[index],
                suggestion.confidence >= minimumConfidence,
                let suggestedIndex = candidates.firstIndex(of: suggestion.replacementValue),
                suggestedIndex != currentIndex
            else {
                selections.append(currentIndex)
                continue
            }
            changed = true
            selections.append(suggestedIndex)
        }
        return changed ? selections : nil
    }
}

struct EvidenceBasedUserAdaptationPolicy {
    static let minimumLocalApplicationConfidence = 0.9

    static func fromPreferences() -> Self {
        Self(
            shortTermHalfLife: TimeInterval(
                Preferences.llmCorrectionShortTermHalfLifeMinutes * 60),
            shortTermMaximumAge: TimeInterval(
                Preferences.llmCorrectionShortTermMaximumAgeMinutes * 60),
            longTermHalfLife: TimeInterval(
                Preferences.llmCorrectionLongTermHalfLifeDays * 24 * 60 * 60),
            longTermMaximumAge: TimeInterval(
                Preferences.llmCorrectionLongTermMaximumAgeDays * 24 * 60 * 60),
            longTermMinimumAcceptances:
                Preferences.llmCorrectionLongTermMinimumAcceptances,
            longTermMinimumSessions:
                Preferences.llmCorrectionLongTermMinimumSessions,
            minimumAcceptanceRatio: Double(
                Preferences.llmCorrectionMinimumAcceptanceRatioPercent) / 100)
    }

    let shortTermHalfLife: TimeInterval
    let shortTermMaximumAge: TimeInterval
    let longTermHalfLife: TimeInterval
    let longTermMaximumAge: TimeInterval
    let longTermMinimumAcceptances: Int
    let longTermMinimumSessions: Int
    let minimumAcceptanceRatio: Double

    init(
        shortTermHalfLife: TimeInterval = 90 * 60,
        shortTermMaximumAge: TimeInterval = 90 * 60,
        longTermHalfLife: TimeInterval = 180 * 24 * 60 * 60,
        longTermMaximumAge: TimeInterval = 365 * 24 * 60 * 60,
        longTermMinimumAcceptances: Int = 3,
        longTermMinimumSessions: Int = 2,
        minimumAcceptanceRatio: Double = 0.8
    ) {
        self.shortTermHalfLife = shortTermHalfLife
        self.shortTermMaximumAge = shortTermMaximumAge
        self.longTermHalfLife = longTermHalfLife
        self.longTermMaximumAge = longTermMaximumAge
        self.longTermMinimumAcceptances = longTermMinimumAcceptances
        self.longTermMinimumSessions = longTermMinimumSessions
        self.minimumAcceptanceRatio = minimumAcceptanceRatio
    }

    func suggestion(
        for query: UserAdaptationQuery,
        records: [LLMCorrectionEvidenceRecord],
        at timestamp: Date
    ) -> UserAdaptationSuggestion? {
        let matchingRecords = records.filter { record in
            record.key.reading == query.context.reading
                && record.key.originalValue == query.context.currentValue
                && record.key.leftReading == query.context.leftReading
                && record.key.leftValue == query.context.leftValue
                && record.key.replacementValue != query.context.currentValue
                && query.candidateValues.contains(record.key.replacementValue)
        }
        return matchingRecords.compactMap { record in
            guard let tier = memoryTier(for: record, at: timestamp) else {
                return nil
            }
            return UserAdaptationSuggestion(
                replacementValue: record.key.replacementValue,
                confidence: confidence(for: record, tier: tier, at: timestamp),
                tier: tier,
                source: record.source)
        }.max { lhs, rhs in
            suggestionPriority(lhs) < suggestionPriority(rhs)
        }
    }

    func memoryTier(
        for record: LLMCorrectionEvidenceRecord,
        at timestamp: Date
    ) -> UserAdaptationMemoryTier? {
        if record.source == .explicitAlwaysUse {
            return record.acceptedCount > record.rejectedCount ? .explicit : nil
        }
        guard
            record.acceptedCount > 0,
            let lastAcceptedAt = record.lastAcceptedAt
        else {
            return nil
        }
        if let lastRejectedAt = record.lastRejectedAt,
            lastRejectedAt >= lastAcceptedAt
        {
            return nil
        }

        let total = record.acceptedCount + record.rejectedCount
        let acceptanceRatio = Double(record.acceptedCount) / Double(total)
        guard acceptanceRatio >= minimumAcceptanceRatio else {
            return nil
        }
        let age = max(0, timestamp.timeIntervalSince(lastAcceptedAt))
        if record.acceptedCount >= longTermMinimumAcceptances,
            record.sessionIDs.count >= longTermMinimumSessions,
            age <= longTermMaximumAge
        {
            return .longTerm
        }
        if age <= shortTermMaximumAge {
            return .shortTerm
        }
        return nil
    }

    private func confidence(
        for record: LLMCorrectionEvidenceRecord,
        tier: UserAdaptationMemoryTier,
        at timestamp: Date
    ) -> Double {
        let total = record.acceptedCount + record.rejectedCount
        let acceptanceRatio =
            total > 0
            ? Double(record.acceptedCount) / Double(total) : 0
        let lastAcceptedAt = record.lastAcceptedAt ?? record.lastSeenAt
        let age = max(0, timestamp.timeIntervalSince(lastAcceptedAt))
        let sourceBonus = record.source == .manualSelection ? 0.02 : 0

        switch tier {
        case .explicit:
            return 1
        case .longTerm:
            let recency = decayedValue(age: age, halfLife: longTermHalfLife)
            return min(0.99, 0.9 + 0.05 * acceptanceRatio + 0.02 * recency + sourceBonus)
        case .shortTerm:
            let recency = decayedValue(age: age, halfLife: shortTermHalfLife)
            let repetitionBonus = 0.01 * Double(min(record.acceptedCount, 2))
            return min(0.98, 0.88 + 0.04 * recency + repetitionBonus + sourceBonus)
        }
    }

    private func decayedValue(age: TimeInterval, halfLife: TimeInterval) -> Double {
        guard halfLife > 0 else {
            return 0
        }
        return exp2(-age / halfLife)
    }

    private func suggestionPriority(
        _ suggestion: UserAdaptationSuggestion
    ) -> (Int, Int, Double) {
        let tierPriority: Int
        switch suggestion.tier {
        case .shortTerm:
            tierPriority = 1
        case .longTerm:
            tierPriority = 2
        case .explicit:
            tierPriority = 3
        }
        let sourcePriority: Int
        switch suggestion.source {
        case .acceptedLLMCorrection:
            sourcePriority = 1
        case .manualSelection:
            sourcePriority = 2
        case .explicitAlwaysUse:
            sourcePriority = 3
        }
        return (tierPriority, sourcePriority, suggestion.confidence)
    }
}

final class EvidenceBasedUserAdaptationBackend: UserAdaptationBackend {
    private let store: LLMCorrectionEvidenceStore
    private let policyProvider: () -> EvidenceBasedUserAdaptationPolicy
    private let now: () -> Date
    private let metricRecorder: (UserAdaptationMetric) -> Void

    init(
        store: LLMCorrectionEvidenceStore,
        policy: EvidenceBasedUserAdaptationPolicy = .init(),
        policyProvider: (() -> EvidenceBasedUserAdaptationPolicy)? = nil,
        now: @escaping () -> Date = Date.init,
        metricRecorder: @escaping (UserAdaptationMetric) -> Void = { metric in
            switch metric {
            case .promotion:
                CandidateRankingStats.record(.memoryPromotion)
            case .demotion:
                CandidateRankingStats.record(.memoryDemotion)
            }
        }
    ) {
        self.store = store
        self.policyProvider = policyProvider ?? { policy }
        self.now = now
        self.metricRecorder = metricRecorder
    }

    func suggestions(for queries: [UserAdaptationQuery]) throws
        -> [UserAdaptationSuggestion?]
    {
        let records = try store.records()
        let timestamp = now()
        let policy = policyProvider()
        return queries.map {
            policy.suggestion(for: $0, records: records, at: timestamp)
        }
    }

    func observe(_ observation: UserAdaptationObservation) throws {
        guard
            let reading = observation.context.reading,
            !reading.isEmpty,
            !observation.context.currentValue.isEmpty,
            !observation.replacementValue.isEmpty,
            observation.context.currentValue != observation.replacementValue,
            observation.weight > 0
        else {
            return
        }
        let timestamp = observation.timestamp
        let policy = policyProvider()
        let key = LLMCorrectionEvidenceKey(
            reading: reading,
            originalValue: observation.context.currentValue,
            replacementValue: observation.replacementValue,
            leftReading: observation.context.leftReading,
            leftValue: observation.context.leftValue)
        let tierBeforeObservation = try matchingTier(
            key: key,
            source: observation.source,
            at: timestamp,
            policy: policy)
        let outcome: LLMCorrectionOutcome =
            observation.outcome == .accepted
            ? .accepted : .rejected
        let evidence = LLMCorrectionEvidence(
            change: LLMCorrectionChange(
                start: 0,
                end: observation.context.currentValue.count,
                originalValue: observation.context.currentValue,
                replacementValue: observation.replacementValue,
                context: LLMCorrectionContext(
                    reading: reading,
                    leftReading: observation.context.leftReading,
                    leftValue: observation.context.leftValue)),
            outcome: outcome)
        let repetitions = max(1, Int(observation.weight.rounded()))
        try store.record(
            Array(repeating: evidence, count: repetitions),
            source: observation.source,
            at: timestamp)
        let tierAfterObservation = try matchingTier(
            key: key,
            source: observation.source,
            at: timestamp,
            policy: policy)
        if tierBeforeObservation != .longTerm, tierAfterObservation == .longTerm {
            metricRecorder(.promotion)
        } else if tierBeforeObservation == .longTerm, tierAfterObservation != .longTerm {
            metricRecorder(.demotion)
        }
    }

    func reset(_ scope: UserAdaptationResetScope) throws {
        switch scope {
        case .source(let source):
            try store.reset(source: source)
        case .all:
            try store.reset()
        case .shortTerm:
            let timestamp = now()
            let policy = policyProvider()
            try store.removeRecords { record in
                if record.source == .explicitAlwaysUse {
                    return false
                }
                return policy.memoryTier(for: record, at: timestamp) != .longTerm
            }
        case .longTerm:
            let timestamp = now()
            let policy = policyProvider()
            try store.removeRecords {
                policy.memoryTier(for: $0, at: timestamp) == .longTerm
            }
        }
    }

    private func matchingTier(
        key: LLMCorrectionEvidenceKey,
        source: LLMCorrectionEvidenceSource,
        at timestamp: Date,
        policy: EvidenceBasedUserAdaptationPolicy
    ) throws -> UserAdaptationMemoryTier? {
        guard
            let record = try store.records().first(where: {
                $0.key == key && $0.source == source
            })
        else {
            return nil
        }
        return policy.memoryTier(for: record, at: timestamp)
    }
}

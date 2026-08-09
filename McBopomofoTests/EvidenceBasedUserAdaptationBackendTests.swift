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

@Suite("Evidence-Based User Adaptation Backend Tests")
struct EvidenceBasedUserAdaptationBackendTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let query = UserAdaptationQuery(
        context: UserAdaptationContext(
            reading: "ㄧㄥ",
            currentValue: "因",
            leftReading: "ㄨㄛˇ",
            leftValue: "我"),
        candidateValues: ["因", "應"])

    private func makeRecord(
        source: LLMCorrectionEvidenceSource = .acceptedLLMCorrection,
        replacementValue: String = "應",
        accepted: Int = 1,
        rejected: Int = 0,
        sessions: Int = 1,
        acceptedAge: TimeInterval = 0,
        rejectedAge: TimeInterval? = nil
    ) -> LLMCorrectionEvidenceRecord {
        let acceptedDate = now.addingTimeInterval(-acceptedAge)
        let rejectedDate = rejectedAge.map { now.addingTimeInterval(-$0) }
        return LLMCorrectionEvidenceRecord(
            key: LLMCorrectionEvidenceKey(
                reading: "ㄧㄥ",
                originalValue: "因",
                replacementValue: replacementValue,
                leftReading: "ㄨㄛˇ",
                leftValue: "我"),
            source: source,
            acceptedCount: accepted,
            rejectedCount: rejected,
            sessionIDs: (0..<sessions).map { "session-\($0)" },
            firstSeenAt: acceptedDate,
            lastSeenAt: max(acceptedDate, rejectedDate ?? acceptedDate),
            lastAcceptedAt: accepted > 0 ? acceptedDate : nil,
            lastRejectedAt: rejected > 0 ? rejectedDate ?? now : nil)
    }

    @Test("One recent exact acceptance creates short-term memory")
    func createsShortTermSuggestion() throws {
        let suggestion = EvidenceBasedUserAdaptationPolicy().suggestion(
            for: query,
            records: [makeRecord()],
            at: now)

        let value = try #require(suggestion)
        #expect(value.replacementValue == "應")
        #expect(value.tier == .shortTerm)
        #expect(
            value.confidence
                >= EvidenceBasedUserAdaptationPolicy.minimumLocalApplicationConfidence)
    }

    @Test("Expired short-term evidence does not suggest")
    func expiresShortTermSuggestion() {
        let suggestion = EvidenceBasedUserAdaptationPolicy().suggestion(
            for: query,
            records: [makeRecord(acceptedAge: 91 * 60)],
            at: now)

        #expect(suggestion == nil)
    }

    @Test("A newer rejection blocks the matching correction")
    func rejectionBlocksSuggestion() {
        let suggestion = EvidenceBasedUserAdaptationPolicy().suggestion(
            for: query,
            records: [makeRecord(accepted: 4, rejected: 1, sessions: 2, rejectedAge: 0)],
            at: now)

        #expect(suggestion == nil)
    }

    @Test("Repeated acceptance across sessions promotes long-term memory")
    func promotesLongTermSuggestion() throws {
        let suggestion = EvidenceBasedUserAdaptationPolicy().suggestion(
            for: query,
            records: [makeRecord(accepted: 3, sessions: 2, acceptedAge: 2 * 60 * 60)],
            at: now)

        #expect(try #require(suggestion).tier == .longTerm)
    }

    @Test("Suggestion requires exact context and an available candidate")
    func requiresContextAndCandidate() {
        let differentContext = UserAdaptationQuery(
            context: UserAdaptationContext(
                reading: "ㄧㄥ",
                currentValue: "因",
                leftReading: nil,
                leftValue: nil),
            candidateValues: ["因", "應"])
        let unavailableCandidate = UserAdaptationQuery(
            context: query.context,
            candidateValues: ["因"])
        let record = makeRecord()

        #expect(
            EvidenceBasedUserAdaptationPolicy().suggestion(
                for: differentContext,
                records: [record],
                at: now) == nil)
        #expect(
            EvidenceBasedUserAdaptationPolicy().suggestion(
                for: unavailableCandidate,
                records: [record],
                at: now) == nil)
    }

    @Test("Explicit evidence has precedence")
    func explicitEvidenceHasPrecedence() throws {
        let records = [
            makeRecord(replacementValue: "應", accepted: 3, sessions: 2),
            makeRecord(
                source: .explicitAlwaysUse,
                replacementValue: "映",
                accepted: 1),
        ]
        let expandedQuery = UserAdaptationQuery(
            context: query.context,
            candidateValues: ["因", "應", "映"])

        let suggestion = EvidenceBasedUserAdaptationPolicy().suggestion(
            for: expandedQuery,
            records: records,
            at: now)

        let value = try #require(suggestion)
        #expect(value.replacementValue == "映")
        #expect(value.tier == .explicit)
    }

    @Test("Selection planner applies only high-confidence available suggestions")
    func selectionPlannerUsesSafeSuggestions() {
        let highConfidence = UserAdaptationSuggestion(
            replacementValue: "應",
            confidence: 0.95,
            tier: .shortTerm,
            source: .acceptedLLMCorrection)
        let lowConfidence = UserAdaptationSuggestion(
            replacementValue: "豪",
            confidence: 0.5,
            tier: .shortTerm,
            source: .acceptedLLMCorrection)

        let selections = UserAdaptationSelectionPlanner.selections(
            currentValues: ["因", "好"],
            candidateValues: [["因", "應"], ["好", "豪"]],
            suggestions: [highConfidence, lowConfidence])

        #expect(selections == [1, 0])
        #expect(
            UserAdaptationSelectionPlanner.selections(
                currentValues: ["因"],
                candidateValues: [["因", "應"]],
                suggestions: [highConfidence],
                minimumConfidence: 0.96) == nil)
        #expect(
            UserAdaptationSelectionPlanner.selections(
                currentValues: ["因"],
                candidateValues: [["因"]],
                suggestions: [highConfidence]) == nil)
    }

    @Test("Short-term reset preserves promoted evidence")
    func resetsOnlyShortTermEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("evidence.json")
        let firstStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            now: { now })
        let firstBackend = EvidenceBasedUserAdaptationBackend(
            store: firstStore,
            now: { now })
        let longTermObservation = UserAdaptationObservation(
            context: query.context,
            replacementValue: "應",
            outcome: .accepted,
            source: .acceptedLLMCorrection,
            weight: 2,
            timestamp: now)
        try firstBackend.observe(longTermObservation)

        let secondStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            now: { now })
        let secondBackend = EvidenceBasedUserAdaptationBackend(
            store: secondStore,
            now: { now })
        try secondBackend.observe(
            UserAdaptationObservation(
                context: query.context,
                replacementValue: "應",
                outcome: .accepted,
                source: .acceptedLLMCorrection,
                weight: 1,
                timestamp: now))
        try secondBackend.observe(
            UserAdaptationObservation(
                context: UserAdaptationContext(
                    reading: "ㄏㄠˇ",
                    currentValue: "好",
                    leftReading: nil,
                    leftValue: nil),
                replacementValue: "郝",
                outcome: .accepted,
                source: .acceptedLLMCorrection,
                weight: 1,
                timestamp: now))

        try secondBackend.reset(.shortTerm)

        let records = try secondStore.records()
        #expect(records.count == 1)
        #expect(records.first?.key.replacementValue == "應")
        #expect(records.first?.acceptedCount == 3)
        #expect(records.first?.sessionIDs.count == 2)
    }

    @Test("Backend reports promotion and demotion transitions")
    func reportsTierTransitions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("evidence.json")
        let firstStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let firstBackend = EvidenceBasedUserAdaptationBackend(
            store: firstStore,
            now: { now },
            metricRecorder: { _ in })
        let acceptedObservation = UserAdaptationObservation(
            context: query.context,
            replacementValue: "應",
            outcome: .accepted,
            source: .acceptedLLMCorrection,
            weight: 2,
            timestamp: now)
        try firstBackend.observe(acceptedObservation)

        var metrics: [UserAdaptationMetric] = []
        let secondStore = LLMCorrectionEvidenceStore(
            fileURL: fileURL,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let secondBackend = EvidenceBasedUserAdaptationBackend(
            store: secondStore,
            now: { now },
            metricRecorder: { metrics.append($0) })
        try secondBackend.observe(
            UserAdaptationObservation(
                context: query.context,
                replacementValue: "應",
                outcome: .accepted,
                source: .acceptedLLMCorrection,
                weight: 1,
                timestamp: now))
        try secondBackend.observe(
            UserAdaptationObservation(
                context: query.context,
                replacementValue: "應",
                outcome: .rejected,
                source: .acceptedLLMCorrection,
                weight: 1,
                timestamp: now))

        #expect(metrics == [.promotion, .demotion])
    }

    @Test("Backend policy provider applies tuning changes immediately")
    func appliesPolicyChangesImmediately() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LLMCorrectionEvidenceStore(
            fileURL: directory.appendingPathComponent("evidence.json"))
        try store.record(
            [
                LLMCorrectionEvidence(
                    change: LLMCorrectionChange(
                        start: 0,
                        end: 1,
                        originalValue: "因",
                        replacementValue: "應",
                        context: LLMCorrectionContext(
                            reading: "ㄧㄥ",
                            leftReading: "ㄨㄛˇ",
                            leftValue: "我")),
                    outcome: .accepted
                )
            ], at: now.addingTimeInterval(-120))

        var maximumAge: TimeInterval = 60
        let backend = EvidenceBasedUserAdaptationBackend(
            store: store,
            policyProvider: {
                EvidenceBasedUserAdaptationPolicy(
                    shortTermMaximumAge: maximumAge)
            },
            now: { now })

        #expect(try backend.suggestion(for: query) == nil)
        maximumAge = 180
        #expect(try backend.suggestion(for: query)?.replacementValue == "應")
    }
}

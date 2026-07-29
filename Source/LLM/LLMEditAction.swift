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

struct LLMRerankHypothesis {
    let text: String
    let score: Double
}

struct LLMLocalCandidate {
    let start: Int
    let length: Int
    let value: String
    let score: Double
    let candidateRank: Int
}

struct LLMEditAction: Equatable {
    let start: Int
    let end: Int
    let replacement: String
    let sourceRank: Int
    let sourceScore: Double
    let components: Int
    let localScoreDelta: Double?
}

enum LLMEditActionGenerator {
    private struct ActionKey: Hashable {
        let start: Int
        let end: Int
        let replacement: String
    }

    private struct SpanKey: Hashable {
        let start: Int
        let end: Int
    }

    private struct NodeKey: Hashable {
        let start: Int
        let length: Int
    }

    private static let particles: Set<Character> = ["的", "得", "地"]

    static func generate(
        input: String,
        hypotheses: [LLMRerankHypothesis],
        localCandidates: [LLMLocalCandidate],
        limit: Int = 20,
        maxGroupCharacters: Int = 4,
        alternativesPerSpan: Int = 5
    ) -> [LLMEditAction] {
        guard limit > 0, !hypotheses.isEmpty else {
            return []
        }
        let inputCharacters = Array(input)

        var directByKey: [ActionKey: LLMEditAction] = [:]
        for (offset, hypothesis) in hypotheses.enumerated() {
            for span in diffSpans(original: input, candidate: hypothesis.text) {
                if shouldFilterAction(
                    inputCharacters: inputCharacters,
                    start: span.start,
                    end: span.end,
                    replacement: span.replacement
                ) {
                    continue
                }
                keepBetter(
                    .init(
                        start: span.start,
                        end: span.end,
                        replacement: span.replacement,
                        sourceRank: offset + 1,
                        sourceScore: hypothesis.score,
                        components: 1,
                        localScoreDelta: nil
                    ),
                    in: &directByKey
                )
            }
        }

        let pathStarts = Set(directByKey.values.map(\.start))
        let localNodes = Dictionary(grouping: localCandidates) {
            NodeKey(start: $0.start, length: $0.length)
        }
        var localFallbacksByKey: [ActionKey: LLMEditAction] = [:]
        for (nodeKey, candidates) in localNodes {
            guard !pathStarts.contains(nodeKey.start) else {
                continue
            }
            guard
                nodeKey.start >= 0,
                nodeKey.length > 0,
                nodeKey.start + nodeKey.length <= inputCharacters.count
            else {
                continue
            }
            let original = String(
                inputCharacters[nodeKey.start..<(nodeKey.start + nodeKey.length)])
            let originalCandidates = candidates.filter { $0.value == original }
            guard
                originalCandidates.map(\.candidateRank).min() == 1,
                let originalScore = originalCandidates.map(\.score).max()
            else {
                continue
            }
            for candidate in candidates {
                let end = nodeKey.start + nodeKey.length
                let normalizedOriginal = normalizedComparisonText(original)
                let normalizedReplacement = normalizedComparisonText(candidate.value)
                if candidate.value == original
                    || candidate.candidateRank > 5
                    || candidate.value.count != nodeKey.length
                    || normalizedOriginal == normalizedReplacement
                    || shouldFilterAction(
                        inputCharacters: inputCharacters,
                        start: nodeKey.start,
                        end: end,
                        replacement: candidate.value
                    )
                {
                    continue
                }
                let delta = candidate.score - originalScore
                if delta < -0.15 {
                    continue
                }
                keepBetter(
                    .init(
                        start: nodeKey.start,
                        end: end,
                        replacement: candidate.value,
                        sourceRank: 1000 + candidate.candidateRank,
                        sourceScore: candidate.score,
                        components: 1,
                        localScoreDelta: delta
                    ),
                    in: &localFallbacksByKey
                )
            }
        }

        var localFallbacks = Array(localFallbacksByKey.values)
        localFallbacks.sort(by: localFallbackRanksBefore)
        var bestLocalByStart: [Int: LLMEditAction] = [:]
        for action in localFallbacks where bestLocalByStart[action.start] == nil {
            bestLocalByStart[action.start] = action
        }
        let diverseFallbacks = bestLocalByStart.values.sorted(by: localFallbackRanksBefore)
        let diverseKeys = Set(diverseFallbacks.map(actionKey))
        localFallbacks = diverseFallbacks
            + localFallbacks.filter { !diverseKeys.contains(actionKey($0)) }

        let bySpan = Dictionary(grouping: directByKey.values) {
            SpanKey(start: $0.start, end: $0.end)
        }
        var directActions: [LLMEditAction] = []
        for actions in bySpan.values {
            directActions.append(
                contentsOf: actions.sorted(by: directRanksBefore)
                    .prefix(alternativesPerSpan))
        }

        let actionsByStart = Dictionary(grouping: directActions, by: \.start)
        var combinedByKey: [ActionKey: LLMEditAction] = [:]

        func extendChain(_ chain: [LLMEditAction], nextStart: Int) {
            guard let first = chain.first, let last = chain.last else {
                return
            }
            if chain.count > 1 {
                keepBetter(
                    .init(
                        start: first.start,
                        end: last.end,
                        replacement: chain.map(\.replacement).joined(),
                        sourceRank: chain.map(\.sourceRank).max() ?? first.sourceRank,
                        sourceScore: chain.map(\.sourceScore).reduce(0, +),
                        components: chain.count,
                        localScoreDelta: nil
                    ),
                    in: &combinedByKey
                )
            }
            if chain.count >= maxGroupCharacters {
                return
            }
            for action in actionsByStart[nextStart] ?? [] {
                if action.end - first.start > maxGroupCharacters {
                    continue
                }
                extendChain(chain + [action], nextStart: action.end)
            }
        }

        for action in directActions {
            extendChain([action], nextStart: action.end)
        }

        directActions.sort(by: directRanksBefore)
        let rankedCombinations = combinedByKey.values.sorted(by: combinationRanksBefore)
        let combinationBudget = min(rankedCombinations.count, limit / 4)
        let fallbackBudget = min(localFallbacks.count, max(1, limit / 10))
        let directBudget = limit - combinationBudget - fallbackBudget

        var bestDirectByStart: [Int: LLMEditAction] = [:]
        for action in directActions where bestDirectByStart[action.start] == nil {
            bestDirectByStart[action.start] = action
        }
        var selectedDirect = Array(bestDirectByStart.values)
            .sorted(by: directRanksBefore)
            .prefix(directBudget)
            .map { $0 }
        var selectedDirectKeys = Set(selectedDirect.map(actionKey))
        for action in directActions where selectedDirect.count < directBudget {
            if selectedDirectKeys.insert(actionKey(action)).inserted {
                selectedDirect.append(action)
            }
        }

        var selected = selectedDirect
            + Array(rankedCombinations.prefix(combinationBudget))
            + Array(localFallbacks.prefix(fallbackBudget))
        var uniqueSelected: [LLMEditAction] = []
        var selectedKeys: Set<ActionKey> = []
        for action in selected + directActions + rankedCombinations + localFallbacks {
            if selectedKeys.insert(actionKey(action)).inserted {
                uniqueSelected.append(action)
            }
            if uniqueSelected.count >= limit {
                break
            }
        }
        selected = uniqueSelected
        selected.sort(by: finalRanksBefore)
        return selected
    }

    static func applying(
        actionIDs: [Int],
        to input: String,
        actions: [LLMEditAction]
    ) -> String? {
        guard actionIDs.count == Set(actionIDs).count else {
            return nil
        }
        var selected: [LLMEditAction] = []
        for actionID in actionIDs {
            guard actionID >= 0, actionID < actions.count else {
                return nil
            }
            selected.append(actions[actionID])
        }
        selected.sort {
            ($0.start, $0.end) < ($1.start, $1.end)
        }
        let inputCharacters = Array(input)
        var previousEnd = 0
        for action in selected {
            guard
                action.start >= previousEnd,
                action.start >= 0,
                action.end > action.start,
                action.end <= inputCharacters.count,
                action.replacement.count == action.end - action.start
            else {
                return nil
            }
            previousEnd = action.end
        }

        var result = inputCharacters
        for action in selected.reversed() {
            result.replaceSubrange(
                action.start..<action.end,
                with: Array(action.replacement))
        }
        return String(result)
    }

    private static func diffSpans(
        original: String,
        candidate: String
    ) -> [(start: Int, end: Int, replacement: String)] {
        let originalCharacters = Array(original)
        let candidateCharacters = Array(candidate)
        guard originalCharacters.count == candidateCharacters.count else {
            return []
        }
        var spans: [(Int, Int, String)] = []
        var start: Int?
        for index in originalCharacters.indices {
            if originalCharacters[index] != candidateCharacters[index], start == nil {
                start = index
            }
            if originalCharacters[index] == candidateCharacters[index], let spanStart = start {
                spans.append(
                    (spanStart, index, String(candidateCharacters[spanStart..<index])))
                start = nil
            }
        }
        if let start {
            spans.append(
                (start, originalCharacters.count, String(candidateCharacters[start...])))
        }
        return spans
    }

    private static func shouldFilterAction(
        inputCharacters: [Character],
        start: Int,
        end: Int,
        replacement: String
    ) -> Bool {
        guard start >= 0, end <= inputCharacters.count, end > start else {
            return true
        }
        let original = Array(inputCharacters[start..<end])
        let replacementCharacters = Array(replacement)
        guard original.count == replacementCharacters.count else {
            return false
        }
        let differences = zip(original, replacementCharacters).filter {
            $0.0 != $0.1
        }
        guard !differences.isEmpty else {
            return true
        }
        if differences.allSatisfy({
            particles.contains($0.0) && particles.contains($0.1)
        }) {
            return true
        }
        if differences.allSatisfy({
            guard let left = asciiLetter($0.0), let right = asciiLetter($0.1) else {
                return false
            }
            return String(left).lowercased() == String(right).lowercased()
        }) {
            var tokenEnd = end
            while tokenEnd < inputCharacters.count,
                asciiLetter(inputCharacters[tokenEnd]) != nil
            {
                tokenEnd += 1
            }
            if tokenEnd == inputCharacters.count {
                return true
            }
        }
        return false
    }

    private static func asciiLetter(_ character: Character) -> Unicode.Scalar? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else {
            return nil
        }
        let value = scalar.value
        guard (65...90).contains(value) || (97...122).contains(value) else {
            return nil
        }
        return scalar
    }

    private static func normalizedComparisonText(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func actionKey(_ action: LLMEditAction) -> ActionKey {
        .init(
            start: action.start,
            end: action.end,
            replacement: action.replacement)
    }

    private static func keepBetter(
        _ action: LLMEditAction,
        in actions: inout [ActionKey: LLMEditAction]
    ) {
        let key = actionKey(action)
        guard let existing = actions[key] else {
            actions[key] = action
            return
        }
        let proposed = betterActionTuple(action)
        let current = betterActionTuple(existing)
        if proposed.0 < current.0
            || (proposed.0 == current.0 && proposed.1 < current.1)
            || (proposed.0 == current.0 && proposed.1 == current.1
                && proposed.2 < current.2)
        {
            actions[key] = action
        }
    }

    private static func betterActionTuple(
        _ action: LLMEditAction
    ) -> (Int, Double, Int) {
        (action.sourceRank, -action.sourceScore, -action.components)
    }

    private static func directRanksBefore(
        _ left: LLMEditAction,
        _ right: LLMEditAction
    ) -> Bool {
        if left.sourceRank != right.sourceRank {
            return left.sourceRank < right.sourceRank
        }
        if left.sourceScore != right.sourceScore {
            return left.sourceScore > right.sourceScore
        }
        if left.start != right.start {
            return left.start < right.start
        }
        if left.end != right.end {
            return left.end < right.end
        }
        return left.replacement < right.replacement
    }

    private static func localFallbackRanksBefore(
        _ left: LLMEditAction,
        _ right: LLMEditAction
    ) -> Bool {
        let leftDelta = left.localScoreDelta ?? -.infinity
        let rightDelta = right.localScoreDelta ?? -.infinity
        if leftDelta != rightDelta {
            return leftDelta > rightDelta
        }
        return directRanksBefore(left, right)
    }

    private static func combinationRanksBefore(
        _ left: LLMEditAction,
        _ right: LLMEditAction
    ) -> Bool {
        let leftAverage = Double(left.sourceRank) / Double(left.components)
        let rightAverage = Double(right.sourceRank) / Double(right.components)
        if leftAverage != rightAverage {
            return leftAverage < rightAverage
        }
        if left.sourceRank != right.sourceRank {
            return left.sourceRank < right.sourceRank
        }
        if left.components != right.components {
            return left.components > right.components
        }
        let leftLength = left.end - left.start
        let rightLength = right.end - right.start
        if leftLength != rightLength {
            return leftLength > rightLength
        }
        return directRanksBefore(left, right)
    }

    private static func finalRanksBefore(
        _ left: LLMEditAction,
        _ right: LLMEditAction
    ) -> Bool {
        let leftAverage = Double(left.sourceRank) / Double(left.components)
        let rightAverage = Double(right.sourceRank) / Double(right.components)
        if leftAverage != rightAverage {
            return leftAverage < rightAverage
        }
        if left.sourceRank != right.sourceRank {
            return left.sourceRank < right.sourceRank
        }
        if left.components != right.components {
            return left.components > right.components
        }
        if left.start != right.start {
            return left.start < right.start
        }
        return left.replacement < right.replacement
    }
}

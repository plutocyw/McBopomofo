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

import CandidateUI
import Cocoa
import InputMethodKit
import NotifierUI
import OpenCCBridge
import SystemCharacterInfo
import TooltipUI

extension Bool {
    fileprivate var state: NSControl.StateValue {
        self ? .on : .off
    }
}

private let kMinKeyLabelSize: CGFloat = 10

internal var gCurrentCandidateController: CandidateController?

struct GoogleGenerateContentThinkingConfig: Encodable {
    let thinkingBudget: Int?
    let thinkingLevel: String?
}

struct GoogleGenerateContentIntegerSchema: Encodable {
    let type = "integer"
    let minimum: Int
    let maximum: Int
}

struct GoogleGenerateContentArraySchema: Encodable {
    let type = "array"
    let items: GoogleGenerateContentIntegerSchema
    let minItems: Int
    let maxItems: Int
}

struct GoogleGenerateContentGenerationConfig: Encodable {
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int
    let candidateCount: Int?
    let responseMimeType: String
    let responseJsonSchema: GoogleGenerateContentArraySchema?
    let thinkingConfig: GoogleGenerateContentThinkingConfig

    init(
        modelName: String,
        thinkingLevel: LLMGoogleThinkingLevel,
        actionCount: Int? = nil
    ) {
        // Gemini 3 thinking tokens share the response budget with the visible
        // answer. Leave enough headroom so a short rewrite is not truncated.
        if let actionCount, actionCount > 0 {
            maxOutputTokens = 64
            responseMimeType = "application/json"
            responseJsonSchema = .init(
                items: .init(minimum: 0, maximum: actionCount - 1),
                minItems: 0,
                maxItems: actionCount
            )
        } else {
            maxOutputTokens = 1024
            responseMimeType = "text/plain"
            responseJsonSchema = nil
        }

        let normalizedModelName = modelName.lowercased()
        let usesLatestRequestFormat =
            normalizedModelName.hasPrefix("gemini-3.6")
            || normalizedModelName == "gemini-3.5-flash-lite"
            || normalizedModelName == "gemini-flash-latest"
        if usesLatestRequestFormat {
            temperature = nil
            topP = nil
            candidateCount = nil
            thinkingConfig = .init(
                thinkingBudget: nil,
                thinkingLevel: thinkingLevel.thinkingLevel
            )
        } else {
            temperature = 0
            topP = 1
            candidateCount = 1
            thinkingConfig = .init(
                thinkingBudget: thinkingLevel.thinkingBudget,
                thinkingLevel: nil
            )
        }
    }
}

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

extension CandidateController {
    static let horizontal = HorizontalCandidateController()
    static let vertical = VerticalCandidateController()
}

@objc(McBopomofoInputMethodController)
class McBopomofoInputMethodController: IMKInputController {

    private static let tooltipController = TooltipController()
    private static let cloudPromptCandidateLimitPerSegment = 12

    // MARK: -

    var currentClient: Any?
    var keyHandler: KeyHandler = KeyHandler()
    var state: InputState = InputState.Empty()
    private var activeCandidateRankingToken: CandidateRankingContextToken?
    private var dispatchedCandidateRankingToken: CandidateRankingContextToken?
    private var pendingManualCandidateSelectionRequest = false
    private var manualCandidateSelectionToken: CandidateRankingContextToken?
    private var pendingCandidateRankingWorkItem: DispatchWorkItem?
    private var pendingInputtingCandidateRankingWorkItem: DispatchWorkItem?
    private var lastCandidateRankingDispatchAt = Date.distantPast
    private var activeInputtingRankingToken: CandidateRankingContextToken?
    private var dispatchedInputtingRankingToken: CandidateRankingContextToken?
    private var lastInputtingRankingSignature: String?
    private var skipNextInputtingRankingSchedule = false
    private var suppressInputtingRankingAfterManualCandidateSelection = false
    private var manualSelectionSuppressedBufferLength = 0
    private let candidateRankingQueue = DispatchQueue(
        label: "org.openvanilla.McBopomofo.CandidateRanking",
        qos: .userInitiated
    )

    private struct InputtingRankingContext {
        let token: CandidateRankingContextToken
        let composingBuffer: String
        let segments: [InputtingSegmentContext]
        let editActions: [LLMEditAction]?
    }

    private struct InputtingSegmentContext {
        let startCursor: Int
        let reading: String
        let currentValue: String
        let candidates: [InputState.Candidate]
    }

    private struct InputtingRewriteResponse {
        let provider: String
        let prompt: String
        let rawResponse: String?
        let elapsedMs: Int
        let rewrittenBuffer: String?
        let selections: [Int]?
        let actionIDs: [Int]?
        let fallbackReason: String?
        let errorDescription: String?

        init(
            provider: String,
            prompt: String,
            rawResponse: String?,
            elapsedMs: Int,
            rewrittenBuffer: String?,
            selections: [Int]?,
            actionIDs: [Int]? = nil,
            fallbackReason: String?,
            errorDescription: String?
        ) {
            self.provider = provider
            self.prompt = prompt
            self.rawResponse = rawResponse
            self.elapsedMs = elapsedMs
            self.rewrittenBuffer = rewrittenBuffer
            self.selections = selections
            self.actionIDs = actionIDs
            self.fallbackReason = fallbackReason
            self.errorDescription = errorDescription
        }
    }

    // Share the stored issues, so a set of issues is shown as notification only once.
    static var latestUserFileIssues: [String] = []

    // MARK: - IMKInputController methods

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        keyHandler.delegate = self
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Input Method Menu")

        let chineseConversionItem = menu.addItem(
            withTitle: NSLocalizedString("Convert to Simplified Chinese", comment: ""),
            action: #selector(toggleChineseConverter(_:)), keyEquivalent: "g")
        chineseConversionItem.keyEquivalentModifierMask = [.command, .control]
        chineseConversionItem.state = Preferences.chineseConversionEnabled.state

        let halfWidthPunctuationItem = menu.addItem(
            withTitle: NSLocalizedString("Use Half-Width Punctuations", comment: ""),
            action: #selector(toggleHalfWidthPunctuation(_:)), keyEquivalent: "h")
        halfWidthPunctuationItem.keyEquivalentModifierMask = [.command, .control]
        halfWidthPunctuationItem.state = Preferences.halfWidthPunctuationEnabled.state
        let associatedPhrasesItem = menu.addItem(
            withTitle: NSLocalizedString("Associated Phrases", comment: ""),
            action: #selector(toggleAssociatedPhrasesEnabled(_:)), keyEquivalent: "")
        associatedPhrasesItem.state = Preferences.associatedPhrasesEnabled.state

        let inputMode = keyHandler.inputMode

        // Only Bopomofo mode supports Bopomofo Font Annotation. If support is
        // on, ensure that the user has a way to disable it. Otherwise, only
        // show the item when it is set to show in the input menu.
        if inputMode == .bopomofo
            && (Preferences.showBopomofoFontAnnotationSupportItemInInputMenu
                || Preferences.bopomofoFontAnnotationSupportEnabled)
        {
            let bopomofoFontAnnotationSupportItem = menu.addItem(
                withTitle: NSLocalizedString("Bopomofo Font Annotation Support", comment: ""),
                action: #selector(toggleBopomofoFontAnnotationSupport(_:)), keyEquivalent: "")
            bopomofoFontAnnotationSupportItem.state =
                Preferences.bopomofoFontAnnotationSupportEnabled.state
        }

        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
        if inputMode == .bopomofo && optionKeyPressed {
            let phaseReplacementItem = menu.addItem(
                withTitle: NSLocalizedString("Use Phrase Replacement", comment: ""),
                action: #selector(togglePhraseReplacement(_:)), keyEquivalent: "")
            phaseReplacementItem.state = Preferences.phraseReplacementEnabled.state
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: NSLocalizedString("User Phrases", comment: ""), action: nil,
            keyEquivalent: "")

        if inputMode == .plainBopomofo {
            if Preferences.enableUserPhrasesInPlainBopomofo {
                menu.addItem(
                    withTitle: NSLocalizedString("Edit User Phrases", comment: ""),
                    action: #selector(openUserPhrasesPlainBopomofo(_:)), keyEquivalent: "")
            }
            menu.addItem(
                withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""),
                action: #selector(openExcludedPhrasesPlainBopomofo(_:)), keyEquivalent: "")
        } else {
            menu.addItem(
                withTitle: NSLocalizedString("Edit User Phrases", comment: ""),
                action: #selector(openUserPhrases(_:)), keyEquivalent: "")
            menu.addItem(
                withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""),
                action: #selector(openExcludedPhrasesMcBopomofo(_:)), keyEquivalent: "")
            if optionKeyPressed {
                menu.addItem(
                    withTitle: NSLocalizedString("Edit Phrase Replacement Table", comment: ""),
                    action: #selector(openPhraseReplacementMcBopomofo(_:)), keyEquivalent: "")
            }
        }

        menu.addItem(
            withTitle: NSLocalizedString("Reload User Phrases", comment: ""),
            action: #selector(reloadUserPhrases(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Log Candidate Ranking Stats", comment: ""),
            action: #selector(logCandidateRankingStats(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Reset Candidate Ranking Stats", comment: ""),
            action: #selector(resetCandidateRankingStats(_:)), keyEquivalent: "")

        if !McBopomofoInputMethodController.latestUserFileIssues.isEmpty {
            // Setting menuItem.image does not work in input method menus even on macOS 26,
            // so we just use the alert emoji in the menu item title.
            let menuItem = NSMenuItem(
                title: NSLocalizedString("Show Issues in User Files ⚠️", comment: ""),
                action: #selector(showUserFileIssues(_:)), keyEquivalent: "")
            menu.addItem(menuItem)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: NSLocalizedString("McBopomofo Preferences", comment: ""),
            action: #selector(showPreferences(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Check for Updates…", comment: ""),
            action: #selector(checkForUpdate(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("About McBopomofo…", comment: ""),
            action: #selector(showAbout(_:)), keyEquivalent: "")
        return menu
    }

    // MARK: - IMKStateSetting protocol methods

    override func activateServer(_ client: Any!) {
        UserDefaults.standard.synchronize()

        // Override the keyboard layout. Use US if not set.
        (client as? IMKTextInput)?.overrideKeyboard(
            withKeyboardNamed: Preferences.basisKeyboardLayout)
        // reset the state
        currentClient = client

        keyHandler.clear()
        keyHandler.syncWithPreferences()

        (NSApp.delegate as? AppDelegate)?.checkForUpdate()
    }

    override func deactivateServer(_ client: Any!) {
        currentClient = nil
        keyHandler.clear()
        self.handle(state: .Deactivated(), client: client)
    }

    override func setValue(_ value: Any!, forTag tag: Int, client: Any!) {
        let newInputMode = InputMode(rawValue: value as? String ?? InputMode.bopomofo.rawValue)
        LanguageModelManager.loadDataModel(newInputMode)
        if keyHandler.inputMode != newInputMode {
            UserDefaults.standard.synchronize()
            // Remember to override the keyboard layout again -- treat this as an activate event.
            (client as? IMKTextInput)?.overrideKeyboard(
                withKeyboardNamed: Preferences.basisKeyboardLayout)
            keyHandler.clear()
            keyHandler.inputMode = newInputMode
            self.handle(state: .Empty(), client: client)
        }

        // Since setValue is called after activateServer, show user file issues here, if any.
        checkUserFileIssues()
    }

    // MARK: - IMKServerInput protocol methods

    override func commitComposition(_ client: Any!) {
        keyHandler.handleForceCommit(stateCallback: { newState in
            self.handle(state: newState, client: client)
        })
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        let events: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        return Int(events.rawValue)
    }

    override func handle(_ maybeEvent: NSEvent!, client: Any!) -> Bool {
        // nil may be passed, applefeedback://FB11472618
        guard let event = maybeEvent else {
            commitComposition(client)
            return false
        }

        if event.type == .flagsChanged {
            if state is InputState.Empty {
                return false
            }
            // Handle key up events during active input state.
            //
            // This prevents double-space from affecting the current input.
            // While macOS may normally insert a period on double space, this
            // should be suppressed when there is an active composing buffer or
            // candidate window.
            return true
        }

        if event.type == .flagsChanged {
            let functionKeyKeyboardLayoutID = Preferences.functionKeyboardLayout
            let basisKeyboardLayoutID = Preferences.basisKeyboardLayout

            if functionKeyKeyboardLayoutID == basisKeyboardLayoutID {
                return false
            }

            let includeShift = Preferences.functionKeyKeyboardLayoutOverrideIncludeShiftKey
            let notShift = NSEvent.ModifierFlags(rawValue: ~(NSEvent.ModifierFlags.shift.rawValue))
            if event.modifierFlags.contains(notShift)
                || (event.modifierFlags.contains(.shift) && includeShift)
            {
                (client as? IMKTextInput)?.overrideKeyboard(
                    withKeyboardNamed: functionKeyKeyboardLayoutID)
                return false
            }
            (client as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: basisKeyboardLayoutID)
            return false
        }

        var textFrame = NSRect.zero
        let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(
            forCharacterIndex: 0, lineHeightRectangle: &textFrame)
        let useVerticalMode =
            (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
        let input = KeyHandlerInput(event: event, isVerticalMode: useVerticalMode)
        pendingManualCandidateSelectionRequest = isManualCandidateSelectionRequest(input: input)

        let result = keyHandler.handle(input: input, state: state) { newState in
            self.handle(state: newState, client: client)
        } errorCallback: {
            if Preferences.beepUponInputError {
                NSSound.beep()
            }
        }
        return result
    }

    // MARK: - Menu Items

    @objc override func showPreferences(_ sender: Any?) {
        super.showPreferences(sender)
    }

    @objc func toggleChineseConverter(_ sender: Any?) {
        let enabled = Preferences.toggleChineseConversionEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Chinese Conversion On", comment: "")
                : NSLocalizedString("Chinese Conversion Off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleHalfWidthPunctuation(_ sender: Any?) {
        let enabled = Preferences.toggleHalfWidthPunctuationEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Half-Width Punctuation On", comment: "")
                : NSLocalizedString("Half-Width Punctuation Off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleAssociatedPhrasesEnabled(_ sender: Any?) {
        _ = Preferences.toggleAssociatedPhrasesEnabled()
    }

    @objc func toggleBopomofoFontAnnotationSupport(_ sender: Any?) {
        let enabled = Preferences.toggleBopomofoFontAnnotationSupportEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Bopomofo Font Annotation Support On", comment: "")
                : NSLocalizedString("Bopomofo Font Annotation Support Off", comment: ""))
    }

    @objc func togglePhraseReplacement(_ sender: Any?) {
        let enabled = Preferences.togglePhraseReplacementEnabled()
        LanguageModelManager.phraseReplacementEnabled = enabled
    }

    @objc func checkForUpdate(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.checkForUpdate(forced: true)
    }

    @objc func openUserPhrases(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrases(sender)
    }

    @objc func openUserPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesMcBopomofo(sender)
    }

    @objc func openPhraseReplacementMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openPhraseReplacementMcBopomofo(sender)
    }

    @objc func reloadUserPhrases(_ sender: Any?) {
        LanguageModelManager.loadUserPhrases(
            enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        LanguageModelManager.loadUserPhraseReplacement()

        // Empty the issues so that if there are still the same issues, a
        // notification will be shown.
        McBopomofoInputMethodController.latestUserFileIssues = []
        checkUserFileIssues()
    }

    @objc func logCandidateRankingStats(_ sender: Any?) {
        let snapshot = CandidateRankingStats.currentSnapshot()
        NSLog(
            "CandidateRankingStats snapshot scheduled=%d applied=%d staleDropped=%d timeoutFallback=%d invalidResultFallback=%d parserFallback=%d",
            snapshot.scheduled,
            snapshot.applied,
            snapshot.staleDropped,
            snapshot.timeoutFallback,
            snapshot.invalidResultFallback,
            snapshot.parserFallback
        )
        let message = String(
            format:
                "LLM ranking stats\nscheduled=%d\napplied=%d\nstaleDropped=%d\ntimeoutFallback=%d\ninvalidResultFallback=%d\nparserFallback=%d",
            snapshot.scheduled,
            snapshot.applied,
            snapshot.staleDropped,
            snapshot.timeoutFallback,
            snapshot.invalidResultFallback,
            snapshot.parserFallback
        )

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Candidate Ranking Stats", comment: "")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = message
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }

    @objc func resetCandidateRankingStats(_ sender: Any?) {
        CandidateRankingStats.reset()
        NSLog("CandidateRankingStats reset")
    }

    @objc func showUserFileIssues(_ sender: Any?) {
        let header = NSLocalizedString(
            "Issues were found in the following user phrase files:", comment: "")
        let report =
            header + "\n\n"
            + McBopomofoInputMethodController.latestUserFileIssues.joined(separator: "\n")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss.SSS"
        let dateString = formatter.string(from: now)
        let fileName = "UserFileIssues-\(dateString).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
        } catch {
            NSLog("Failed to write report to temporary file: \(error)")
            return
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

}

// MARK: - State Handling

extension McBopomofoInputMethodController {

    func handle(state newState: InputState, client: Any?) {
        let previous = state
        state = newState
        activeCandidateRankingToken = (newState as? InputState.ChoosingCandidate)?.rankingContextToken
        if let inputtingState = newState as? InputState.Inputting {
            activeInputtingRankingToken = CandidateRankingContextToken()
            dispatchedInputtingRankingToken = nil
            lastInputtingRankingSignature = nil
            if skipNextInputtingRankingSchedule {
                skipNextInputtingRankingSchedule = false
            } else {
                scheduleInputtingCandidateRankingIfNeeded(for: inputtingState, client: client)
            }
        } else {
            activeInputtingRankingToken = nil
            dispatchedInputtingRankingToken = nil
            pendingInputtingCandidateRankingWorkItem?.cancel()
            pendingInputtingCandidateRankingWorkItem = nil
            lastInputtingRankingSignature = nil
            skipNextInputtingRankingSchedule = false
        }
        if !(newState is InputState.ChoosingCandidate) {
            manualCandidateSelectionToken = nil
        }

        switch newState {
        case let newState as InputState.Deactivated:
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
        case let newState as InputState.Empty:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.EmptyIgnoringPreviousState:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Committing:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Inputting:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Marking:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ChoosingCandidate:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrases:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrasesPlain:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingFeature:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingDateMacro:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Number:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.IcuTransform:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Big5:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingDictionary:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ShowingCharInfo:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.CustomMenu:
            handle(state: newState, previous: previous, client: client)
        default:
            break
        }
    }

    func isCurrentCandidateRankingToken(_ token: CandidateRankingContextToken) -> Bool {
        guard
            let currentState = state as? InputState.ChoosingCandidate,
            let activeToken = activeCandidateRankingToken
        else {
            return false
        }
        return currentState.rankingContextToken == token && activeToken == token
    }

    private func commit(text: String, client: Any!) {

        func convertToSimplifiedChineseIfRequired(_ text: String) -> String {
            if !Preferences.chineseConversionEnabled {
                return text
            }
            if Preferences.chineseConversionStyle == .model {
                return text
            }
            return OpenCCBridge.shared.convertToSimplified(text) ?? ""
        }

        let buffer = convertToSimplifiedChineseIfRequired(text)
        if buffer.isEmpty {
            return
        }
        (client as? IMKTextInput)?.insertText(
            buffer, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func handle(state: InputState.Deactivated, previous: InputState, client: Any?) {
        currentClient = nil

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        switch previous {
        case let previous as InputState.NotEmpty:
            commit(text: previous.composingBuffer, client: client)
        case is InputState.Big5,
            is InputState.Number,
            is InputState.IcuTransform:
            client.setMarkedText(
                "", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(0, 0))
        default:
            break
        }

        // Unlike the Empty state handler, we don't call client.setMarkedText() here:
        // there's no point calling setMarkedText() with an empty string as the session
        // is being deactivated anyway, and we have found issues with how certains app
        // could not handle setMarkedText() at this point (see GitHub issue #346).
    }

    private func handle(state: InputState.Empty, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(
        state: InputState.EmptyIgnoringPreviousState, previous: InputState, client: Any!
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Committing, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        let poppedText = state.poppedText
        if !poppedText.isEmpty {
            commit(text: poppedText, client: client)
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Inputting, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))

        if suppressInputtingRankingAfterManualCandidateSelection,
            Int(state.cursorIndex) == state.composingBuffer.count,
            state.composingBuffer.count > manualSelectionSuppressedBufferLength
        {
            suppressInputtingRankingAfterManualCandidateSelection = false
            manualSelectionSuppressedBufferLength = 0
        }

        if !state.tooltip.isEmpty {
            show(
                tooltip: state.tooltip, composingBuffer: state.composingBuffer,
                cursorIndex: state.cursorIndex, client: client)
        }
    }

    private func handle(state: InputState.Marking, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        guard let client = client as? IMKTextInput else {
            hideTooltip()
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))

        if state.tooltip.isEmpty {
            hideTooltip()
        } else {
            show(
                tooltip: state.tooltip, composingBuffer: state.composingBuffer,
                cursorIndex: state.markerIndex, client: client)
        }
    }

    private func handle(state: InputState.ChoosingCandidate, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        if pendingManualCandidateSelectionRequest {
            manualCandidateSelectionToken = state.rankingContextToken
            suppressInputtingRankingAfterManualCandidateSelection = true
            manualSelectionSuppressedBufferLength = state.composingBuffer.count
        }
        pendingManualCandidateSelectionRequest = false

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.AssociatedPhrases, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }

        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Inputting:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(
        state: InputState.AssociatedPhrasesPlain, previous: InputState, client: Any?
    ) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.SelectingFeature, previous: InputState, client: Any?) {
        handleStateWithSimpleCandidateWindow(state: state, previous: previous, client: client)
    }

    private func handle(state: InputState.SelectingDateMacro, previous: InputState, client: Any?) {
        handleStateWithSimpleCandidateWindow(state: state, previous: previous, client: client)
    }

    private func handleSpecialInputWithCandidateWindow(state: InputState, composingBuffer: String, candidateCount: Int, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        client.setMarkedText(
            composingBuffer,
            selectionRange: NSMakeRange(
                (composingBuffer as NSString).length,
                0
            ),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound)
        )
        if candidateCount > 0 {
            show(candidateWindowWith: state, client: client)
        }
    }


    private func handle(state: InputState.Number, previous: InputState, client: Any?) {
        handleSpecialInputWithCandidateWindow(state: state, composingBuffer: state.composingBuffer, candidateCount: state.candidateCount, client: client)
    }

    private func handle(state: InputState.IcuTransform, previous: InputState, client: Any?) {
        handleSpecialInputWithCandidateWindow(state: state, composingBuffer: state.composingBuffer, candidateCount: state.candidateCount, client: client)
    }

    private func handle(state: InputState.Big5, previous: InputState, client: Any?) {
        handleStateForCustomInput(
            composingBuffer: state.composingBuffer, previous: previous, client: client)
    }

    private func handle(state: InputState.SelectingDictionary, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer

        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Marking:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.ShowingCharInfo, previous: InputState, client: Any?) {

        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Marking:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.CustomMenu, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        show(candidateWindowWith: state, client: client)
    }
}

// MARK: -

extension McBopomofoInputMethodController {
    private func handleStateForCustomInput(
        composingBuffer: String, previous: InputState, client: Any?
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText(
            composingBuffer, selectionRange: NSMakeRange(composingBuffer.utf16.count, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handleStateWithSimpleCandidateWindow(
        state: InputState, previous: InputState, client: Any?
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func show(candidateWindowWith state: InputState, client: Any!) {
        let useVerticalMode: Bool = {
            var useVerticalMode = false
            var candidates: [InputState.Candidate] = []
            switch state {
            case let state as InputState.ChoosingCandidate:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrasesPlain:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrases:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case is InputState.SelectingFeature,
                is InputState.SelectingDateMacro,
                is InputState.SelectingDictionary,
                is InputState.ShowingCharInfo,
                is InputState.Number,
                is InputState.IcuTransform:
                return true
            default:
                break
            }

            if useVerticalMode == true {
                return true
            }
            candidates.sort {
                return $0.displayText.count > $1.displayText.count
            }
            // If there is a candidate which is too long, we use the vertical
            // candidate list window automatically.
            if candidates.first?.displayText.count ?? 0 > 8 {
                return true
            }
            return false
        }()

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false

        if useVerticalMode {
            gCurrentCandidateController = .vertical
        } else if Preferences.useHorizontalCandidateList {
            gCurrentCandidateController = .horizontal
        } else {
            gCurrentCandidateController = .vertical
        }

        gCurrentCandidateController?.tooltip =
            switch state {
            case let state as InputState.SelectingDictionary:
                String(format: NSLocalizedString("Look up %@", comment: ""), state.selectedPhrase)
            case let state as InputState.AssociatedPhrases:
                String(format: NSLocalizedString("%@…", comment: ""), state.prefixValue)
            case let state as InputState.CustomMenu:
                state.title
            default:
                ""
            }

        // set the attributes for the candidate panel (which uses NSAttributedString)
        let textSize = Preferences.candidateListTextSize
        let keyLabelSize = max(textSize / 2, kMinKeyLabelSize)

        func font(name: String?, size: CGFloat) -> NSFont {
            if let name = name {
                return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
            }
            return NSFont.systemFont(ofSize: size)
        }

        gCurrentCandidateController?.keyLabelFont = font(
            name: Preferences.candidateKeyLabelFontName, size: keyLabelSize)
        gCurrentCandidateController?.candidateFont = font(
            name: Preferences.candidateTextFontName, size: textSize)

        let candidateKeys = Preferences.candidateKeys
        let keyLabels =
            candidateKeys.count >= 4
            ? Array(candidateKeys) : Array(Preferences.defaultCandidateKeys)

        let keyLabelFormat: (String)->String = switch state {
        case let state as InputState.AssociatedPhrases where state.autoTriggered:
            { _ in "⇧ ⏎" }
        case is InputState.AssociatedPhrasesPlain,
            is InputState.Number,
            is InputState.IcuTransform:
            { "⇧ " + $0 }
        default:
            { $0 }
        }
        gCurrentCandidateController?.keyLabels = keyLabels.map {
            CandidateKeyLabel(key: String($0), displayedText: keyLabelFormat(String($0)))
        }

        gCurrentCandidateController?.delegate = self
        gCurrentCandidateController?.reloadData()
        currentClient = client

        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = 0

        if let state = state as? InputState.NotEmpty {
            cursor = Int(state.cursorIndex)
            if cursor == state.composingBuffer.count && cursor != 0 {
                cursor -= 1
            }
        }

        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            (client as? IMKTextInput)?.attributes(
                forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            cursor -= 1
        }

        if useVerticalMode {
            gCurrentCandidateController?.set(
                windowTopLeftPoint: NSMakePoint(
                    lineHeightRect.origin.x + lineHeightRect.size.width + 4.0,
                    lineHeightRect.origin.y - 4.0),
                bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        } else {
            gCurrentCandidateController?.set(
                windowTopLeftPoint: NSMakePoint(
                    lineHeightRect.origin.x, lineHeightRect.origin.y - 4.0),
                bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        }

        gCurrentCandidateController?.visible = true
    }

    private func show(tooltip: String, composingBuffer: String, cursorIndex: UInt, client: Any!) {
        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = Int(cursorIndex)
        if cursor == composingBuffer.count && cursor != 0 {
            cursor -= 1
        }

        var isVerticalMode = false
        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(
                forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            let useVerticalMode =
                (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
            isVerticalMode = isVerticalMode || useVerticalMode
            cursor -= 1
        }

        // Make sure that tooltip hovers next to the vertical text.
        if isVerticalMode && lineHeightRect.size.height > 0 {
            lineHeightRect.origin.x += (lineHeightRect.size.width + 1.0)
        }

        McBopomofoInputMethodController.tooltipController.show(
            tooltip: tooltip, at: lineHeightRect.origin)
    }

    private func hideTooltip() {
        McBopomofoInputMethodController.tooltipController.hide()
    }

    private func checkUserFileIssues() {
        let issues: [String] = keyHandler.collectUserFileIssues()

        // McBopomofoLM caps the maximum number of issues collected, and so
        // we'll just do this O(n) comparison since n is small.
        if McBopomofoInputMethodController.latestUserFileIssues != issues {
            McBopomofoInputMethodController.latestUserFileIssues = issues

            if !McBopomofoInputMethodController.latestUserFileIssues.isEmpty {
                NotifierController.notify(
                    message: NSLocalizedString(
                        "Check McBopomofo menu for user file issues", comment: ""), stay: true)
            }
        }
    }

    private func scheduleCandidateRankingIfNeeded(
        for state: InputState.ChoosingCandidate,
        client: Any
    ) {
        // Candidate-list reranking is intentionally disabled.
        _ = state
        _ = client
    }

    private func isCurrentInputtingRankingToken(_ token: CandidateRankingContextToken) -> Bool {
        guard state is InputState.Inputting else {
            return false
        }
        return activeInputtingRankingToken == token
    }

    private func scheduleInputtingCandidateRankingIfNeeded(
        for state: InputState.Inputting,
        client: Any?
    ) {
        guard Preferences.llmCandidateRankingEnabled else {
            return
        }
        guard !suppressInputtingRankingAfterManualCandidateSelection else {
            return
        }
        guard shouldTriggerInputtingRanking(for: state) else {
            return
        }
        guard let client else {
            return
        }
        guard let token = activeInputtingRankingToken else {
            return
        }
        let segments = buildInputtingSegmentContexts()
        guard !segments.isEmpty else {
            return
        }
        if !segments.contains(where: { $0.candidates.count > 1 }) {
            return
        }

        let editActions: [LLMEditAction]?
        if Preferences.llmEditActionRerankingEnabled {
            guard let generatedActions = buildInputtingEditActions(for: state),
                !generatedActions.isEmpty
            else {
                return
            }
            editActions = generatedActions
        } else {
            editActions = nil
        }

        let signature = makeInputtingRankingSignature(
            from: state,
            segments: segments,
            editActions: editActions)
        if signature == lastInputtingRankingSignature {
            return
        }
        lastInputtingRankingSignature = signature

        pendingInputtingCandidateRankingWorkItem?.cancel()
        let context = InputtingRankingContext(
            token: token,
            composingBuffer: state.composingBuffer,
            segments: segments,
            editActions: editActions
        )
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.dispatchInputtingCandidateRanking(context: context, client: client)
        }
        pendingInputtingCandidateRankingWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + candidateRankingDebounceIntervalSeconds,
            execute: workItem
        )
    }

    private func buildInputtingSegmentContexts() -> [InputtingSegmentContext] {
        let rawContexts = keyHandler.buildSegmentCandidateContexts() as [[String: Any]]
        return rawContexts.compactMap { raw in
            guard
                let startCursor = raw["startCursor"] as? NSNumber,
                let reading = raw["reading"] as? String,
                let currentValue = raw["currentValue"] as? String,
                let candidates = raw["candidates"] as? [InputState.Candidate]
            else {
                return nil
            }
            return InputtingSegmentContext(
                startCursor: startCursor.intValue,
                reading: reading,
                currentValue: currentValue,
                candidates: candidates
            )
        }
    }

    private func makeInputtingRankingSignature(
        from state: InputState.Inputting,
        segments: [InputtingSegmentContext],
        editActions: [LLMEditAction]?
    ) -> String {
        let segmentPart = segments.map { segment in
            let candidatesPart = segment.candidates.map { "\($0.reading)|\($0.value)|\($0.rawValue)" }
                .joined(separator: "^")
            return "\(segment.startCursor)|\(segment.reading)|\(segment.currentValue)|\(candidatesPart)"
        }.joined(separator: "||")
        let actionPart = editActions?.map {
            "\($0.start)|\($0.end)|\($0.replacement)"
        }.joined(separator: "^") ?? "v1"
        return "\(state.composingBuffer)#\(state.cursorIndex)#\(segmentPart)#\(actionPart)"
    }

    private func buildInputtingEditActions(
        for state: InputState.Inputting
    ) -> [LLMEditAction]? {
        guard
            let rawContext = keyHandler.buildLLMEditActionCandidateContext(limit: 20),
            let input = rawContext["input"] as? String,
            input == state.composingBuffer,
            let rawHypotheses = rawContext["hypotheses"] as? [[String: Any]],
            let rawLocalCandidates = rawContext["localCandidates"] as? [[String: Any]]
        else {
            return nil
        }

        let hypotheses = rawHypotheses.compactMap { raw -> LLMRerankHypothesis? in
            guard
                let text = raw["text"] as? String,
                let score = raw["score"] as? NSNumber
            else {
                return nil
            }
            return .init(text: text, score: score.doubleValue)
        }
        let localCandidates = rawLocalCandidates.compactMap {
            raw -> LLMLocalCandidate? in
            guard
                let start = raw["start"] as? NSNumber,
                let length = raw["length"] as? NSNumber,
                let value = raw["value"] as? String,
                let score = raw["score"] as? NSNumber,
                let candidateRank = raw["candidateRank"] as? NSNumber
            else {
                return nil
            }
            return .init(
                start: start.intValue,
                length: length.intValue,
                value: value,
                score: score.doubleValue,
                candidateRank: candidateRank.intValue)
        }
        guard !hypotheses.isEmpty else {
            return nil
        }
        return LLMEditActionGenerator.generate(
            input: input,
            hypotheses: hypotheses,
            localCandidates: localCandidates)
    }

    private func shouldTriggerInputtingRanking(for state: InputState.Inputting) -> Bool {
        switch Preferences.llmInputtingTriggerMode {
        case .continuous:
            return true
        case .segmentEnd:
            guard Int(state.cursorIndex) == state.composingBuffer.count else {
                return false
            }
            guard let lastScalar = state.composingBuffer.unicodeScalars.last else {
                return false
            }
            let segmentEndCharacterSet =
                CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
            return segmentEndCharacterSet.contains(lastScalar)
        }
    }

    private func dispatchInputtingCandidateRanking(context: InputtingRankingContext, client: Any) {
        guard isCurrentInputtingRankingToken(context.token) else {
            return
        }

        let elapsed = Date().timeIntervalSince(lastCandidateRankingDispatchAt)
        if elapsed < candidateRankingMinIntervalSeconds {
            let delay = candidateRankingMinIntervalSeconds - elapsed
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.dispatchInputtingCandidateRanking(context: context, client: client)
            }
            return
        }

        dispatchedInputtingRankingToken = context.token
        lastCandidateRankingDispatchAt = Date()
        CandidateRankingStats.record(.scheduled)
        notifyLLMActivity(state: .running)

        candidateRankingQueue.async { [weak self] in
            guard let self else {
                return
            }
            let result = self.rankWholeInputtingBuffer(context: context)
            DispatchQueue.main.async {
                self.applyInputtingCandidateRankingResult(result, context: context, client: client)
            }
        }
    }

    private func applyInputtingCandidateRankingResult(
        _ result: InputtingRewriteResponse,
        context: InputtingRankingContext,
        client: Any
    ) {
        guard isCurrentInputtingRankingToken(context.token) else {
            CandidateRankingStats.record(.staleDropped)
            notifyLLMActivity(state: .fallback)
            return
        }
        guard state is InputState.Inputting else {
            return
        }
        guard !context.segments.isEmpty else {
            return
        }

        showLLMInputtingRewriteDebugAlertIfNeeded(context: context, result: result)

        if let editActions = context.editActions {
            guard
                let actionIDs = result.actionIDs,
                let rewrittenBuffer = result.rewrittenBuffer,
                LLMEditActionGenerator.applying(
                    actionIDs: actionIDs,
                    to: context.composingBuffer,
                    actions: editActions) == rewrittenBuffer
            else {
                CandidateRankingStats.record(.invalidResultFallback)
                notifyLLMActivity(state: .fallback)
                return
            }
            if actionIDs.isEmpty {
                notifyLLMActivity(state: .applied)
                return
            }
            guard keyHandler.applyComposedTextCandidatePath(rewrittenBuffer) else {
                CandidateRankingStats.record(.invalidResultFallback)
                notifyLLMActivity(state: .fallback)
                return
            }
            guard
                let rerankedInputtingState =
                    keyHandler.buildInputtingState() as? InputState.Inputting
            else {
                CandidateRankingStats.record(.invalidResultFallback)
                notifyLLMActivity(state: .fallback)
                return
            }
            CandidateRankingStats.record(.applied)
            notifyLLMActivity(state: .applied)
            skipNextInputtingRankingSchedule = true
            handle(state: rerankedInputtingState, client: client)
            return
        }

        guard let selections = result.selections else {
            CandidateRankingStats.record(.invalidResultFallback)
            notifyLLMActivity(state: .fallback)
            return
        }
        guard selections.count == context.segments.count else {
            CandidateRankingStats.record(.invalidResultFallback)
            notifyLLMActivity(state: .fallback)
            return
        }
        var hasNonZeroSelection = false
        for (index, selected) in selections.enumerated() {
            let count = context.segments[index].candidates.count
            if selected < 0 || selected >= count {
                CandidateRankingStats.record(.invalidResultFallback)
                notifyLLMActivity(state: .fallback)
                return
            }
            if selected != 0 {
                hasNonZeroSelection = true
            }
        }
        if !hasNonZeroSelection {
            notifyLLMActivity(state: .applied)
            return
        }
        guard
            keyHandler.applySegmentCandidateOverrides(
                selections: selections.map { NSNumber(value: $0) })
        else {
            CandidateRankingStats.record(.invalidResultFallback)
            notifyLLMActivity(state: .fallback)
            return
        }

        guard let rerankedInputtingState = keyHandler.buildInputtingState() as? InputState.Inputting else {
            return
        }
        CandidateRankingStats.record(.applied)
        notifyLLMActivity(state: .applied)
        skipNextInputtingRankingSchedule = true
        handle(state: rerankedInputtingState, client: client)
    }

    private func rankWholeInputtingBuffer(context: InputtingRankingContext) -> InputtingRewriteResponse {
        let prompt = makeInputtingRewritePrompt(context: context)
        let startNs = DispatchTime.now().uptimeNanoseconds
        switch Preferences.llmCloudProvider {
        case .google:
            return rankWholeInputtingBufferWithGoogleCloud(
                prompt: prompt, context: context, startNs: startNs)
        case .openAI:
            return rankWholeInputtingBufferWithOpenAI(
                prompt: prompt, context: context, startNs: startNs)
        }
    }

    private func rankWholeInputtingBufferWithGoogleCloud(
        prompt: String,
        context: InputtingRankingContext,
        startNs: UInt64
    ) -> InputtingRewriteResponse {
        struct GenerateContentRequest: Encodable {
            struct Content: Encodable {
                struct Part: Encodable {
                    let text: String
                }
                let parts: [Part]
            }

            struct SystemInstruction: Encodable {
                struct Part: Encodable {
                    let text: String
                }
                let parts: [Part]
            }

            let systemInstruction: SystemInstruction
            let contents: [Content]
            let generationConfig: GoogleGenerateContentGenerationConfig
        }
        struct GenerateContentResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        let provider = "GoogleCloud"
        let timeout = max(0.05, Double(Preferences.llmCandidateRankingTimeoutMs) / 1000.0)
        let endpointBase = Preferences.llmGoogleEndpoint.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !endpointBase.isEmpty else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyCloudEndpoint",
                errorDescription: nil
            )
        }
        let modelName = normalizeGoogleModelName(Preferences.llmGoogleModelName)
        guard !modelName.isEmpty else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyCloudModelName",
                errorDescription: nil
            )
        }
        let apiKey = Preferences.llmGoogleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyGoogleAPIKey",
                errorDescription: nil
            )
        }
        guard let endpoint = makeGoogleGenerateContentURL(baseEndpoint: endpointBase, modelName: modelName) else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "invalidCloudEndpoint",
                errorDescription: nil
            )
        }

        let systemInstruction =
            context.editActions == nil
            ? "You are an IME same-pronunciation correction engine. Output the corrected sentence exactly once. The output must have exactly the same character count as the input sentence. Do not repeat, add, or omit any character. Output no analysis, explanation, formatting, or chain-of-thought."
            : "You are a Traditional Chinese IME correction action selector for Taiwan. Compare every proposed action in its word and sentence context and select every necessary, mutually non-overlapping action. Return an empty array only when every proposed replacement is worse or provides no linguistic improvement. Return only a JSON array of integer action IDs. Do not explain your answer."
        let body = GenerateContentRequest(
            systemInstruction: .init(
                parts: [
                    .init(text: systemInstruction)
                ]),
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(
                modelName: modelName,
                thinkingLevel: Preferences.llmGoogleThinkingLevel,
                actionCount: context.editActions?.count
            )
        )
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "jsonEncodeFailed",
                errorDescription: nil
            )
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = jsonData
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()

        let wait = semaphore.wait(timeout: .now() + timeout + 0.05)
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)
        if wait == .timedOut {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: elapsedMs,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "requestTimeout",
                errorDescription: nil
            )
        }
        guard let responseData else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: elapsedMs,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyResponse",
                errorDescription: responseError.map { "\($0)" }
            )
        }
        let rawResponse = String(data: responseData, encoding: .utf8)
        guard
            let parsed = try? JSONDecoder().decode(GenerateContentResponse.self, from: responseData),
            let candidate = parsed.candidates?.first,
            let parts = candidate.content?.parts
        else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: rawResponse,
                elapsedMs: elapsedMs,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "invalidJSON",
                errorDescription: nil
            )
        }
        let responseText = parts.compactMap(\.text).joined()
        if let editActions = context.editActions {
            let parsedActionResult = parseInputtingEditActionResponse(
                from: responseText,
                input: context.composingBuffer,
                actions: editActions)
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: responseText,
                elapsedMs: elapsedMs,
                rewrittenBuffer: parsedActionResult?.rewrittenBuffer,
                selections: nil,
                actionIDs: parsedActionResult?.actionIDs,
                fallbackReason: parsedActionResult == nil ? "parserFallback" : nil,
                errorDescription: nil
            )
        }
        let rewrittenBuffer = parseInputtingRewrittenBuffer(
            from: responseText,
            expectedCharacterCount: context.composingBuffer.count
        )
        let selections = rewrittenBuffer.flatMap {
            mapRewrittenBufferToSelections($0, segments: context.segments)
        }
        return InputtingRewriteResponse(
            provider: provider,
            prompt: prompt,
            rawResponse: responseText,
            elapsedMs: elapsedMs,
            rewrittenBuffer: rewrittenBuffer,
            selections: selections,
            fallbackReason: selections == nil ? "parserFallback" : nil,
            errorDescription: nil
        )
    }

    private func rankWholeInputtingBufferWithOpenAI(
        prompt: String,
        context: InputtingRankingContext,
        startNs: UInt64
    ) -> InputtingRewriteResponse {
        struct ChatCompletionsRequest: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let messages: [Message]
            let temperature: Double
        }
        struct ChatCompletionsResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]?
        }

        let provider = "OpenAICloud"
        let timeout = max(0.05, Double(Preferences.llmCandidateRankingTimeoutMs) / 1000.0)
        let endpointText = Preferences.llmOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpointText.isEmpty else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyCloudEndpoint",
                errorDescription: nil
            )
        }
        let modelName = Preferences.llmOpenAIModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyCloudModelName",
                errorDescription: nil
            )
        }
        let apiKey = Preferences.llmOpenAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyOpenAIAPIKey",
                errorDescription: nil
            )
        }
        guard let endpoint = URL(string: endpointText) else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "invalidCloudEndpoint",
                errorDescription: nil
            )
        }

        let systemInstruction =
            context.editActions == nil
            ? "You are an IME same-pronunciation correction engine. Output only the corrected sentence. Never output analysis or chain-of-thought."
            : "You are a Traditional Chinese IME correction action selector for Taiwan. Compare every proposed action in its word and sentence context and select every necessary, mutually non-overlapping action. Return an empty array only when every proposed replacement is worse or provides no linguistic improvement. Return only a JSON array of integer action IDs. Do not explain your answer."
        let body = ChatCompletionsRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemInstruction),
                .init(role: "user", content: prompt),
            ],
            temperature: 0
        )
        guard let jsonData = try? JSONEncoder().encode(body) else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: 0,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "jsonEncodeFailed",
                errorDescription: nil
            )
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()

        let wait = semaphore.wait(timeout: .now() + timeout + 0.05)
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)
        if wait == .timedOut {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: elapsedMs,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "requestTimeout",
                errorDescription: nil
            )
        }
        guard let responseData else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: nil,
                elapsedMs: elapsedMs,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "emptyResponse",
                errorDescription: responseError.map { "\($0)" }
            )
        }
        let rawResponse = String(data: responseData, encoding: .utf8)
        guard
            let parsed = try? JSONDecoder().decode(ChatCompletionsResponse.self, from: responseData),
            let responseText = parsed.choices?.first?.message.content
        else {
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: rawResponse,
                elapsedMs: elapsedMs,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: "invalidJSON",
                errorDescription: nil
            )
        }

        if let editActions = context.editActions {
            let parsedActionResult = parseInputtingEditActionResponse(
                from: responseText,
                input: context.composingBuffer,
                actions: editActions)
            return InputtingRewriteResponse(
                provider: provider,
                prompt: prompt,
                rawResponse: responseText,
                elapsedMs: elapsedMs,
                rewrittenBuffer: parsedActionResult?.rewrittenBuffer,
                selections: nil,
                actionIDs: parsedActionResult?.actionIDs,
                fallbackReason: parsedActionResult == nil ? "parserFallback" : nil,
                errorDescription: nil
            )
        }
        let rewrittenBuffer = parseInputtingRewrittenBuffer(
            from: responseText,
            expectedCharacterCount: context.composingBuffer.count
        )
        let selections = rewrittenBuffer.flatMap {
            mapRewrittenBufferToSelections($0, segments: context.segments)
        }
        return InputtingRewriteResponse(
            provider: provider,
            prompt: prompt,
            rawResponse: responseText,
            elapsedMs: elapsedMs,
            rewrittenBuffer: rewrittenBuffer,
            selections: selections,
            fallbackReason: selections == nil ? "parserFallback" : nil,
            errorDescription: nil
        )
    }

    private func normalizeGoogleModelName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if trimmed.hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    private func makeGoogleGenerateContentURL(baseEndpoint: String, modelName: String) -> URL? {
        let trimmedBase = baseEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmedBase)/models/\(modelName):generateContent")
    }

    private func makeInputtingRewritePrompt(context: InputtingRankingContext) -> String {
        if let editActions = context.editActions {
            return makeInputtingEditActionPrompt(
                input: context.composingBuffer,
                actions: editActions)
        }
        return makeGoogleCloudInputtingRewritePrompt(context: context)
    }

    private func makeInputtingEditActionPrompt(
        input: String,
        actions: [LLMEditAction]
    ) -> String {
        let actionLines = renderInputtingEditActions(input: input, actions: actions)
        return """
            你是台灣繁體中文注音輸入法的選字糾錯引擎。
            輸入句是輸入法選出的第一版，可能含有少數同音錯字。下面每個 action 都來自輸入法的合法候選路徑。
            請逐一比較 action 所列出的詞組與「套用後」上下文。如果替換能形成更自然的詞語、固定搭配、專有名稱或完整語意，就選擇該 action。
            不要把空陣列當成預設答案。只有當所有 actions 都讓原句變差或沒有語言上的改善時，才輸出 []。
            不可選擇互相重疊的 actions。不要只為文體偏好或網路用語的英文大小寫而修改。
            如果詞組 action 能完整修正同一個詞，優先選擇詞組 action，不要再選其中重疊的單字 action。
            只輸出 action ID 的 JSON array，不要解釋或輸出 Markdown。

            輸入法第一版：\(input)
            Action 數量：\(actions.count)

            Actions:
            \(actionLines)
            """
    }

    private func renderInputtingEditActions(
        input: String,
        actions: [LLMEditAction]
    ) -> String {
        let inputCharacters = Array(input)
        return actions.enumerated().compactMap { actionID, action -> String? in
            guard
                action.start >= 0,
                action.end > action.start,
                action.end <= inputCharacters.count
            else {
                return nil
            }
            let original = String(inputCharacters[action.start..<action.end])
            let position =
                action.end == action.start + 1
                ? "第 \(action.start + 1) 字"
                : "第 \(action.start + 1)-\(action.end) 字"
            var line =
                "[\(actionID)] \(position)：\(original) -> \(action.replacement)"

            var windows: [String] = []
            let windowRanges = [
                (max(0, action.start - 1), action.end),
                (action.start, min(inputCharacters.count, action.end + 1)),
                (action.start, min(inputCharacters.count, action.end + 2)),
            ]
            for (windowStart, windowEnd) in windowRanges
            where windowEnd - windowStart > action.end - action.start {
                let before = Array(inputCharacters[windowStart..<windowEnd])
                let relativeStart = action.start - windowStart
                let relativeEnd = action.end - windowStart
                var after = before
                after.replaceSubrange(
                    relativeStart..<relativeEnd,
                    with: Array(action.replacement))
                let comparison = "\(String(before)) -> \(String(after))"
                if !windows.contains(comparison) {
                    windows.append(comparison)
                }
            }
            if !windows.isEmpty {
                line += "；詞組比較：\(windows.joined(separator: " | "))"
            }

            let contextStart = max(0, action.start - 5)
            let contextEnd = min(inputCharacters.count, action.end + 5)
            var appliedContext = Array(inputCharacters[contextStart..<contextEnd])
            appliedContext.replaceSubrange(
                (action.start - contextStart)..<(action.end - contextStart),
                with: Array(action.replacement))
            line += "；套用後：\(String(appliedContext))"
            return line
        }.joined(separator: "\n")
    }

    private func makeGoogleCloudInputtingRewritePrompt(context: InputtingRankingContext) -> String {
        let segmentLines = context.segments.enumerated().map { index, segment -> String in
            let candidates = segment.candidates.prefix(Self.cloudPromptCandidateLimitPerSegment).enumerated().map {
                localIndex, candidate in
                "[\(localIndex)] \(candidate.value)"
            }.joined(separator: " | ")
            return """
                Segment \(index)
                - reading: \(segment.reading)
                - current: \(segment.currentValue)
                - candidates: \(candidates)
                """
        }.joined(separator: "\n")

        return """
            你是「繁體中文注音輸入法選字糾錯引擎」。
            任務：修正同音錯字，但只能在輸入法候選內做替換。

            硬性規則（必須遵守）：
            1) 你必須對每個 Segment 選一個候選詞。
            2) 只能從該 Segment 的 candidates 清單中選，不可使用清單外字詞。
            3) 依 Segment 原順序串接，不可調換順序。
            4) 不可新增字、不可刪字。
            5) 若不確定，選 current 對應的候選。
            6) 只輸出最終整句，不要解釋、JSON、Markdown。

            輸入句子：\(context.composingBuffer)
            Segment 數量：\(context.segments.count)

            Segments:
            \(segmentLines)
            """
    }

    private func parseInputtingEditActionResponse(
        from text: String,
        input: String,
        actions: [LLMEditAction]
    ) -> (rewrittenBuffer: String, actionIDs: [Int])? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = extractJSONArrayCandidates(from: normalized) + [normalized]
        var checked: Set<String> = []
        for candidate in candidates where checked.insert(candidate).inserted {
            guard
                let data = candidate.data(using: .utf8),
                let actionIDs = try? JSONDecoder().decode([Int].self, from: data),
                let rewrittenBuffer = LLMEditActionGenerator.applying(
                    actionIDs: actionIDs,
                    to: input,
                    actions: actions)
            else {
                continue
            }
            return (rewrittenBuffer, actionIDs)
        }
        return nil
    }

    private func parseInputtingRewrittenBuffer(
        from text: String,
        expectedCharacterCount: Int
    ) -> String? {
        guard expectedCharacterCount > 0 else {
            return nil
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        func decodeArray(_ candidate: String) -> [String]? {
            guard let data = candidate.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode([String].self, from: data)
        }

        let candidates = extractJSONArrayCandidates(from: normalized)
        for candidate in candidates {
            guard let array = decodeArray(candidate) else {
                continue
            }
            guard array.count == expectedCharacterCount else {
                continue
            }
            guard array.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            guard array.allSatisfy({ $0.count == 1 }) else {
                continue
            }
            let placeholderSet = Set(["字", "X", "x"])
            if array.allSatisfy({ placeholderSet.contains($0) }) {
                continue
            }
            return array.joined()
        }
        var plain = normalized
        if plain.hasPrefix("```") && plain.hasSuffix("```") {
            plain = plain.replacingOccurrences(of: "```json", with: "")
            plain = plain.replacingOccurrences(of: "```", with: "")
            plain = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if plain.hasPrefix("\""), plain.hasSuffix("\""), let data = plain.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(String.self, from: data)
        {
            plain = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let firstLine = plain
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? plain
        if firstLine.count == expectedCharacterCount, !firstLine.isEmpty {
            return firstLine
        }

        return nil
    }

    private func extractJSONArrayCandidates(from text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }
        var results: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaping = false

        for index in text.indices {
            let ch = text[index]

            if inString {
                if escaping {
                    escaping = false
                    continue
                }
                if ch == "\\" {
                    escaping = true
                    continue
                }
                if ch == "\"" {
                    inString = false
                }
                continue
            }

            if ch == "\"" {
                inString = true
                continue
            }

            if ch == "[" {
                if depth == 0 {
                    start = index
                }
                depth += 1
                continue
            }

            if ch == "]", depth > 0 {
                depth -= 1
                if depth == 0, let startIndex = start {
                    let end = text.index(after: index)
                    results.append(String(text[startIndex..<end]))
                    start = nil
                }
            }
        }
        if results.isEmpty {
            results = [text]
        }
        return results
    }

    private func mapRewrittenBufferToSelections(
        _ rewrittenBuffer: String,
        segments: [InputtingSegmentContext]
    ) -> [Int]? {
        guard !segments.isEmpty else {
            return nil
        }

        let originalReading = LanguageModelManager.reading(for: segments.map(\.currentValue).joined())
        let rewrittenReading = LanguageModelManager.reading(for: rewrittenBuffer)
        if let originalReading, let rewrittenReading, originalReading != rewrittenReading {
            return nil
        }

        let rewrittenNSString = rewrittenBuffer as NSString
        let totalLength = rewrittenNSString.length
        var memo: [String: [Int]?] = [:]

        func solve(_ segmentIndex: Int, _ offset: Int) -> [Int]? {
            let key = "\(segmentIndex)#\(offset)"
            if let cached = memo[key] {
                return cached
            }
            if segmentIndex == segments.count {
                let result: [Int]? = (offset == totalLength) ? [] : nil
                memo[key] = result
                return result
            }
            if offset > totalLength {
                memo[key] = nil
                return nil
            }

            let candidates = segments[segmentIndex].candidates
            for (candidateIndex, candidate) in candidates.enumerated() {
                let valueNSString = candidate.value as NSString
                let valueLength = valueNSString.length
                if offset + valueLength > totalLength {
                    continue
                }
                let candidateRange = NSRange(location: offset, length: valueLength)
                let rewrittenSlice = rewrittenNSString.substring(with: candidateRange)
                if rewrittenSlice != candidate.value {
                    continue
                }
                if let suffix = solve(segmentIndex + 1, offset + valueLength) {
                    let result = [candidateIndex] + suffix
                    memo[key] = result
                    return result
                }
            }
            memo[key] = nil
            return nil
        }

        return solve(0, 0)
    }

    private func applyCandidateRankingResult(_ result: CandidateRankingResult, client: Any) {
        guard isCurrentCandidateRankingToken(result.token) else {
            CandidateRankingStats.record(.staleDropped)
            notifyLLMActivity(state: .fallback)
            return
        }
        guard let choosingState = state as? InputState.ChoosingCandidate else {
            return
        }
        guard !choosingState.candidates.isEmpty else {
            return
        }
        let rankedCandidateCount = result.orderedCandidateIndices.count
        let isInvalidRankingResult =
            rankedCandidateCount > choosingState.candidates.count
            || !result.isValidPermutation(candidateCount: rankedCandidateCount)

        if isInvalidRankingResult {
            CandidateRankingStats.record(.invalidResultFallback)
            notifyLLMActivity(state: .fallback)
            return
        }
        guard
            let reorderedCandidates = CandidateRankingPipeline.reorderedCandidates(
                from: choosingState.candidates,
                result: result
            )
        else {
            notifyLLMActivity(state: .fallback)
            return
        }

        let rerankedState = InputState.ChoosingCandidate(
            composingBuffer: choosingState.composingBuffer,
            cursorIndex: choosingState.cursorIndex,
            candidates: reorderedCandidates,
            useVerticalMode: choosingState.useVerticalMode,
            rankingContextToken: choosingState.rankingContextToken
        )
        rerankedState.originalCursorIndex = choosingState.originalCursorIndex
        CandidateRankingStats.record(.applied)
        notifyLLMActivity(state: .applied)
        handle(state: rerankedState, client: client)
    }

    private func isManualCandidateSelectionRequest(input: KeyHandlerInput) -> Bool {
        guard state is InputState.NotEmpty else {
            return false
        }
        return input.isExtraChooseCandidateKey
            || input.charCode == 32
            || (input.useVerticalMode && input.isVerticalModeOnlyChooseCandidateKey)
    }

    private func dispatchCandidateRanking(
        request: CandidateRankingRequest,
        client: Any,
        token: CandidateRankingContextToken
    ) {
        guard isCurrentCandidateRankingToken(token) else {
            return
        }

        let elapsed = Date().timeIntervalSince(lastCandidateRankingDispatchAt)
        if elapsed < candidateRankingMinIntervalSeconds {
            let delay = candidateRankingMinIntervalSeconds - elapsed
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.dispatchCandidateRanking(request: request, client: client, token: token)
            }
            return
        }

        dispatchedCandidateRankingToken = token
        lastCandidateRankingDispatchAt = Date()
        CandidateRankingStats.record(.scheduled)
        notifyLLMActivity(state: .running)

        let ranker = TimeoutCandidateRanker(
            base: CandidateRankerFactory.makeCandidateRanker(),
            timeoutMs: Preferences.llmCandidateRankingTimeoutMs
        )
        candidateRankingQueue.async { [weak self] in
            guard let self else {
                return
            }
            let result = ranker.rank(request: request)
            DispatchQueue.main.async {
                self.showLLMDebugAlertIfNeeded(request: request, result: result)
                self.applyCandidateRankingResult(result, client: client)
            }
        }
    }

    private enum LLMActivityIndicatorState {
        case running
        case applied
        case fallback
    }

    private var candidateRankingDebounceIntervalSeconds: TimeInterval {
        Double(Preferences.llmInputtingPauseMs) / 1000.0
    }

    private var candidateRankingMinIntervalSeconds: TimeInterval {
        0.8
    }

    private func notifyLLMActivity(state: LLMActivityIndicatorState) {
        guard Preferences.llmShowActivityIndicator else {
            return
        }
        let message: String
        switch state {
        case .running:
            message = "LLM..."
        case .applied:
            message = "LLM✓"
        case .fallback:
            message = "LLM↺"
        }
        NotifierController.notify(message: message, stay: false)
    }

    private func showLLMDebugAlertIfNeeded(
        request: CandidateRankingRequest,
        result: CandidateRankingResult
    ) {
        guard Preferences.llmShowDebugAlert else {
            return
        }
        guard let trace = result.debugTrace else {
            return
        }

        let candidatesText = request.candidates.map { candidate in
            "[\(candidate.originalIndex)] reading=\(candidate.reading) display=\(candidate.displayText) value=\(candidate.value) raw=\(candidate.rawValue)"
        }.joined(separator: "\n")

        let orderedIndicesText = result.orderedCandidateIndices.map(String.init).joined(separator: ",")
        let fallback = trace.fallbackReason ?? "none"
        let errorDescription = trace.errorDescription ?? "none"
        let responseText = trace.response ?? "<nil>"
        let message = """
            Provider: \(trace.provider)
            Token: \(request.token.id.uuidString)
            Compose buffer: \(request.composingBuffer)
            Cursor index: \(request.cursorIndex)
            Candidate count: \(request.candidates.count)
            Elapsed: \(trace.elapsedMs) ms
            Fallback reason: \(fallback)
            Error: \(errorDescription)
            Ordered indices: \(orderedIndicesText)

            Prompt:
            \(trace.prompt)

            Raw response:
            \(responseText)

            Candidates:
            \(candidatesText)
            """
        showLLMDebugAlert(message: message)
    }

    private func showLLMInputtingRewriteDebugAlertIfNeeded(
        context: InputtingRankingContext,
        result: InputtingRewriteResponse
    ) {
        guard Preferences.llmShowDebugAlert else {
            return
        }
        let fallback = result.fallbackReason ?? "none"
        let errorDescription = result.errorDescription ?? "none"
        let responseText = result.rawResponse ?? "<nil>"
        let rewrittenBuffer = result.rewrittenBuffer ?? "<nil>"
        let selectedIndicesText = result.selections?.map(String.init).joined(separator: ",") ?? "<nil>"
        let actionIDsText = result.actionIDs?.map(String.init).joined(separator: ",") ?? "<nil>"
        let editActionsText =
            context.editActions.map {
                renderInputtingEditActions(
                    input: context.composingBuffer,
                    actions: $0)
            } ?? "<disabled>"
        let segmentsText = context.segments.enumerated().map { index, segment in
            let candidates = segment.candidates.enumerated().map { candidateIndex, candidate in
                "[\(candidateIndex)] \(candidate.value)"
            }.joined(separator: " | ")
            return
                "Segment \(index) start=\(segment.startCursor) reading=\(segment.reading) current=\(segment.currentValue)\n\(candidates)"
        }.joined(separator: "\n\n")

        let message = """
            Provider: \(result.provider)
            Token: \(context.token.id.uuidString)
            Compose buffer: \(context.composingBuffer)
            Segment count: \(context.segments.count)
            Elapsed: \(result.elapsedMs) ms
            Fallback reason: \(fallback)
            Error: \(errorDescription)
            Rewritten buffer: \(rewrittenBuffer)
            Selected indices: \(selectedIndicesText)
            Action IDs: \(actionIDsText)

            Prompt:
            \(result.prompt)

            Raw response:
            \(responseText)

            Segments:
            \(segmentsText)

            Edit actions:
            \(editActionsText)
            """
        showLLMDebugAlert(message: message)
    }

    private func showLLMDebugAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("LLM Ranking Debug", comment: "")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.minSize = NSSize(width: 760, height: 520)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = message
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)

        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }
}

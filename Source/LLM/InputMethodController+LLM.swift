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

import Cocoa
import NotifierUI

extension McBopomofoInputMethodController {

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

    func scheduleInputtingCandidateRankingIfNeeded(
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

        if applyUserAdaptationSuggestionIfAvailable(
            context: context,
            client: client)
        {
            CandidateRankingStats.record(.localMemoryHit)
            return
        }
        CandidateRankingStats.record(.localMemoryMiss)

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
        _ result: LLMInputtingRewriteResult,
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
            if let transaction = makeCorrectionTransaction(
                context: context,
                editActions: editActions,
                actionIDs: actionIDs)
            {
                llmCorrectionFeedbackCoordinator.begin(transaction)
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
        for (index, selected) in selections.enumerated() {
            let count = context.segments[index].candidates.count
            if selected < 0 || selected >= count {
                CandidateRankingStats.record(.invalidResultFallback)
                notifyLLMActivity(state: .fallback)
                return
            }
        }
        guard let transaction = makeCorrectionTransaction(
            context: context,
            selections: selections)
        else {
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
        llmCorrectionFeedbackCoordinator.begin(transaction)
        CandidateRankingStats.record(.applied)
        notifyLLMActivity(state: .applied)
        skipNextInputtingRankingSchedule = true
        handle(state: rerankedInputtingState, client: client)
    }

    private func makeCorrectionTransaction(
        context: InputtingRankingContext,
        selections: [Int],
        learnsAcceptance: Bool = true
    ) -> LLMCorrectionTransaction? {
        guard selections.count == context.segments.count else {
            return nil
        }
        let changes = selections.enumerated().compactMap {
            index, selection -> LLMCorrectionChange? in
            let segment = context.segments[index]
            guard selection >= 0, selection < segment.candidates.count else {
                return nil
            }
            let replacement = segment.candidates[selection].value
            guard replacement != segment.currentValue else {
                return nil
            }
            let leftSegment = index > 0 ? context.segments[index - 1] : nil
            return LLMCorrectionChange(
                start: segment.startCursor,
                end: segment.startCursor + segment.currentValue.count,
                originalValue: segment.currentValue,
                replacementValue: replacement,
                context: LLMCorrectionContext(
                    reading: segment.reading,
                    leftReading: leftSegment?.reading,
                    leftValue: leftSegment?.currentValue))
        }
        return LLMCorrectionTransaction(
            originalBuffer: context.composingBuffer,
            changes: changes,
            learnsAcceptance: learnsAcceptance)
    }

    private func applyUserAdaptationSuggestionIfAvailable(
        context: InputtingRankingContext,
        client: Any
    ) -> Bool {
        let queries = context.segments.enumerated().map { index, segment in
            let leftSegment = index > 0 ? context.segments[index - 1] : nil
            return UserAdaptationQuery(
                context: UserAdaptationContext(
                    reading: segment.reading,
                    currentValue: segment.currentValue,
                    leftReading: leftSegment?.reading,
                    leftValue: leftSegment?.currentValue),
                candidateValues: segment.candidates.map(\.value))
        }
        let suggestions: [UserAdaptationSuggestion?]
        do {
            suggestions = try userAdaptationBackend.suggestions(for: queries)
        } catch {
            NSLog("Failed to read user adaptation suggestions: \(error)")
            return false
        }
        guard suggestions.count == context.segments.count else {
            return false
        }

        guard
            let selections = UserAdaptationSelectionPlanner.selections(
                currentValues: context.segments.map(\.currentValue),
                candidateValues: context.segments.map { $0.candidates.map(\.value) },
                suggestions: suggestions,
                minimumConfidence: Double(
                    Preferences.llmCorrectionMinimumConfidencePercent) / 100)
        else {
            return false
        }
        guard
            let transaction = makeCorrectionTransaction(
                context: context,
                selections: selections,
                learnsAcceptance: false),
            keyHandler.applySegmentCandidateOverrides(
                selections: selections.map { NSNumber(value: $0) }),
            let adaptedState = keyHandler.buildInputtingState() as? InputState.Inputting
        else {
            return false
        }

        llmCorrectionFeedbackCoordinator.begin(transaction)
        skipNextInputtingRankingSchedule = true
        handle(state: adaptedState, client: client)
        return true
    }

    private func makeCorrectionTransaction(
        context: InputtingRankingContext,
        editActions: [LLMEditAction],
        actionIDs: [Int]
    ) -> LLMCorrectionTransaction? {
        let originalCharacters = Array(context.composingBuffer)
        let changes = actionIDs.compactMap { actionID -> LLMCorrectionChange? in
            guard actionID >= 0, actionID < editActions.count else {
                return nil
            }
            let action = editActions[actionID]
            guard action.start >= 0, action.end <= originalCharacters.count else {
                return nil
            }
            let originalValue = String(originalCharacters[action.start..<action.end])
            let coveredSegments = context.segments.filter { segment in
                let segmentEnd = segment.startCursor + segment.currentValue.count
                return segment.startCursor >= action.start && segmentEnd <= action.end
            }
            let leftSegment = context.segments.last { segment in
                segment.startCursor + segment.currentValue.count <= action.start
            }
            let reading = coveredSegments.isEmpty
                ? nil
                : coveredSegments.map(\.reading).joined(separator: "-")
            return LLMCorrectionChange(
                start: action.start,
                end: action.end,
                originalValue: originalValue,
                replacementValue: action.replacement,
                context: LLMCorrectionContext(
                    reading: reading,
                    leftReading: leftSegment?.reading,
                    leftValue: leftSegment?.currentValue))
        }
        return LLMCorrectionTransaction(
            originalBuffer: context.composingBuffer,
            changes: changes)
    }

    func reconcileLLMCorrectionFeedback(
        newState: InputState,
        previousState: InputState
    ) {
        switch newState {
        case let committing as InputState.Committing:
            guard previousState is InputState.NotEmpty else {
                return
            }
            finishLLMCorrectionFeedback(
                disposition: .committed,
                finalBuffer: committing.poppedText)
        case is InputState.Empty:
            guard let previous = previousState as? InputState.NotEmpty else {
                return
            }
            finishLLMCorrectionFeedback(
                disposition: .committed,
                finalBuffer: previous.composingBuffer)
        case is InputState.Deactivated:
            guard let previous = previousState as? InputState.NotEmpty else {
                return
            }
            finishLLMCorrectionFeedback(
                disposition: .committed,
                finalBuffer: previous.composingBuffer)
        case is InputState.EmptyIgnoringPreviousState:
            finishLLMCorrectionFeedback(disposition: .cancelled)
        default:
            break
        }
    }

    private func finishLLMCorrectionFeedback(
        disposition: LLMCorrectionTransactionDisposition,
        finalBuffer: String? = nil
    ) {
        let evidence = llmCorrectionFeedbackCoordinator.finish(
            disposition: disposition,
            finalBuffer: finalBuffer)
        let timestamp = Date()
        for item in evidence {
            let outcome: UserAdaptationObservationOutcome
            switch item.outcome {
            case .accepted:
                CandidateRankingStats.record(.correctionAccepted)
                outcome = .accepted
            case .rejected:
                CandidateRankingStats.record(.correctionRejected)
                if item.origin == .localMemory {
                    CandidateRankingStats.record(.postHitManualReversal)
                }
                outcome = .rejected
            case .neutral:
                continue
            }
            do {
                try userAdaptationBackend.observe(
                    UserAdaptationObservation(
                        context: UserAdaptationContext(
                            reading: item.change.context.reading,
                            currentValue: item.change.originalValue,
                            leftReading: item.change.context.leftReading,
                            leftValue: item.change.context.leftValue),
                        replacementValue: item.change.replacementValue,
                        outcome: outcome,
                        source: .acceptedLLMCorrection,
                        weight: 1,
                        timestamp: timestamp))
            } catch {
                NSLog("Failed to persist LLM correction evidence: \(error)")
            }
        }
    }

    private func rankWholeInputtingBuffer(
        context: InputtingRankingContext
    ) -> LLMInputtingRewriteResult {
        let request = LLMInputtingRewriteRequest(
            composingBuffer: context.composingBuffer,
            segments: context.segments.map { segment in
                LLMInputtingRewriteSegment(
                    reading: segment.reading,
                    currentValue: segment.currentValue,
                    candidates: segment.candidates.map(\.value))
            },
            editActions: context.editActions)
        let configuration: LLMCloudProviderConfiguration
        switch Preferences.llmCloudProvider {
        case .google:
            configuration = .google(
                baseEndpoint: Preferences.llmGoogleEndpoint,
                modelName: Preferences.llmGoogleModelName,
                apiKey: Preferences.llmGoogleAPIKey,
                thinkingLevel: Preferences.llmGoogleThinkingLevel,
                editActionCount: context.editActions?.count)
        case .openAI:
            configuration = .openAI(
                endpoint: Preferences.llmOpenAIEndpoint,
                modelName: Preferences.llmOpenAIModelName,
                apiKey: Preferences.llmOpenAIAPIKey,
                usesEditActions: context.editActions != nil)
        }
        let timeout = max(0.05, Double(Preferences.llmCandidateRankingTimeoutMs) / 1000.0)
        return LLMInputtingRewriteEngine.live.rewrite(
            request: request,
            configuration: configuration,
            timeout: timeout)
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

    func isManualCandidateSelectionRequest(input: KeyHandlerInput) -> Bool {
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
        result: LLMInputtingRewriteResult
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
                LLMInputtingRewriteEngine.renderEditActions(
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

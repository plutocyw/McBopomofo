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

struct LLMInputtingRewriteSegment {
    let reading: String
    let currentValue: String
    let candidates: [String]
}

struct LLMInputtingRewriteRequest {
    let composingBuffer: String
    let segments: [LLMInputtingRewriteSegment]
    let editActions: [LLMEditAction]?
}

struct LLMInputtingRewriteResult {
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

struct LLMInputtingRewriteEngine {
    typealias ReadingProvider = (String) -> String?

    private static let promptCandidateLimitPerSegment = 12

    static let live = LLMInputtingRewriteEngine(
        cloudClient: .live,
        readingProvider: { LanguageModelManager.reading(for: $0) })

    private let cloudClient: LLMCloudClient
    private let readingProvider: ReadingProvider

    init(
        cloudClient: LLMCloudClient,
        readingProvider: @escaping ReadingProvider
    ) {
        self.cloudClient = cloudClient
        self.readingProvider = readingProvider
    }

    func rewrite(
        request: LLMInputtingRewriteRequest,
        configuration: LLMCloudProviderConfiguration,
        timeout: TimeInterval
    ) -> LLMInputtingRewriteResult {
        let prompt = Self.makePrompt(request: request)
        let response = cloudClient.send(
            prompt: prompt,
            configuration: configuration,
            timeout: timeout)
        guard let responseText = response.responseText else {
            return LLMInputtingRewriteResult(
                provider: response.provider,
                prompt: prompt,
                rawResponse: response.rawResponse,
                elapsedMs: response.elapsedMs,
                rewrittenBuffer: nil,
                selections: nil,
                fallbackReason: response.fallbackReason,
                errorDescription: response.errorDescription)
        }

        if let editActions = request.editActions {
            let parsedActionResult = Self.parseEditActionResponse(
                from: responseText,
                input: request.composingBuffer,
                actions: editActions)
            return LLMInputtingRewriteResult(
                provider: response.provider,
                prompt: prompt,
                rawResponse: responseText,
                elapsedMs: response.elapsedMs,
                rewrittenBuffer: parsedActionResult?.rewrittenBuffer,
                selections: nil,
                actionIDs: parsedActionResult?.actionIDs,
                fallbackReason: parsedActionResult == nil ? "parserFallback" : nil,
                errorDescription: nil)
        }

        let rewrittenBuffer = Self.parseRewrittenBuffer(
            from: responseText,
            expectedCharacterCount: request.composingBuffer.count)
        let selections = rewrittenBuffer.flatMap {
            mapRewrittenBufferToSelections($0, segments: request.segments)
        }
        return LLMInputtingRewriteResult(
            provider: response.provider,
            prompt: prompt,
            rawResponse: responseText,
            elapsedMs: response.elapsedMs,
            rewrittenBuffer: rewrittenBuffer,
            selections: selections,
            fallbackReason: selections == nil ? "parserFallback" : nil,
            errorDescription: nil)
    }

    static func renderEditActions(
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

    private static func makePrompt(request: LLMInputtingRewriteRequest) -> String {
        if let editActions = request.editActions {
            return makeEditActionPrompt(
                input: request.composingBuffer,
                actions: editActions)
        }
        return makeCandidateRewritePrompt(request: request)
    }

    private static func makeEditActionPrompt(
        input: String,
        actions: [LLMEditAction]
    ) -> String {
        let actionLines = renderEditActions(input: input, actions: actions)
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

    private static func makeCandidateRewritePrompt(
        request: LLMInputtingRewriteRequest
    ) -> String {
        let segmentLines = request.segments.enumerated().map { index, segment -> String in
            let candidates = segment.candidates.prefix(promptCandidateLimitPerSegment).enumerated()
                .map { localIndex, candidate in
                    "[\(localIndex)] \(candidate)"
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

            輸入句子：\(request.composingBuffer)
            Segment 數量：\(request.segments.count)

            Segments:
            \(segmentLines)
            """
    }

    private static func parseEditActionResponse(
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

    private static func parseRewrittenBuffer(
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

    private static func extractJSONArrayCandidates(from text: String) -> [String] {
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
        segments: [LLMInputtingRewriteSegment]
    ) -> [Int]? {
        guard !segments.isEmpty else {
            return nil
        }

        let originalReading = readingProvider(segments.map(\.currentValue).joined())
        let rewrittenReading = readingProvider(rewrittenBuffer)
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
                let valueNSString = candidate as NSString
                let valueLength = valueNSString.length
                if offset + valueLength > totalLength {
                    continue
                }
                let candidateRange = NSRange(location: offset, length: valueLength)
                let rewrittenSlice = rewrittenNSString.substring(with: candidateRange)
                if rewrittenSlice != candidate {
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
}

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
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleOnDeviceCandidateRankingParser {
    static func parseOrderedIndices(from text: String, candidateCount: Int) -> [Int]? {
        guard candidateCount > 0 else {
            return nil
        }

        if let lineResult = parseFromDedicatedOrderLine(text, candidateCount: candidateCount) {
            return lineResult
        }

        let numberTokens = text.split(whereSeparator: { !$0.isNumber })
        guard !numberTokens.isEmpty else {
            return nil
        }

        var orderedIndices: [Int] = []
        var seen = Set<Int>()

        for token in numberTokens {
            guard let index = Int(token) else {
                continue
            }
            guard index >= 0 && index < candidateCount else {
                continue
            }
            if seen.insert(index).inserted {
                orderedIndices.append(index)
            }
            if orderedIndices.count == candidateCount {
                break
            }
        }

        guard orderedIndices.count == candidateCount else {
            return nil
        }
        return orderedIndices
    }

    private static func parseFromDedicatedOrderLine(_ text: String, candidateCount: Int) -> [Int]? {
        let lines = text.split(separator: "\n")
        for line in lines.reversed() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }
            guard isLikelyOrderLine(trimmedLine) else {
                continue
            }
            let content = trimmedLine
                .trimmingCharacters(in: CharacterSet(charactersIn: "[](){}"))
            let rawParts = content.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard rawParts.count == candidateCount else {
                continue
            }
            let parts = rawParts.compactMap(Int.init)
            guard parts.count == candidateCount else {
                continue
            }
            let result = CandidateRankingResult(
                token: CandidateRankingContextToken(),
                orderedCandidateIndices: parts
            )
            if result.isValidPermutation(candidateCount: candidateCount) {
                return parts
            }
        }
        return nil
    }

    private static func isLikelyOrderLine(_ line: String) -> Bool {
        for character in line {
            if character.isNumber || character == "," || character == " " || character == "\t"
                || character == "[" || character == "]" || character == "(" || character == ")"
                || character == "{" || character == "}"
            {
                continue
            }
            return false
        }
        return line.contains(",")
    }
}

struct AppleOnDeviceCandidateRanker: CandidateRanker {
    func rank(request: CandidateRankingRequest) -> CandidateRankingResult {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return rankWithFoundationModels(request: request)
            }
        #endif
        return fallbackResult(for: request)
    }

    private func fallbackResult(
        for request: CandidateRankingRequest,
        debugTrace: CandidateRankingDebugTrace? = nil
    ) -> CandidateRankingResult {
        CandidateRankingResult(
            token: request.token,
            orderedCandidateIndices: Array(request.candidates.indices),
            debugTrace: debugTrace
        )
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
extension AppleOnDeviceCandidateRanker {
    func rankWithFoundationModels(request: CandidateRankingRequest) -> CandidateRankingResult {
        let model = SystemLanguageModel.default
        let prompt = makePrompt(for: request)
        let startNs = DispatchTime.now().uptimeNanoseconds
        guard model.isAvailable else {
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "AppleOnDevice",
                    prompt: prompt,
                    response: nil,
                    elapsedMs: 0,
                    fallbackReason: "modelUnavailable",
                    errorDescription: nil
                )
            )
        }

        let instructions =
            """
            You rank Traditional Chinese input method candidates.
            Return ONLY a comma-separated list of candidate indices in best-first order.
            Do not include any other text.
            """
        let session = LanguageModelSession(model: model, tools: [], instructions: instructions)
        let options = GenerationOptions(
            sampling: .greedy,
            temperature: 0,
            maximumResponseTokens: 64
        )

        let semaphore = DispatchSemaphore(value: 0)
        var responseText: String?
        var responseErrorDescription: String?
        Task {
            defer { semaphore.signal() }
            do {
                let response = try await session.respond(to: prompt, options: options)
                responseText = response.content
            } catch {
                responseText = nil
                responseErrorDescription = "\(error)"
            }
        }
        semaphore.wait()
        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)

        guard
            let responseText,
            let orderedIndices = AppleOnDeviceCandidateRankingParser.parseOrderedIndices(
                from: responseText,
                candidateCount: request.candidates.count
            )
        else {
            if responseText != nil {
                CandidateRankingStats.record(.parserFallback)
            }
            return fallbackResult(
                for: request,
                debugTrace: CandidateRankingDebugTrace(
                    provider: "AppleOnDevice",
                    prompt: prompt,
                    response: responseText,
                    elapsedMs: elapsedMs,
                    fallbackReason: responseText == nil ? "requestFailed" : "parserFallback",
                    errorDescription: responseErrorDescription
                )
            )
        }

        let result = CandidateRankingResult(
            token: request.token,
            orderedCandidateIndices: orderedIndices,
            debugTrace: CandidateRankingDebugTrace(
                provider: "AppleOnDevice",
                prompt: prompt,
                response: responseText,
                elapsedMs: elapsedMs,
                fallbackReason: nil,
                errorDescription: nil
            )
        )
        guard result.isValidPermutation(candidateCount: request.candidates.count) else {
            let trace = result.debugTrace?.withFallbackReason("invalidPermutation")
            return fallbackResult(for: request, debugTrace: trace)
        }
        return result
    }

    private func makePrompt(for request: CandidateRankingRequest) -> String {
        let header = """
            Task: Rank Traditional Chinese IME candidates for the current input context.
            Compose buffer: \(request.composingBuffer)
            Cursor index: \(request.cursorIndex)
            Candidate count: \(request.candidates.count)
            Selection priorities:
            1) Prefer common, contextually natural Traditional Chinese words.
            2) If uncertain, keep earlier baseline order.
            3) Avoid uncommon variants unless context clearly requires them.
            """

        let candidateLines = request.candidates.map { candidate in
            let displayLength = candidate.displayText.count
            let isSingleCharacter = displayLength == 1
            let rawMatchesValue = candidate.rawValue == candidate.value
            return """
                [\(candidate.originalIndex)] reading=\(candidate.reading) display=\(candidate.displayText) value=\(candidate.value) raw=\(candidate.rawValue) len=\(displayLength) single=\(isSingleCharacter) rawMatches=\(rawMatchesValue)
                """
        }.joined(separator: "\n")

        let outputRule = """
            Output format rule:
            - Return exactly one line with \(request.candidates.count) unique indices.
            - Use comma-separated integers only.
            - No explanation, no extra words.
            Example: \(Array(0..<request.candidates.count).map(String.init).joined(separator: ","))
            """
        return [header, "Candidates:", candidateLines, outputRule].joined(separator: "\n")
    }
}
#endif

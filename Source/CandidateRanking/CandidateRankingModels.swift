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

struct CandidateRankingDebugTrace {
    let provider: String
    let prompt: String
    let response: String?
    let elapsedMs: Int
    let fallbackReason: String?
    let errorDescription: String?

    func withFallbackReason(_ reason: String) -> CandidateRankingDebugTrace {
        CandidateRankingDebugTrace(
            provider: provider,
            prompt: prompt,
            response: response,
            elapsedMs: elapsedMs,
            fallbackReason: reason,
            errorDescription: errorDescription
        )
    }
}

struct CandidateRankingContextToken: Equatable, Hashable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

struct CandidateRankingCandidate: Equatable {
    let reading: String
    let value: String
    let displayText: String
    let rawValue: String
    let originalIndex: Int
}

struct CandidateRankingRequest {
    let token: CandidateRankingContextToken
    let composingBuffer: String
    let cursorIndex: UInt
    let candidates: [CandidateRankingCandidate]
}

struct CandidateRankingResult {
    let token: CandidateRankingContextToken
    let orderedCandidateIndices: [Int]
    let scoresByCandidateIndex: [Int: Double]
    let debugTrace: CandidateRankingDebugTrace?

    init(
        token: CandidateRankingContextToken,
        orderedCandidateIndices: [Int],
        scoresByCandidateIndex: [Int: Double] = [:],
        debugTrace: CandidateRankingDebugTrace? = nil
    ) {
        self.token = token
        self.orderedCandidateIndices = orderedCandidateIndices
        self.scoresByCandidateIndex = scoresByCandidateIndex
        self.debugTrace = debugTrace
    }

    func isValidPermutation(candidateCount: Int) -> Bool {
        guard orderedCandidateIndices.count == candidateCount else {
            return false
        }
        let expected = Set(0..<candidateCount)
        return Set(orderedCandidateIndices) == expected
    }
}

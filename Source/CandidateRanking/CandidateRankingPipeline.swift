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

enum CandidateRankingPipeline {
    static func makeRequest(from state: InputState.ChoosingCandidate, topN: Int)
        -> CandidateRankingRequest?
    {
        guard state.candidates.count > 1 else {
            return nil
        }
        let boundedTopN = min(max(topN, 1), state.candidates.count)
        let rankedCandidates = Array(state.candidates.prefix(boundedTopN))
        let requestCandidates: [CandidateRankingCandidate] = rankedCandidates.enumerated().map {
            index, candidate in
            CandidateRankingCandidate(
                reading: candidate.reading,
                value: candidate.value,
                displayText: candidate.displayText,
                rawValue: candidate.rawValue,
                originalIndex: index
            )
        }
        return CandidateRankingRequest(
            token: state.rankingContextToken,
            composingBuffer: state.composingBuffer,
            cursorIndex: state.cursorIndex,
            candidates: requestCandidates
        )
    }

    static func reorderedCandidates(
        from candidates: [InputState.Candidate],
        result: CandidateRankingResult
    ) -> [InputState.Candidate]? {
        let rankedCandidateCount = result.orderedCandidateIndices.count
        guard rankedCandidateCount > 0 else {
            return nil
        }
        guard rankedCandidateCount <= candidates.count else {
            return nil
        }
        guard result.isValidPermutation(candidateCount: rankedCandidateCount) else {
            return nil
        }

        let prefix = Array(candidates.prefix(rankedCandidateCount))
        let reorderedPrefix = result.orderedCandidateIndices.map { prefix[$0] }
        let suffix = Array(candidates.dropFirst(rankedCandidateCount))
        let reordered = reorderedPrefix + suffix
        let hasChangedOrder = zip(candidates, reordered).contains { $0 !== $1 }
        return hasChangedOrder ? reordered : nil
    }
}

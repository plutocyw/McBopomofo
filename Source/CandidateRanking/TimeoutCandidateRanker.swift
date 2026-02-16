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

struct TimeoutCandidateRanker: CandidateRanker {
    typealias TimeProvider = () -> UInt64

    private let base: CandidateRanker
    private let timeoutMs: Int
    private let timeProvider: TimeProvider

    init(
        base: CandidateRanker,
        timeoutMs: Int,
        timeProvider: @escaping TimeProvider = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.base = base
        self.timeoutMs = timeoutMs
        self.timeProvider = timeProvider
    }

    func rank(request: CandidateRankingRequest) -> CandidateRankingResult {
        let start = timeProvider()
        let result = base.rank(request: request)
        let end = timeProvider()
        let elapsedNs = end >= start ? end - start : 0
        let elapsedMs = Int(elapsedNs / 1_000_000)
        guard elapsedMs <= timeoutMs else {
            CandidateRankingStats.record(.timeoutFallback)
            return CandidateRankingResult(
                token: request.token,
                orderedCandidateIndices: Array(request.candidates.indices)
            )
        }
        return result
    }
}

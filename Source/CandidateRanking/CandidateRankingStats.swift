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

enum CandidateRankingStatsEvent {
    case scheduled
    case applied
    case staleDropped
    case timeoutFallback
    case invalidResultFallback
    case parserFallback
    case localMemoryHit
    case localMemoryMiss
    case correctionAccepted
    case correctionRejected
    case memoryPromotion
    case memoryDemotion
    case postHitManualReversal
}

struct CandidateRankingStatsSnapshot: Equatable {
    var scheduled: Int = 0
    var applied: Int = 0
    var staleDropped: Int = 0
    var timeoutFallback: Int = 0
    var invalidResultFallback: Int = 0
    var parserFallback: Int = 0
    var localMemoryHit: Int = 0
    var localMemoryMiss: Int = 0
    var correctionAccepted: Int = 0
    var correctionRejected: Int = 0
    var memoryPromotion: Int = 0
    var memoryDemotion: Int = 0
    var postHitManualReversal: Int = 0
}

enum CandidateRankingStats {
    private static let lock = NSLock()
    private static var snapshot = CandidateRankingStatsSnapshot()
    private static let reportInterval = 100

    static func record(_ event: CandidateRankingStatsEvent) {
        var shouldReport = false
        var reportSnapshot = CandidateRankingStatsSnapshot()
        lock.lock()
        switch event {
        case .scheduled:
            snapshot.scheduled += 1
            shouldReport = snapshot.scheduled % reportInterval == 0
        case .applied:
            snapshot.applied += 1
        case .staleDropped:
            snapshot.staleDropped += 1
        case .timeoutFallback:
            snapshot.timeoutFallback += 1
        case .invalidResultFallback:
            snapshot.invalidResultFallback += 1
        case .parserFallback:
            snapshot.parserFallback += 1
        case .localMemoryHit:
            snapshot.localMemoryHit += 1
        case .localMemoryMiss:
            snapshot.localMemoryMiss += 1
        case .correctionAccepted:
            snapshot.correctionAccepted += 1
        case .correctionRejected:
            snapshot.correctionRejected += 1
        case .memoryPromotion:
            snapshot.memoryPromotion += 1
        case .memoryDemotion:
            snapshot.memoryDemotion += 1
        case .postHitManualReversal:
            snapshot.postHitManualReversal += 1
        }
        if shouldReport {
            reportSnapshot = snapshot
        }
        lock.unlock()

        if shouldReport {
            NSLog(
                "CandidateRankingStats scheduled=%d applied=%d staleDropped=%d timeoutFallback=%d invalidResultFallback=%d parserFallback=%d localMemoryHit=%d localMemoryMiss=%d correctionAccepted=%d correctionRejected=%d memoryPromotion=%d memoryDemotion=%d postHitManualReversal=%d",
                reportSnapshot.scheduled,
                reportSnapshot.applied,
                reportSnapshot.staleDropped,
                reportSnapshot.timeoutFallback,
                reportSnapshot.invalidResultFallback,
                reportSnapshot.parserFallback,
                reportSnapshot.localMemoryHit,
                reportSnapshot.localMemoryMiss,
                reportSnapshot.correctionAccepted,
                reportSnapshot.correctionRejected,
                reportSnapshot.memoryPromotion,
                reportSnapshot.memoryDemotion,
                reportSnapshot.postHitManualReversal
            )
        }
    }

    static func currentSnapshot() -> CandidateRankingStatsSnapshot {
        lock.lock()
        let current = snapshot
        lock.unlock()
        return current
    }

    static func reset() {
        lock.lock()
        snapshot = CandidateRankingStatsSnapshot()
        lock.unlock()
    }
}

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

/// Owns pending LLM correction transactions for one input controller. It can
/// accumulate corrections across multiple LLM passes in the same composition.
/// Persistence is intentionally deferred to the evidence-store phase.
struct LLMCorrectionFeedbackCoordinator {
    private var transactions: [LLMCorrectionTransaction] = []

    var hasPendingCorrections: Bool {
        !transactions.isEmpty
    }

    mutating func begin(_ transaction: LLMCorrectionTransaction) {
        transactions = transactions.map {
            $0.reconcilingCurrentBuffer(
                transaction.originalBuffer,
                differences: .invalidation)
        }
        transactions.append(transaction)
    }

    mutating func recordExplicitUserBuffer(_ buffer: String) {
        transactions = transactions.map {
            $0.reconcilingCurrentBuffer(buffer, differences: .contradiction)
        }
    }

    mutating func finish(
        disposition: LLMCorrectionTransactionDisposition,
        finalBuffer: String? = nil
    ) -> [LLMCorrectionEvidence] {
        if case .committed = disposition, let finalBuffer {
            transactions = transactions.map {
                $0.reconcilingCurrentBuffer(finalBuffer, differences: .invalidation)
            }
        }
        let evidence = transactions.flatMap { $0.evidence(on: disposition) }
        transactions.removeAll()
        return evidence
    }
}

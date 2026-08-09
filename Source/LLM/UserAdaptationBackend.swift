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

/// Context understood by a user-adaptation backend. It deliberately excludes
/// LLM request details so the backend can later be implemented by an upstream
/// contextual model without depending on the correction pipeline.
struct UserAdaptationContext: Equatable, Hashable {
    let reading: String?
    let currentValue: String
    let leftReading: String?
    let leftValue: String?
}

struct UserAdaptationQuery: Equatable {
    let context: UserAdaptationContext
    let candidateValues: [String]
}

enum UserAdaptationMemoryTier: Equatable {
    case shortTerm
    case longTerm
    case explicit
}

struct UserAdaptationSuggestion: Equatable {
    let replacementValue: String
    let confidence: Double
    let tier: UserAdaptationMemoryTier
    let source: LLMCorrectionEvidenceSource

    init(
        replacementValue: String,
        confidence: Double,
        tier: UserAdaptationMemoryTier,
        source: LLMCorrectionEvidenceSource
    ) {
        self.replacementValue = replacementValue
        self.confidence = min(max(confidence, 0), 1)
        self.tier = tier
        self.source = source
    }
}

enum UserAdaptationObservationOutcome: Equatable {
    case accepted
    case rejected
}

struct UserAdaptationObservation: Equatable {
    let context: UserAdaptationContext
    let replacementValue: String
    let outcome: UserAdaptationObservationOutcome
    let source: LLMCorrectionEvidenceSource
    let weight: Double
    let timestamp: Date

    init(
        context: UserAdaptationContext,
        replacementValue: String,
        outcome: UserAdaptationObservationOutcome,
        source: LLMCorrectionEvidenceSource,
        weight: Double,
        timestamp: Date
    ) {
        self.context = context
        self.replacementValue = replacementValue
        self.outcome = outcome
        self.source = source
        self.weight = max(weight, 0)
        self.timestamp = timestamp
    }
}

enum UserAdaptationResetScope: Equatable {
    case shortTerm
    case longTerm
    case source(LLMCorrectionEvidenceSource)
    case all
}

/// Replaceable boundary between correction policy and the ranking model.
/// Implementations own ranking-state scoring, decay, and persistence. Raw LLM
/// acceptance evidence remains in `LLMCorrectionEvidenceStore`.
protocol UserAdaptationBackend: AnyObject {
    func suggestions(for queries: [UserAdaptationQuery]) throws
        -> [UserAdaptationSuggestion?]
    func observe(_ observation: UserAdaptationObservation) throws
    func reset(_ scope: UserAdaptationResetScope) throws
}

extension UserAdaptationBackend {
    func suggestion(for query: UserAdaptationQuery) throws
        -> UserAdaptationSuggestion?
    {
        try suggestions(for: [query]).first ?? nil
    }
}

final class NoOpUserAdaptationBackend: UserAdaptationBackend {
    func suggestions(for queries: [UserAdaptationQuery]) throws
        -> [UserAdaptationSuggestion?]
    {
        queries.map { _ in nil }
    }

    func observe(_ observation: UserAdaptationObservation) throws {
        _ = observation
    }

    func reset(_ scope: UserAdaptationResetScope) throws {
        _ = scope
    }
}

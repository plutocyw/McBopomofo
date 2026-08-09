# LLM Correction Memory Plan

Last updated: 2026-08-08T05:11:59+08:00

## Objective

Reduce repeated LLM correction calls by learning from corrections that the user
actually accepts, while preventing an incorrect LLM answer from immediately or
permanently changing future candidate selection.

The implementation must remain easy to reconcile with future changes pulled
from `upstream/master`, especially the possible future integration of
`ContextualUserModel` from `upstream/feat/keyhandler_user_model`.

## Non-goals

- Do not permanently add an LLM result to the user phrase file after one
  acceptance.
- Do not treat successful application of an LLM result as user acceptance.
- Do not duplicate or vendor the upstream `ContextualUserModel` implementation.
- Do not make broad changes to `KeyHandler.mm` or `LanguageModelManager.mm`
  before the user-adaptation backend boundary is defined.
- Do not make candidate memory impossible to disable or reset during LLM
  regression testing.

## Repository Baseline

- Working branch at plan creation: `master`
- Working commit at plan creation: `5008b40`
- Upstream master observed at plan creation: `ac23922`
- Upstream candidate branch: `upstream/feat/keyhandler_user_model`
- Merge base between the working master and the upstream candidate branch:
  `040097e`

The upstream candidate branch touches these merge-sensitive files:

- `McBopomofo.xcodeproj/project.pbxproj`
- `Source/AppDelegate.swift`
- `Source/Engine/CMakeLists.txt`
- `Source/KeyHandler.mm`
- `Source/LanguageModelManager+Privates.h`
- `Source/LanguageModelManager.h`
- `Source/LanguageModelManager.mm`

It also adds `Source/Engine/ContextualUserModel.*`. New work should avoid
duplicating those files or embedding LLM-specific policy in the legacy
`UserOverrideModel`.

## Architecture Boundary

The work is split into two responsibilities.

### LLM correction evidence and policy

This fork owns:

- tracking the candidate path before and after an LLM rewrite;
- tracking each changed segment independently;
- classifying user actions as accepted, rejected, or neutral;
- assigning evidence source and weight;
- deciding when evidence remains short-term or is promoted;
- evaluation bypass, reset, and LLM-only deletion;
- metrics for memory hits, reversals, and avoided LLM calls.

This logic should live under `Source/LLM/` and should not depend on a concrete
C++ user model.

### User-adaptation backend

The backend owns:

- context key construction;
- scoring and decay;
- interaction with `ReadingGrid`;
- persistence of ranking state;
- production of candidate suggestions.

The first integration must use a narrow adapter. When an upstream contextual
model lands, only the adapter should need replacement.

## Evidence Semantics

An LLM correction begins as a transaction. A transaction contains one or more
independent changed segments.

Expected outcomes:

- Commit with a changed segment intact: weak acceptance.
- Manual selection of the same value: strong acceptance.
- Manual selection of another value or restoration of the original value:
  rejection for that segment.
- Escape, deletion of the whole composition, stale LLM response, or failed
  application: neutral and must not be learned.
- A sentence with three corrections can produce two acceptances and one
  rejection; it is not classified as one all-or-nothing event.

Evidence sources must remain distinguishable:

- `manualSelection`
- `acceptedLLMCorrection`
- `explicitAlwaysUse`

## Proposed Memory Tiers

1. Pending transaction: exists only while the corrected composition is active.
2. Short-term evidence: exact or close context, quickly decaying and resettable.
3. Long-term contextual evidence: persisted after repeated acceptance across
   sessions, but still reversible and slowly decaying.
4. Explicit user phrase: permanent until the user removes it; only entered by
   an explicit user action.

Initial promotion policy, subject to tests and later tuning:

- at least three accepted occurrences;
- at least two distinct sessions;
- acceptance ratio at least 80 percent;
- no recent explicit rejection;
- manual evidence has greater weight than passive acceptance of an LLM result;
- one newer rejection blocks matching short-term reuse and demotes long-term
  eligibility until newer positive evidence restores confidence.

## Evaluation Requirements

The finished feature must support:

- disable all memory reads;
- disable all memory writes;
- disable only LLM-derived learning;
- clear only LLM-derived memory;
- clear short-term memory;
- preserve manual user phrases while testing LLM behavior;
- compare base, base plus memory, base plus LLM, and base plus memory plus LLM.

## Implementation Phases

### Phase 1: Durable plan and transaction model

Status: completed

Deliverables:

- this durable plan and progress log;
- immutable correction segment and transaction value types;
- unit tests for creation, unchanged acceptance, partial rejection, and neutral
  cancellation;
- no production behavior change yet.

### Phase 2: Controller feedback integration

Status: completed

Deliverables:

- create a transaction only after an LLM result is validated and applied;
- confirm surviving changed segments when text is committed;
- reject only overlapping segments on manual correction;
- discard on stale response, failed application, or neutral cancellation;
- retain all policy outside `KeyHandler.mm` where possible.

### Phase 3: Evidence store and evaluation controls

Status: completed

Deliverables:

- versioned local evidence format separate from
  `contextual-user-model.txt`;
- atomic persistence;
- provenance-aware reset;
- read/write bypass controls;
- tests for malformed input, migration boundary, reset, and source filtering.

### Phase 4: User-adaptation backend boundary

Status: completed

Deliverables:

- neutral context and suggestion types;
- backend protocol or bridge;
- no-op backend for deterministic tests;
- minimal legacy adapter only if upstream contextual integration is still not
  available;
- documented replacement path for `ContextualUserModel`.

### Phase 5: Short-term use and long-term consolidation

Status: completed

Deliverables:

- short-term lookup before cloud dispatch;
- promotion and demotion policy;
- high-confidence local correction can avoid an LLM call;
- explicit permanent promotion remains a separate user action;
- manual selection has precedence over LLM-derived evidence.

### Phase 6: Integration validation and upstream readiness

Status: completed

Deliverables:

- focused Swift tests;
- relevant C++ tests if a backend is integrated;
- Xcode build or test verification;
- metrics for LLM dispatch, local memory hit, acceptance, rejection, promotion,
  demotion, and post-hit manual reversal;
- final conflict audit against current `upstream/master` and
  `upstream/feat/keyhandler_user_model`.

### Phase 7: Runtime tuning controls

Status: completed

Deliverables:

- expose safe policy thresholds in the LLM preferences UI;
- apply changes to the next lookup or observation without recompilation or
  restart;
- enforce bounded values and provide one-click default restoration;
- include active values in system reports and preference tests.

## Progress Log

### 2026-08-08T04:02:23+08:00

- Confirmed that manual candidate selection currently records observations in
  `UserOverrideModel`, while LLM segment and edit-action application do not.
- Confirmed that the current model is process-local, has capacity 500, and has
  a 90-minute half-life.
- Reviewed `upstream/feat/keyhandler_user_model`. It persists contextual
  observations and generalizes after repeated contexts, but does not provide
  LLM provenance, acceptance transactions, rejection evidence, evaluation
  bypass, or a short-to-long consolidation policy.
- Chose an additive LLM evidence layer plus a replaceable user-adaptation
  backend instead of modifying the legacy user model directly.
- Created the implementation plan. Phase 1 transaction types and tests are the
  next action.

### 2026-08-08T04:07:16+08:00

- Added `LLMCorrectionTransaction` as a pure Swift value type under
  `Source/LLM/`. It validates fixed-length, non-overlapping changes and keeps
  correction policy independent of any ranking backend.
- Added per-segment outcomes. A commit accepts unchanged corrections and
  rejects only corrections contradicted by an overlapping manual replacement;
  cancellation produces neutral evidence.
- Added six focused transaction tests covering corrected-buffer construction,
  unchanged acceptance, partial rejection, preservation of the corrected
  value, neutral cancellation, and invalid overlap rejection.
- Added the new source and test files to the Xcode project with additive
  project entries.
- Completed Phase 1. The next action is Phase 2 integration: construct a
  transaction only after a validated LLM result is applied, then resolve it at
  commit or neutral cancellation boundaries without changing ranking yet.

### 2026-08-08T04:13:16+08:00

- Added `LLMCorrectionFeedbackCoordinator` so multiple validated LLM passes in
  the same composition can be tracked without conflating their changed
  segments.
- Integrated transaction creation after both candidate-path and edit-action
  LLM results are validated and applied.
- Integrated commit, deactivation, and cancellation boundaries. Corrections
  surviving commit become accepted evidence; an explicit overlapping manual
  candidate selection becomes rejected evidence; automatic rewrites and
  neutral cancellation do not create positive or negative evidence.
- Kept the feedback policy in `Source/LLM/` and avoided changes to
  `KeyHandler.mm`, `LanguageModelManager.mm`, and the C++ engine.
- Added four focused coordinator tests for multi-pass accumulation, overlapping
  rewrite invalidation, explicit user rejection, and neutral cancellation.
- Completed Phase 2 without feeding evidence into ranking. The next action is
  Phase 3: implement a versioned, atomic, provenance-aware evidence store with
  independent read, write, and LLM-learning bypasses.

### 2026-08-08T04:19:19+08:00

- Added `LLMCorrectionEvidenceStore`, which atomically persists a versioned JSON
  envelope in `llm-correction-evidence.json`, separate from user phrase and
  ranking-model files.
- The file stores only the corrected span, its reading, immediate left context,
  provenance, aggregate acceptance and rejection counts, timestamps, and
  distinct process-session identifiers. It does not retain the full composing
  sentence.
- Added independent preferences for memory reads, memory writes, and
  LLM-derived learning. Disabling reads does not prevent safe aggregation of
  writes; disabling writes leaves the file unchanged; disabling LLM learning
  still permits evidence from other provenances.
- Added provenance-aware filtering and reset. Clearing
  `acceptedLLMCorrection` evidence does not touch manual evidence, explicit
  user phrases, or a future ranking-model file.
- Connected committed non-neutral LLM feedback to the store. Evidence is now
  collected, but it is still never read to change ranking or suppress an LLM
  request.
- Added seven store tests for aggregation, distinct sessions, independent
  bypasses, LLM-only bypass, provenance reset, malformed data, and unsupported
  format versions. Added a preference test for all three controls.
- Completed Phase 3. The next action is Phase 4: define neutral context,
  suggestion, and observation types plus a replaceable no-op backend, without
  integrating the legacy `UserOverrideModel` or modifying merge-sensitive C++
  files.

### 2026-08-08T04:22:02+08:00

- Added the replaceable `UserAdaptationBackend` boundary with neutral query,
  context, suggestion, observation, memory-tier, and reset-scope types.
- Added a deterministic `NoOpUserAdaptationBackend` and injected the backend
  through `McBopomofoInputMethodController`. Production behavior remains
  unchanged at this checkpoint.
- Kept the contract synchronous and narrow so an upstream
  `ContextualUserModel` adapter can map context, suggestion, observation, and
  reset operations without importing LLM request or provider details.
- Deliberately did not add a legacy `UserOverrideModel` bridge: doing so would
  modify `KeyHandler.mm` for a temporary backend that cannot persist and would
  create avoidable conflicts with the upstream contextual-model branch.
- Added three backend-contract tests for deterministic no-op behavior and
  bounded confidence and observation values.
- Completed Phase 4. The next action is Phase 5: add an evidence-backed policy
  implementation, classify short- versus long-term confidence, apply only
  high-confidence candidate matches before cloud dispatch, and retain a clean
  fallback to LLM.

### 2026-08-08T04:36:05+08:00

- Added `EvidenceBasedUserAdaptationBackend` with exact-context lookup,
  candidate availability checks, confidence decay, and deterministic
  precedence for explicit, long-term, and short-term evidence.
- A recent accepted correction now creates short-term memory. Three accepted
  occurrences across at least two process sessions promote it to long-term
  memory when its acceptance ratio remains at least 80 percent. A newer
  rejection blocks unsafe reuse.
- Added a pure selection planner that changes only high-confidence segments and
  preserves the current candidate for every other segment. A safe local hit is
  applied before cloud dispatch and therefore avoids an LLM request; a miss or
  backend error retains the existing cloud path.
- Local-memory replay does not reinforce itself as another acceptance. If the
  user manually reverses the replay, it still produces rejection evidence.
- Added separate preference controls for memory reads, memory writes, and
  learning from accepted LLM corrections. Added an LLM-only clear action to
  the LLM preferences screen with English and Traditional Chinese localization.
  Explicit reset remains available even while ordinary memory writes are
  disabled, and it preserves manual user phrases.
- Added local-memory hit and miss counters. Completed Phase 5. The next action
  is Phase 6: add acceptance, rejection, promotion, demotion, and post-hit
  reversal metrics, then perform the final upstream conflict audit.

### 2026-08-08T04:41:08+08:00

- Routed committed correction observations through `UserAdaptationBackend`
  instead of writing the store directly. The controller remains independent of
  the concrete evidence backend, so a future contextual-model adapter can be
  substituted at one initialization point.
- Added counters for accepted and rejected correction segments, long-term
  promotion and demotion, and manual reversal after a local-memory hit. The
  existing scheduled counter represents actual LLM dispatches; local-memory
  hits represent avoided dispatches.
- Added origin tracking without persisting extra sentence data. Local-memory
  replay remains neutral when accepted, but a manual reversal is identifiable
  as both rejection evidence and a post-hit reversal metric.
- Corrected cross-session consolidation so only sessions containing acceptance
  count toward long-term promotion; a rejection-only session cannot satisfy
  the two-session threshold.
- Completed a local upstream audit. `origin/master` is exactly the working
  baseline commit `5008b40`; the locally configured `upstream/master` at
  `ac23922` is already an ancestor of that baseline. The contextual-model
  branch has only one path overlap with this work:
  `McBopomofo.xcodeproj/project.pbxproj`. This work deliberately leaves its
  `KeyHandler.mm`, `LanguageModelManager.*`, `AppDelegate.swift`, and C++ engine
  files untouched.
- Completed Phase 6. No C++ test was required because the active backend and
  policy are pure Swift and no C++ backend was integrated.

### 2026-08-08T05:11:59+08:00

- Added a collapsible `Memory Tuning (Testing)` section to LLM preferences.
  It exposes local-application confidence, short-term half-life and maximum
  age, long-term half-life and maximum age, minimum acceptances, minimum
  accepted sessions, and minimum acceptance ratio.
- Stored every tuning value as a bounded preference and added a one-click
  restore-defaults action. Active values are included in system reports.
- Changed `EvidenceBasedUserAdaptationBackend` to obtain policy through a
  provider for each lookup, observation, and tier reset. Preference changes
  therefore apply immediately without recreating the input controller.
- The selection planner receives the current confidence threshold separately,
  so that setting also applies on the next local-memory lookup.
- Added tests for all defaults and bounds, immediate policy-provider changes,
  and alternate selection confidence thresholds. Completed Phase 7.

## ContextualUserModel Replacement Path

When `ContextualUserModel` is rebased onto the current master and becomes
available:

1. Add an adapter implementing `UserAdaptationBackend`.
2. Map `UserAdaptationContext` into the contextual model's key and candidate
   APIs; reject observations whose reading is unavailable.
3. Keep transaction, provenance, evaluation controls, and acceptance policy in
   `Source/LLM/`; do not move LLM-specific semantics into the C++ model.
4. Replace only the default backend initialization in
   `McBopomofoInputMethodController`.
5. Decide explicitly whether the JSON evidence store remains the audit source
   or is migrated. Do not silently merge it into manual phrase files.
6. Regenerate the Xcode project-file additions if the single additive project
   file conflict cannot be resolved mechanically.

## Verification Log

- 2026-08-08T04:07:16+08:00: `plutil -lint` passed for
  `McBopomofo.xcodeproj/project.pbxproj`.
- 2026-08-08T04:07:16+08:00: full macOS test run passed with 142 tests in 12
  suites using the `McBopomofo` scheme. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-06-31--0700.xcresult`.
- 2026-08-08T04:13:16+08:00: `plutil -lint` passed for
  `McBopomofo.xcodeproj/project.pbxproj` after Phase 2 project additions.
- 2026-08-08T04:13:16+08:00: full macOS test run passed with 146 tests in 13
  suites using the `McBopomofo` scheme. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-12-03--0700.xcresult`.
- 2026-08-08T04:19:19+08:00: focused evidence-store and preference test run
  passed with 34 tests in 2 suites. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-17-43--0700.xcresult`.
- 2026-08-08T04:19:19+08:00: focused evidence-store test run passed with 7
  tests in 1 suite after strengthening read-bypass and distinct-session cases.
  Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-18-26--0700.xcresult`.
- 2026-08-08T04:19:19+08:00: full macOS test run passed with 154 tests in 14
  suites using the `McBopomofo` scheme. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-19-01--0700.xcresult`.
- 2026-08-08T04:19:19+08:00: `git diff --check` and `plutil -lint` passed.
  All six new standalone Swift files also passed strict `swift-format` lint.
- 2026-08-08T04:22:02+08:00: focused user-adaptation backend test run passed
  with 3 tests in 1 suite. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-21-29--0700.xcresult`.
- 2026-08-08T04:22:02+08:00: full macOS test run passed with 157 tests in 15
  suites using the `McBopomofo` scheme. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-21-46--0700.xcresult`.
- 2026-08-08T04:29:00+08:00: focused Phase 5 integration test run passed with
  52 tests in 5 suites. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-28-56--0700.xcresult`.
- 2026-08-08T04:31:00+08:00: strengthened policy and selection-planner tests
  passed with 8 tests in 1 suite. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-30-59--0700.xcresult`.
- 2026-08-08T04:36:05+08:00: full macOS test run passed with 166 tests in 16
  suites using the `McBopomofo` scheme. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-34-31--0700.xcresult`.
- 2026-08-08T04:36:05+08:00: `git diff --check` passed. `plutil -lint` passed
  for the Xcode project and all three modified localization files. The new
  evidence-store source and tests passed strict `swift-format` lint.
- 2026-08-08T04:39:00+08:00: full macOS test run passed with 167 tests in 16
  suites after adding all required memory metrics. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-38-23--0700.xcresult`.
- 2026-08-08T04:41:08+08:00: final full macOS test run passed with 168 tests in
  16 suites after excluding rejection-only sessions from promotion. Result
  bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_13-40-52--0700.xcresult`.
- 2026-08-08T04:41:08+08:00: final `git diff --check` and `plutil -lint`
  passed. All new standalone Swift source and test files passed strict
  `swift-format` lint.
- 2026-08-08T05:11:59+08:00: full macOS test run passed with 170 tests in 16
  suites after adding runtime tuning. Result bundle:
  `/tmp/McBopomofoLLMMemoryDerived/Logs/Test/Test-McBopomofo-2026.08.07_14-11-32--0700.xcresult`.

## Resume Instructions

1. Read this file completely.
2. Run `git status --short --branch` and preserve unrelated user changes.
3. Check the latest entry in the Progress Log and the phase statuses above.
4. Continue from the exact next action stated in the latest progress entry.
5. After each completed phase or meaningful partial checkpoint, update:
   - `Last updated`;
   - the phase status;
   - the Progress Log;
   - the Verification Log;
   - the next action.
6. Before editing merge-sensitive files, compare them with
   `upstream/feat/keyhandler_user_model` and keep the integration hook narrow.

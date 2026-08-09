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

private let kKeyboardLayoutPreferenceKey = "KeyboardLayout"
/// alphanumeric ("ASCII") input basic keyboard layout.
private let kBasisKeyboardLayoutPreferenceKey = "BasisKeyboardLayout"
/// alphanumeric ("ASCII") input basic keyboard layout.
private let kFunctionKeyKeyboardLayoutPreferenceKey = "FunctionKeyKeyboardLayout"
/// whether include shift.
private let kFunctionKeyKeyboardLayoutOverrideIncludeShiftKey =
    "FunctionKeyKeyboardLayoutOverrideIncludeShift"
private let kCandidateListTextSizeKey = "CandidateListTextSize"
private let kSelectPhraseAfterCursorAsCandidateKey = "SelectPhraseAfterCursorAsCandidate"
private let kMoveCursorAfterSelectingCandidateKey = "MoveCursorAfterSelectingCandidate"
private let kUseHorizontalCandidateListPreferenceKey = "UseHorizontalCandidateList"
private let kChooseCandidateUsingSpaceKey = "ChooseCandidateUsingSpaceKey"
private let kChineseConversionEnabledKey = "ChineseConversionEnabled"
private let kHalfWidthPunctuationEnabledKey = "HalfWidthPunctuationEnable"
private let kEscToCleanInputBufferKey = "EscToCleanInputBuffer"
private let kKeepReadingUponCompositionError = "KeepReadingUponCompositionError"

private let kCandidateTextFontName = "CandidateTextFontName"
private let kCandidateKeyLabelFontName = "CandidateKeyLabelFontName"
private let kCandidateKeys = "CandidateKeys"
private let kAllowMovingCursorWhenChoosingCandidates = "AllowMovingCursorWhenChoosingCandidates"

private let kPhraseReplacementEnabledKey = "PhraseReplacementEnabled"
private let kChineseConversionStyleKey = "ChineseConversionStyle"
private let kAssociatedPhrasesEnabledKey = "AssociatedPhrasesEnabled"
private let kLetterBehaviorKey = "LetterBehavior"
private let kControlEnterOutputKey = "ControlEnterOutput"
private let kShiftEnterEnabledKey = "ShiftEnterEnabled"
private let kRepeatedPunctuationToSelectCandidateEnabledKey =
    "RepeatedPunctuationToSelectCandidateEnabled"
private let kUseCustomUserPhraseLocation = "UseCustomUserPhraseLocation"
private let kCustomUserPhraseLocation = "CustomUserPhraseLocation"

private let kDefaultCandidateListTextSize: CGFloat = 16
private let kMinCandidateListTextSize: CGFloat = 12
private let kMaxCandidateListTextSize: CGFloat = 196

private let kDefaultKeys = "123456789"
private let kDefaultAssociatedPhrasesKeys = "!@#$%^&*("

private let kAddPhraseHookEnabledKey = "AddPhraseHookEnabled"
private let kAddPhraseHookPath = "AddPhraseHookPath"

private let kSelectCandidateWithNumericKeypad = "SelectCandidateWithNumericKeypad"
private let kBig5InputEnabledKey = "Big5InputEnabled"

// Need to be populated to true by default upon first start, so the key is not private.
let kBeepUponInputErrorKey = "BeepUponInputError"

private let kEnableUserPhrasesInPlainBopomofo = "EnableUserPhrasesInPlainBopomofo"
private let kAllowChangingPriorTone = "AllowChangingPriorTone"
private let kLLMCandidateRankingEnabledKey = "LLMCandidateRankingEnabled"
private let kLLMEditActionRerankingEnabledKey = "LLMEditActionRerankingEnabled"
private let kLLMCorrectionMemoryReadsEnabledKey = "LLMCorrectionMemoryReadsEnabled"
private let kLLMCorrectionMemoryWritesEnabledKey = "LLMCorrectionMemoryWritesEnabled"
private let kLLMCorrectionLearningEnabledKey = "LLMCorrectionLearningEnabled"
private let kLLMCorrectionMinimumConfidencePercentKey =
    "LLMCorrectionMinimumConfidencePercent"
private let kLLMCorrectionShortTermHalfLifeMinutesKey =
    "LLMCorrectionShortTermHalfLifeMinutes"
private let kLLMCorrectionShortTermMaximumAgeMinutesKey =
    "LLMCorrectionShortTermMaximumAgeMinutes"
private let kLLMCorrectionLongTermHalfLifeDaysKey = "LLMCorrectionLongTermHalfLifeDays"
private let kLLMCorrectionLongTermMaximumAgeDaysKey = "LLMCorrectionLongTermMaximumAgeDays"
private let kLLMCorrectionLongTermMinimumAcceptancesKey =
    "LLMCorrectionLongTermMinimumAcceptances"
private let kLLMCorrectionLongTermMinimumSessionsKey =
    "LLMCorrectionLongTermMinimumSessions"
private let kLLMCorrectionMinimumAcceptanceRatioPercentKey =
    "LLMCorrectionMinimumAcceptanceRatioPercent"
private let kLLMCandidateRankingTimeoutMsKey = "LLMCandidateRankingTimeoutMs"
private let kLLMInputtingPauseMsKey = "LLMInputtingPauseMs"
private let kLLMShowActivityIndicatorKey = "LLMShowActivityIndicator"
private let kLLMShowDebugAlertKey = "LLMShowDebugAlert"
private let kLLMInputtingTriggerModeKey = "LLMInputtingTriggerMode"
private let kLLMCloudProviderKey = "LLMCloudProvider"
private let kLLMGoogleModelNameKey = "LLMGoogleModelName"
private let kLLMGoogleEndpointKey = "LLMGoogleEndpoint"
private let kLLMGoogleAPIKeyKey = "LLMGoogleAPIKey"
private let kLLMGoogleThinkingLevelKey = "LLMGoogleThinkingLevel"
private let kLLMOpenAIModelNameKey = "LLMOpenAIModelName"
private let kLLMOpenAIEndpointKey = "LLMOpenAIEndpoint"
private let kLLMOpenAIAPIKeyKey = "LLMOpenAIAPIKey"

private let kDefaultLLMCandidateRankingTimeoutMs = 12
private let kMinLLMCandidateRankingTimeoutMs = 1
private let kMaxLLMCandidateRankingTimeoutMs = 5000
private let kDefaultLLMInputtingPauseMs = 600
private let kMinLLMInputtingPauseMs = 100
private let kMaxLLMInputtingPauseMs = 3000
private let kDefaultLLMCorrectionMinimumConfidencePercent = 90
private let kDefaultLLMCorrectionShortTermHalfLifeMinutes = 90
private let kDefaultLLMCorrectionShortTermMaximumAgeMinutes = 90
private let kDefaultLLMCorrectionLongTermHalfLifeDays = 180
private let kDefaultLLMCorrectionLongTermMaximumAgeDays = 365
private let kDefaultLLMCorrectionLongTermMinimumAcceptances = 3
private let kDefaultLLMCorrectionLongTermMinimumSessions = 2
private let kDefaultLLMCorrectionMinimumAcceptanceRatioPercent = 80
private let kDefaultLLMGoogleModelName = "gemini-3.6-flash"
private let kDefaultLLMGoogleEndpoint = "https://generativelanguage.googleapis.com/v1beta"
private let kDefaultLLMOpenAIModelName = "gpt-4.1-mini"
private let kDefaultLLMOpenAIEndpoint = "https://api.openai.com/v1/chat/completions"

private let kBopomofoFontAnnotationSupportEnabled = "BopomofoFontAnnotationSupportEnabled"
private let kShowBopomofoFontAnnotationSupportItemInInputMenu =
    "ShowBopomofoFontAnnotationSupportItemInInputMenu"
private let kBopomofoFontAnnotationSupportMenuItemEnabledByInstalledFontsCheck_V1 =
    "BopomofoFontAnnotationSupportMenuItemEnabledByInstalledFontsCheck_V1"

// MARK: Property wrappers

@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    var container: UserDefaults = .standard

    var wrappedValue: Value {
        get {
            container.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            container.set(newValue, forKey: key)
        }
    }
}

@propertyWrapper
struct UserDefaultWithFunction<Value> {
    let key: String
    let defaultValueFunction: () -> Value
    var container: UserDefaults = .standard

    var wrappedValue: Value {
        get {
            container.object(forKey: key) as? Value ?? defaultValueFunction()
        }
        set {
            container.set(newValue, forKey: key)
        }
    }
}

@propertyWrapper
struct EnumUserDefault<T: RawRepresentable> {
    let key: String
    let defaultValue: T
    var container: UserDefaults = .standard

    var wrappedValue: T {
        get {
            if let value = container.object(forKey: key) as? T.RawValue {
                return T(rawValue: value) ?? defaultValue
            }
            return defaultValue
        }
        set {
            container.set(newValue.rawValue, forKey: key)
        }
    }
}

@propertyWrapper
struct CandidateListTextSize {
    let key: String
    let defaultValue: CGFloat = kDefaultCandidateListTextSize
    lazy var container: UserDefault = {
        UserDefault(key: key, defaultValue: defaultValue)
    }()

    var wrappedValue: CGFloat {
        mutating get {
            var value = container.wrappedValue
            if value < kMinCandidateListTextSize {
                value = kMinCandidateListTextSize
            } else if value > kMaxCandidateListTextSize {
                value = kMaxCandidateListTextSize
            }
            return value
        }
        set {
            var value = newValue
            if value < kMinCandidateListTextSize {
                value = kMinCandidateListTextSize
            } else if value > kMaxCandidateListTextSize {
                value = kMaxCandidateListTextSize
            }
            container.wrappedValue = value
        }
    }
}

@propertyWrapper
struct BoundedIntUserDefault {
    let key: String
    let defaultValue: Int
    let minValue: Int
    let maxValue: Int
    lazy var container: UserDefault = {
        UserDefault(key: key, defaultValue: defaultValue)
    }()

    var wrappedValue: Int {
        mutating get {
            var value = container.wrappedValue
            if value < minValue {
                value = minValue
            } else if value > maxValue {
                value = maxValue
            }
            return value
        }
        set {
            var value = newValue
            if value < minValue {
                value = minValue
            } else if value > maxValue {
                value = maxValue
            }
            container.wrappedValue = value
        }
    }
}

// MARK: -

@objc enum KeyboardLayout: Int {
    case standard = 0
    case eten = 1
    case hsu = 2
    case eten26 = 3
    case hanyuPinyin = 4
    case IBM = 5

    var name: String {
        return switch self {
        case .standard:
            "Standard"
        case .eten:
            "ETen"
        case .hsu:
            "Hsu"
        case .eten26:
            "ETen26"
        case .hanyuPinyin:
            "HanyuPinyin"
        case .IBM:
            "IBM"
        }
    }
}

@objc enum ChineseConversionStyle: Int {
    case output
    case model

    var name: String {
        return switch self {
        case .output:
            "output"
        case .model:
            "model"
        }
    }
}

@objc enum LLMInputtingTriggerMode: Int {
    case continuous = 0
    case segmentEnd = 1

    var name: String {
        return switch self {
        case .continuous:
            "Continuous"
        case .segmentEnd:
            "SegmentEnd"
        }
    }
}

@objc enum LLMCloudProvider: Int {
    case google = 0
    case openAI = 1

    var name: String {
        return switch self {
        case .google:
            "Google"
        case .openAI:
            "OpenAI"
        }
    }
}

@objc enum LLMGoogleThinkingLevel: Int {
    case off = 0
    case low = 1
    case medium = 2
    case high = 3

    var name: String {
        return switch self {
        case .off:
            "Off"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }

    var thinkingBudget: Int {
        return switch self {
        case .off:
            0
        case .low:
            256
        case .medium:
            1024
        case .high:
            2048
        }
    }

    var thinkingLevel: String {
        return switch self {
        case .off:
            "minimal"
        case .low:
            "low"
        case .medium:
            "medium"
        case .high:
            "high"
        }
    }
}

// MARK: -

class Preferences: NSObject {
    static var allKeys: [String] {
        [
            kKeyboardLayoutPreferenceKey,
            kBasisKeyboardLayoutPreferenceKey,
            kFunctionKeyKeyboardLayoutPreferenceKey,
            kFunctionKeyKeyboardLayoutOverrideIncludeShiftKey,
            kCandidateListTextSizeKey,
            kSelectPhraseAfterCursorAsCandidateKey,
            kUseHorizontalCandidateListPreferenceKey,
            kChooseCandidateUsingSpaceKey,
            kChineseConversionEnabledKey,
            kHalfWidthPunctuationEnabledKey,
            kEscToCleanInputBufferKey,
            kKeepReadingUponCompositionError,
            kCandidateTextFontName,
            kCandidateKeyLabelFontName,
            kCandidateKeys,
            kPhraseReplacementEnabledKey,
            kChineseConversionStyleKey,
            kAssociatedPhrasesEnabledKey,
            kControlEnterOutputKey,
            kShiftEnterEnabledKey,
            kRepeatedPunctuationToSelectCandidateEnabledKey,
            kUseCustomUserPhraseLocation,
            kCustomUserPhraseLocation,
            kLLMCandidateRankingEnabledKey,
            kLLMEditActionRerankingEnabledKey,
            kLLMCorrectionMemoryReadsEnabledKey,
            kLLMCorrectionMemoryWritesEnabledKey,
            kLLMCorrectionLearningEnabledKey,
            kLLMCorrectionMinimumConfidencePercentKey,
            kLLMCorrectionShortTermHalfLifeMinutesKey,
            kLLMCorrectionShortTermMaximumAgeMinutesKey,
            kLLMCorrectionLongTermHalfLifeDaysKey,
            kLLMCorrectionLongTermMaximumAgeDaysKey,
            kLLMCorrectionLongTermMinimumAcceptancesKey,
            kLLMCorrectionLongTermMinimumSessionsKey,
            kLLMCorrectionMinimumAcceptanceRatioPercentKey,
            kLLMCandidateRankingTimeoutMsKey,
            kLLMInputtingPauseMsKey,
            kLLMShowActivityIndicatorKey,
            kLLMShowDebugAlertKey,
            kLLMInputtingTriggerModeKey,
            kLLMCloudProviderKey,
            kLLMGoogleModelNameKey,
            kLLMGoogleEndpointKey,
            kLLMGoogleAPIKeyKey,
            kLLMGoogleThinkingLevelKey,
            kLLMOpenAIModelNameKey,
            kLLMOpenAIEndpointKey,
            kLLMOpenAIAPIKeyKey,
        ]
    }

    @objc static func populateDefaults() {
        Preferences.keyboardLayout = Preferences.keyboardLayout
        Preferences.basisKeyboardLayout = Preferences.basisKeyboardLayout
        Preferences.functionKeyboardLayout = Preferences.functionKeyboardLayout
        Preferences.candidateKeys = Preferences.candidateKeys
        Preferences.selectPhraseAfterCursorAsCandidate =
            Preferences.selectPhraseAfterCursorAsCandidate
        Preferences.moveCursorAfterSelectingCandidate =
            Preferences.moveCursorAfterSelectingCandidate
        Preferences.useHorizontalCandidateList = Preferences.useHorizontalCandidateList
        Preferences.chineseConversionEnabled = Preferences.chineseConversionEnabled
        Preferences.halfWidthPunctuationEnabled = Preferences.halfWidthPunctuationEnabled
        Preferences.selectCandidateWithNumericKeypad = Preferences.selectCandidateWithNumericKeypad
        Preferences.big5InputEnabled = Preferences.big5InputEnabled
        Preferences.chineseConversionStyle = Preferences.chineseConversionStyle
        Preferences.phraseReplacementEnabled = Preferences.phraseReplacementEnabled
        Preferences.associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.letterBehavior = Preferences.letterBehavior
        Preferences.controlEnterOutput = Preferences.controlEnterOutput
        Preferences.shiftEnterEnabled = Preferences.shiftEnterEnabled
        Preferences.repeatedPunctuationToSelectCandidateEnabled =
            Preferences.repeatedPunctuationToSelectCandidateEnabled
        Preferences.addPhraseHookEnabled = Preferences.addPhraseHookEnabled
        Preferences.addPhraseHookPath = Preferences.addPhraseHookPath
        Preferences.beepUponInputError = Preferences.beepUponInputError
        Preferences.enableUserPhrasesInPlainBopomofo = Preferences.enableUserPhrasesInPlainBopomofo
        Preferences.allowMovingCursorWhenChoosingCandidates =
            Preferences.allowMovingCursorWhenChoosingCandidates
        Preferences.llmCandidateRankingEnabled = Preferences.llmCandidateRankingEnabled
        Preferences.llmEditActionRerankingEnabled =
            Preferences.llmEditActionRerankingEnabled
        Preferences.llmCorrectionMemoryReadsEnabled =
            Preferences.llmCorrectionMemoryReadsEnabled
        Preferences.llmCorrectionMemoryWritesEnabled =
            Preferences.llmCorrectionMemoryWritesEnabled
        Preferences.llmCorrectionLearningEnabled =
            Preferences.llmCorrectionLearningEnabled
        Preferences.llmCorrectionMinimumConfidencePercent =
            Preferences.llmCorrectionMinimumConfidencePercent
        Preferences.llmCorrectionShortTermHalfLifeMinutes =
            Preferences.llmCorrectionShortTermHalfLifeMinutes
        Preferences.llmCorrectionShortTermMaximumAgeMinutes =
            Preferences.llmCorrectionShortTermMaximumAgeMinutes
        Preferences.llmCorrectionLongTermHalfLifeDays =
            Preferences.llmCorrectionLongTermHalfLifeDays
        Preferences.llmCorrectionLongTermMaximumAgeDays =
            Preferences.llmCorrectionLongTermMaximumAgeDays
        Preferences.llmCorrectionLongTermMinimumAcceptances =
            Preferences.llmCorrectionLongTermMinimumAcceptances
        Preferences.llmCorrectionLongTermMinimumSessions =
            Preferences.llmCorrectionLongTermMinimumSessions
        Preferences.llmCorrectionMinimumAcceptanceRatioPercent =
            Preferences.llmCorrectionMinimumAcceptanceRatioPercent
        Preferences.llmCandidateRankingTimeoutMs = Preferences.llmCandidateRankingTimeoutMs
        Preferences.llmInputtingPauseMs = Preferences.llmInputtingPauseMs
        Preferences.llmShowActivityIndicator = Preferences.llmShowActivityIndicator
        Preferences.llmShowDebugAlert = Preferences.llmShowDebugAlert
        Preferences.llmInputtingTriggerMode = Preferences.llmInputtingTriggerMode
        Preferences.llmCloudProvider = Preferences.llmCloudProvider
        Preferences.llmGoogleModelName = Preferences.llmGoogleModelName
        Preferences.llmGoogleEndpoint = Preferences.llmGoogleEndpoint
        Preferences.llmGoogleAPIKey = Preferences.llmGoogleAPIKey
        Preferences.llmGoogleThinkingLevel = Preferences.llmGoogleThinkingLevel
        Preferences.llmOpenAIModelName = Preferences.llmOpenAIModelName
        Preferences.llmOpenAIEndpoint = Preferences.llmOpenAIEndpoint
        Preferences.llmOpenAIAPIKey = Preferences.llmOpenAIAPIKey
    }

    @EnumUserDefault(key: kKeyboardLayoutPreferenceKey, defaultValue: KeyboardLayout.standard)
    @objc static var keyboardLayout: KeyboardLayout

    @objc static var keyboardLayoutName: String {
        keyboardLayout.name
    }

    @UserDefault(key: kBasisKeyboardLayoutPreferenceKey, defaultValue: "com.apple.keylayout.US")
    @objc static var basisKeyboardLayout: String

    @UserDefault(
        key: kFunctionKeyKeyboardLayoutPreferenceKey, defaultValue: "com.apple.keylayout.US")
    @objc static var functionKeyboardLayout: String

    @UserDefault(key: kFunctionKeyKeyboardLayoutOverrideIncludeShiftKey, defaultValue: false)
    @objc static var functionKeyKeyboardLayoutOverrideIncludeShiftKey: Bool

    @CandidateListTextSize(key: kCandidateListTextSizeKey)
    @objc static var candidateListTextSize: CGFloat

    @UserDefault(key: kSelectPhraseAfterCursorAsCandidateKey, defaultValue: false)
    @objc static var selectPhraseAfterCursorAsCandidate: Bool

    @UserDefault(key: kMoveCursorAfterSelectingCandidateKey, defaultValue: false)
    @objc static var moveCursorAfterSelectingCandidate: Bool

    @UserDefault(key: kUseHorizontalCandidateListPreferenceKey, defaultValue: false)
    @objc static var useHorizontalCandidateList: Bool

    @UserDefault(key: kChooseCandidateUsingSpaceKey, defaultValue: true)
    @objc static var chooseCandidateUsingSpace: Bool

    @UserDefault(key: kChineseConversionEnabledKey, defaultValue: false)
    @objc static var chineseConversionEnabled: Bool

    @objc static func toggleChineseConversionEnabled() -> Bool {
        chineseConversionEnabled = !chineseConversionEnabled
        return chineseConversionEnabled
    }

    @UserDefault(key: kHalfWidthPunctuationEnabledKey, defaultValue: false)
    @objc static var halfWidthPunctuationEnabled: Bool

    @objc static func toggleHalfWidthPunctuationEnabled() -> Bool {
        halfWidthPunctuationEnabled = !halfWidthPunctuationEnabled
        return halfWidthPunctuationEnabled
    }

    @UserDefault(key: kEscToCleanInputBufferKey, defaultValue: false)
    @objc static var escToCleanInputBuffer: Bool

    @UserDefault(key: kKeepReadingUponCompositionError, defaultValue: false)
    @objc static var keepReadingUponCompositionError: Bool

    // MARK: Optional settings

    @UserDefault(key: kCandidateTextFontName, defaultValue: nil)
    @objc static var candidateTextFontName: String?

    @UserDefault(key: kCandidateKeyLabelFontName, defaultValue: nil)
    @objc static var candidateKeyLabelFontName: String?

    @UserDefault(key: kCandidateKeys, defaultValue: kDefaultKeys)
    @objc static var candidateKeys: String

    @objc static var defaultCandidateKeys: String {
        kDefaultKeys
    }
    @objc static var suggestedCandidateKeys: [String] {
        [kDefaultKeys, "asdfghjkl", "asdfzxcvb"]
    }

    static func validate(candidateKeys: String) throws {
        let trimmed = candidateKeys.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CandidateKeyError.empty
        }
        if !trimmed.canBeConverted(to: .ascii) {
            throw CandidateKeyError.invalidCharacters
        }
        if trimmed.contains(" ") {
            throw CandidateKeyError.containSpace
        }
        if trimmed.count < 4 {
            throw CandidateKeyError.tooShort
        }
        if trimmed.count > 15 {
            throw CandidateKeyError.tooLong
        }
        let set = Set(Array(trimmed))
        if set.count != trimmed.count {
            throw CandidateKeyError.duplicatedCharacters
        }
    }

    enum CandidateKeyError: Error, LocalizedError {
        case empty
        case invalidCharacters
        case containSpace
        case duplicatedCharacters
        case tooShort
        case tooLong

        var errorDescription: String? {
            switch self {
            case .empty:
                return NSLocalizedString("Candidates keys cannot be empty.", comment: "")
            case .invalidCharacters:
                return NSLocalizedString(
                    "Candidate keys can only contain Latin characters and numbers.", comment: "")
            case .containSpace:
                return NSLocalizedString("Candidate keys cannot contain space.", comment: "")
            case .duplicatedCharacters:
                return NSLocalizedString("There should not be duplicated keys.", comment: "")
            case .tooShort:
                return NSLocalizedString(
                    "Candidate keys cannot be shorter than 4 characters.", comment: "")
            case .tooLong:
                return NSLocalizedString(
                    "Candidate keys cannot be longer than 15 characters.", comment: "")
            }
        }
    }
}

/// An enumeration representing keys used for moving the cursor in the
/// application.
@objc enum MovingCursorKey: Int {
    case disabled = 0
    case useJK = 1
    case useHL = 2
}

extension MovingCursorKey {
    var name: String {
        switch self {
        case .disabled: "Disabled"
        case .useJK: "J/K"
        case .useHL: "H/L"
        }
    }
}

extension Preferences {
    /// Whether allows moving the cursor by J/K or H/L keys, when the candidate
    /// window is presented.
    @EnumUserDefault(key: kAllowMovingCursorWhenChoosingCandidates, defaultValue: .disabled)
    @objc static var allowMovingCursorWhenChoosingCandidates: MovingCursorKey
}

extension Preferences {
    /// The conversion style.
    ///
    /// - 0: convert the output
    /// - 1: convert the phrase models.
    @EnumUserDefault(key: kChineseConversionStyleKey, defaultValue: ChineseConversionStyle.output)
    @objc static var chineseConversionStyle: ChineseConversionStyle

    @objc static var chineseConversionStyleName: String {
        chineseConversionStyle.name
    }
}

extension Preferences {

    @UserDefault(key: kPhraseReplacementEnabledKey, defaultValue: false)
    @objc static var phraseReplacementEnabled: Bool

    @objc static func togglePhraseReplacementEnabled() -> Bool {
        phraseReplacementEnabled = !phraseReplacementEnabled
        return phraseReplacementEnabled
    }

    @UserDefault(key: kAssociatedPhrasesEnabledKey, defaultValue: false)
    @objc static var associatedPhrasesEnabled: Bool

    @objc static func toggleAssociatedPhrasesEnabled() -> Bool {
        associatedPhrasesEnabled = !associatedPhrasesEnabled
        return associatedPhrasesEnabled
    }

    @UserDefault(key: kShiftEnterEnabledKey, defaultValue: true)
    @objc static var shiftEnterEnabled: Bool

    @UserDefault(key: kRepeatedPunctuationToSelectCandidateEnabledKey, defaultValue: false)
    @objc static var repeatedPunctuationToSelectCandidateEnabled: Bool
}

@objc enum ControlEnterOutput: Int {
    case off = 0
    case bpmfReading = 1
    case htmlRuby = 2
    case brailleUnicode = 3
    case hanyuPinyin = 4
    case brailleAscii = 5
}

extension ControlEnterOutput {
    var name: String {
        switch self {
        case .off: "Off"
        case .bpmfReading: "Bopomofo Reading"
        case .htmlRuby: "HTML Ruby Text"
        case .brailleUnicode: "Taiwanese Braille (Unicode)"
        case .brailleAscii: "Taiwanese Braille (ASCII)"
        case .hanyuPinyin: "Hanyu Pinyin"
        }
    }
}

extension Preferences {
    /// The behavior of pressing letter keys.
    ///
    /// - 0: Output upper-cased letters directly.
    /// - 1: Output lower-cased letters in the composing buffer.
    @UserDefault(key: kLetterBehaviorKey, defaultValue: 0)
    @objc static var letterBehavior: Int

    /// The behavior of pressing Ctrl + Enter.
    ///
    /// - 0: Disabled.
    /// - 1: Output BPMF readings.
    @EnumUserDefault(key: kControlEnterOutputKey, defaultValue: .off)
    @objc static var controlEnterOutput: ControlEnterOutput
}

@objc class UserPhraseLocationHelper: NSObject {
    @objc static var defaultUserPhraseLocation: String {
        let paths = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true)
        let appSupportPath = paths.first!
        return (appSupportPath as NSString).appendingPathComponent("McBopomofo")
    }
}

extension NSNotification.Name {
    static var userPhraseLocationDidChange = NSNotification.Name(
        rawValue: "UserPhraseLocationDidChangeNotification")
}

extension Preferences {

    static func postUserPhraseLocationNotification() {
        let location: String = {
            if !useCustomUserPhraseLocation {
                return UserPhraseLocationHelper.defaultUserPhraseLocation
            }
            if customUserPhraseLocation.isEmpty {
                return UserPhraseLocationHelper.defaultUserPhraseLocation
            }
            return customUserPhraseLocation
        }()
        let notification = Notification(
            name: .userPhraseLocationDidChange, object: self,
            userInfo: [
                "location": location
            ])
        NotificationQueue.default.dequeueNotifications(matching: notification, coalesceMask: 0)
        NotificationQueue.default.enqueue(notification, postingStyle: .now)
    }

    @UserDefault(key: kUseCustomUserPhraseLocation, defaultValue: false)
    @objc static var useCustomUserPhraseLocation: Bool {
        didSet {
            postUserPhraseLocationNotification()
        }
    }

    @UserDefault(key: kCustomUserPhraseLocation, defaultValue: "")
    @objc static var customUserPhraseLocation: String {
        didSet {
            postUserPhraseLocationNotification()
        }
    }
}

extension Preferences {
    static func defaultAddPhraseHookPath() -> String {
        let bundle = Bundle.main
        let hookPath = bundle.path(forResource: "add-phrase-hook", ofType: "sh")
        return hookPath!
    }

    @UserDefault(key: kAddPhraseHookEnabledKey, defaultValue: false)
    @objc static var addPhraseHookEnabled: Bool

    @UserDefaultWithFunction(
        key: kAddPhraseHookPath, defaultValueFunction: defaultAddPhraseHookPath)
    @objc static var addPhraseHookPath: String
}

extension Preferences {
    @UserDefault(key: kSelectCandidateWithNumericKeypad, defaultValue: false)
    @objc static var selectCandidateWithNumericKeypad: Bool
}

extension Preferences {
    @UserDefault(key: kBig5InputEnabledKey, defaultValue: true)
    @objc static var big5InputEnabled: Bool
}

extension Preferences {
    @UserDefault(key: kBeepUponInputErrorKey, defaultValue: true)
    @objc static var beepUponInputError: Bool
}

extension Preferences {
    @UserDefault(key: kEnableUserPhrasesInPlainBopomofo, defaultValue: false)
    @objc static var enableUserPhrasesInPlainBopomofo: Bool
}

extension Preferences {
    @UserDefault(key: kAllowChangingPriorTone, defaultValue: false)
    @objc static var allowChangingPriorTone: Bool
}

extension Preferences {
    @UserDefault(key: kLLMCandidateRankingEnabledKey, defaultValue: false)
    @objc static var llmCandidateRankingEnabled: Bool

    @UserDefault(key: kLLMEditActionRerankingEnabledKey, defaultValue: false)
    @objc static var llmEditActionRerankingEnabled: Bool

    @UserDefault(key: kLLMCorrectionMemoryReadsEnabledKey, defaultValue: true)
    @objc static var llmCorrectionMemoryReadsEnabled: Bool

    @UserDefault(key: kLLMCorrectionMemoryWritesEnabledKey, defaultValue: true)
    @objc static var llmCorrectionMemoryWritesEnabled: Bool

    @UserDefault(key: kLLMCorrectionLearningEnabledKey, defaultValue: true)
    @objc static var llmCorrectionLearningEnabled: Bool

    @BoundedIntUserDefault(
        key: kLLMCorrectionMinimumConfidencePercentKey,
        defaultValue: kDefaultLLMCorrectionMinimumConfidencePercent,
        minValue: 0, maxValue: 100)
    @objc static var llmCorrectionMinimumConfidencePercent: Int

    @BoundedIntUserDefault(
        key: kLLMCorrectionShortTermHalfLifeMinutesKey,
        defaultValue: kDefaultLLMCorrectionShortTermHalfLifeMinutes,
        minValue: 1, maxValue: 10_080)
    @objc static var llmCorrectionShortTermHalfLifeMinutes: Int

    @BoundedIntUserDefault(
        key: kLLMCorrectionShortTermMaximumAgeMinutesKey,
        defaultValue: kDefaultLLMCorrectionShortTermMaximumAgeMinutes,
        minValue: 1, maxValue: 43_200)
    @objc static var llmCorrectionShortTermMaximumAgeMinutes: Int

    @BoundedIntUserDefault(
        key: kLLMCorrectionLongTermHalfLifeDaysKey,
        defaultValue: kDefaultLLMCorrectionLongTermHalfLifeDays,
        minValue: 1, maxValue: 3_650)
    @objc static var llmCorrectionLongTermHalfLifeDays: Int

    @BoundedIntUserDefault(
        key: kLLMCorrectionLongTermMaximumAgeDaysKey,
        defaultValue: kDefaultLLMCorrectionLongTermMaximumAgeDays,
        minValue: 1, maxValue: 3_650)
    @objc static var llmCorrectionLongTermMaximumAgeDays: Int

    @BoundedIntUserDefault(
        key: kLLMCorrectionLongTermMinimumAcceptancesKey,
        defaultValue: kDefaultLLMCorrectionLongTermMinimumAcceptances,
        minValue: 1, maxValue: 100)
    @objc static var llmCorrectionLongTermMinimumAcceptances: Int

    @BoundedIntUserDefault(
        key: kLLMCorrectionLongTermMinimumSessionsKey,
        defaultValue: kDefaultLLMCorrectionLongTermMinimumSessions,
        minValue: 1, maxValue: 20)
    @objc static var llmCorrectionLongTermMinimumSessions: Int

    @BoundedIntUserDefault(
        key: kLLMCorrectionMinimumAcceptanceRatioPercentKey,
        defaultValue: kDefaultLLMCorrectionMinimumAcceptanceRatioPercent,
        minValue: 0, maxValue: 100)
    @objc static var llmCorrectionMinimumAcceptanceRatioPercent: Int

    @objc static func resetLLMCorrectionMemoryTuningDefaults() {
        llmCorrectionMinimumConfidencePercent =
            kDefaultLLMCorrectionMinimumConfidencePercent
        llmCorrectionShortTermHalfLifeMinutes =
            kDefaultLLMCorrectionShortTermHalfLifeMinutes
        llmCorrectionShortTermMaximumAgeMinutes =
            kDefaultLLMCorrectionShortTermMaximumAgeMinutes
        llmCorrectionLongTermHalfLifeDays =
            kDefaultLLMCorrectionLongTermHalfLifeDays
        llmCorrectionLongTermMaximumAgeDays =
            kDefaultLLMCorrectionLongTermMaximumAgeDays
        llmCorrectionLongTermMinimumAcceptances =
            kDefaultLLMCorrectionLongTermMinimumAcceptances
        llmCorrectionLongTermMinimumSessions =
            kDefaultLLMCorrectionLongTermMinimumSessions
        llmCorrectionMinimumAcceptanceRatioPercent =
            kDefaultLLMCorrectionMinimumAcceptanceRatioPercent
    }

    @BoundedIntUserDefault(
        key: kLLMCandidateRankingTimeoutMsKey, defaultValue: kDefaultLLMCandidateRankingTimeoutMs,
        minValue: kMinLLMCandidateRankingTimeoutMs, maxValue: kMaxLLMCandidateRankingTimeoutMs)
    @objc static var llmCandidateRankingTimeoutMs: Int

    @BoundedIntUserDefault(
        key: kLLMInputtingPauseMsKey, defaultValue: kDefaultLLMInputtingPauseMs,
        minValue: kMinLLMInputtingPauseMs, maxValue: kMaxLLMInputtingPauseMs)
    @objc static var llmInputtingPauseMs: Int

    @UserDefault(key: kLLMShowActivityIndicatorKey, defaultValue: true)
    @objc static var llmShowActivityIndicator: Bool

    @UserDefault(key: kLLMShowDebugAlertKey, defaultValue: false)
    @objc static var llmShowDebugAlert: Bool

    @EnumUserDefault(key: kLLMInputtingTriggerModeKey, defaultValue: .continuous)
    @objc static var llmInputtingTriggerMode: LLMInputtingTriggerMode

    @EnumUserDefault(key: kLLMCloudProviderKey, defaultValue: .google)
    @objc static var llmCloudProvider: LLMCloudProvider

    @UserDefault(key: kLLMGoogleModelNameKey, defaultValue: kDefaultLLMGoogleModelName)
    @objc static var llmGoogleModelName: String

    @UserDefault(key: kLLMGoogleEndpointKey, defaultValue: kDefaultLLMGoogleEndpoint)
    @objc static var llmGoogleEndpoint: String

    @UserDefault(key: kLLMGoogleAPIKeyKey, defaultValue: "")
    @objc static var llmGoogleAPIKey: String

    @EnumUserDefault(key: kLLMGoogleThinkingLevelKey, defaultValue: .off)
    @objc static var llmGoogleThinkingLevel: LLMGoogleThinkingLevel

    @UserDefault(key: kLLMOpenAIModelNameKey, defaultValue: kDefaultLLMOpenAIModelName)
    @objc static var llmOpenAIModelName: String

    @UserDefault(key: kLLMOpenAIEndpointKey, defaultValue: kDefaultLLMOpenAIEndpoint)
    @objc static var llmOpenAIEndpoint: String

    @UserDefault(key: kLLMOpenAIAPIKeyKey, defaultValue: "")
    @objc static var llmOpenAIAPIKey: String

    static let googlePresetModelNames: [String] = [
        "gemini-3.6-flash",
        "gemini-flash-latest",
        "gemini-3-flash-preview",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
    ]

    static let googlePresetEndpoints: [String] = [
        "https://generativelanguage.googleapis.com/v1beta"
    ]

    // Whether to enable Bopomofo Font Annotation Support.
    @UserDefault(key: kBopomofoFontAnnotationSupportEnabled, defaultValue: false)
    @objc static var bopomofoFontAnnotationSupportEnabled: Bool

    @objc static func toggleBopomofoFontAnnotationSupportEnabled() -> Bool {
        bopomofoFontAnnotationSupportEnabled = !bopomofoFontAnnotationSupportEnabled
        return bopomofoFontAnnotationSupportEnabled
    }

    // Whether to show the "Bopomofo Font Annotation Support" toggle in the input menu.
    @UserDefault(key: kShowBopomofoFontAnnotationSupportItemInInputMenu, defaultValue: false)
    @objc static var showBopomofoFontAnnotationSupportItemInInputMenu: Bool

    // Whether at first launch, we have checked if there are any bpmfvs-supporting fonts installed,
    // and enable showBopomofoFontAnnotationSupportItemInInputMenu as a result. No more check is
    // performed once this flag is turned to true.
    @UserDefault(
        key: kBopomofoFontAnnotationSupportMenuItemEnabledByInstalledFontsCheck_V1,
        defaultValue: false)
    @objc static var bopomofoFontAnnotationSupportMenuItemEnabledByInstalledFontsCheck_V1: Bool
}

extension Preferences {
    static func createReport() -> String {
        var lines: [String] = []
        lines.append("- McBopomofo Settings")
        lines.append("  - Keyboard Layout: \(Preferences.keyboardLayout.name)")
        lines.append("  - Basis Keyboard Layout: \(Preferences.basisKeyboardLayout)")
        lines.append("  - Function Keyboard Layout: \(Preferences.functionKeyboardLayout)")
        lines.append("  - Candidate Keys: \(Preferences.candidateKeys)")
        lines.append(
            "  - Selection Mode: \(Preferences.selectPhraseAfterCursorAsCandidate ? "After Cursor" : "Before Cursor")"
        )
        lines.append(
            "  - Move Cursor After Selecting Candidate: \(Preferences.moveCursorAfterSelectingCandidate ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Candidate Window: \(Preferences.useHorizontalCandidateList ? "Horizontal" : "Vertical")"
        )
        lines.append(
            "  - Chinese Conversion: \(Preferences.chineseConversionEnabled ? "Enabled" : "Disabled")"
        )
        lines
            .append(
                "  - Chinese Conversion Style: \(Preferences.chineseConversionStyle.name)"
            )
        lines.append(
            "  - Punctuations: \(Preferences.halfWidthPunctuationEnabled ? "Half-width" : "Full-width")"
        )
        lines.append(
            "  - Select Candidate With Numeric Keyboard: \(Preferences.selectCandidateWithNumericKeypad ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Allow Ctrl + ` For Big5 Input: \(Preferences.big5InputEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Phrase Replacement: \(Preferences.phraseReplacementEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Associated Phrases (McBopomofo): \(Preferences.associatedPhrasesEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Associated Phrases (Plain Bopomofo): \(Preferences.enableUserPhrasesInPlainBopomofo ? "Enabled" : "Disabled")"
        )

        lines.append("  - Letter Keys: \(Preferences.letterBehavior)")
        lines.append("  - Ctrl + Enter Key: \(Preferences.controlEnterOutput.name)")
        lines.append(
            "  - Shift + Enter Key For Associated Phrases: \(Preferences.shiftEnterEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Repeated Keys For Next Candidate: \(Preferences.repeatedPunctuationToSelectCandidateEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Add Phrase Hook: \(Preferences.addPhraseHookEnabled ? "Enabled" : "Disabled")")
        lines.append("  - Add Phrase Hook Path: \(Preferences.addPhraseHookPath)")
        lines.append(
            "  - Beep Upon Errors: \(Preferences.beepUponInputError ? "Enabled" : "Disabled")")
        lines.append(
            "  - Moving Cursor When Choosing Candidates: \(Preferences.allowMovingCursorWhenChoosingCandidates)"
        )
        lines.append(
            "  - LLM Candidate Ranking: \(Preferences.llmCandidateRankingEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - LLM Edit Action Reranking: \(Preferences.llmEditActionRerankingEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - LLM Correction Memory Reads: \(Preferences.llmCorrectionMemoryReadsEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - LLM Correction Memory Writes: \(Preferences.llmCorrectionMemoryWritesEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - Learn from Accepted LLM Corrections: \(Preferences.llmCorrectionLearningEnabled ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - LLM Correction Minimum Confidence: \(Preferences.llmCorrectionMinimumConfidencePercent)%"
        )
        lines.append(
            "  - LLM Correction Short-Term Half-Life: \(Preferences.llmCorrectionShortTermHalfLifeMinutes) minutes"
        )
        lines.append(
            "  - LLM Correction Short-Term Maximum Age: \(Preferences.llmCorrectionShortTermMaximumAgeMinutes) minutes"
        )
        lines.append(
            "  - LLM Correction Long-Term Half-Life: \(Preferences.llmCorrectionLongTermHalfLifeDays) days"
        )
        lines.append(
            "  - LLM Correction Long-Term Maximum Age: \(Preferences.llmCorrectionLongTermMaximumAgeDays) days"
        )
        lines.append(
            "  - LLM Correction Long-Term Minimum Acceptances: \(Preferences.llmCorrectionLongTermMinimumAcceptances)"
        )
        lines.append(
            "  - LLM Correction Long-Term Minimum Sessions: \(Preferences.llmCorrectionLongTermMinimumSessions)"
        )
        lines.append(
            "  - LLM Correction Minimum Acceptance Ratio: \(Preferences.llmCorrectionMinimumAcceptanceRatioPercent)%"
        )
        lines.append(
            "  - LLM Candidate Ranking Timeout: \(Preferences.llmCandidateRankingTimeoutMs) ms")
        lines.append("  - LLM Inputting Pause: \(Preferences.llmInputtingPauseMs) ms")
        lines.append(
            "  - LLM Activity Indicator: \(Preferences.llmShowActivityIndicator ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - LLM Debug Alert: \(Preferences.llmShowDebugAlert ? "Enabled" : "Disabled")"
        )
        lines.append(
            "  - LLM Inputting Trigger Mode: \(Preferences.llmInputtingTriggerMode.name)"
        )
        lines.append(
            "  - LLM Cloud Provider: \(Preferences.llmCloudProvider.name)"
        )
        lines.append("  - LLM Google Model: \(Preferences.llmGoogleModelName)")
        lines.append("  - LLM Google Endpoint: \(Preferences.llmGoogleEndpoint)")
        lines.append(
            "  - LLM Google API Key: \(Preferences.llmGoogleAPIKey.isEmpty ? "<empty>" : "<redacted>")"
        )
        lines.append(
            "  - LLM Google Thinking Level: \(Preferences.llmGoogleThinkingLevel.name) (budget: \(Preferences.llmGoogleThinkingLevel.thinkingBudget))"
        )
        lines.append("  - LLM OpenAI Model: \(Preferences.llmOpenAIModelName)")
        lines.append("  - LLM OpenAI Endpoint: \(Preferences.llmOpenAIEndpoint)")
        lines.append(
            "  - LLM OpenAI API Key: \(Preferences.llmOpenAIAPIKey.isEmpty ? "<empty>" : "<redacted>")"
        )
        return lines.joined(separator: "\n")
    }
}

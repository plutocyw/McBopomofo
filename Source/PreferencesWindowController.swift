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

import Carbon
import Cocoa
import InfoCollector

extension NSToolbarItem.Identifier {
    fileprivate static let basic = NSToolbarItem.Identifier(rawValue: "basic")
    fileprivate static let userPhrases = NSToolbarItem.Identifier(rawValue: "user_phrases")
    fileprivate static let advanced = NSToolbarItem.Identifier(rawValue: "advanced")
}

private let kWindowTitleHeight: CGFloat = 78

// Please note that the class should be exposed as "PreferencesWindowController"
// in Objective-C in order to let IMK to see the same class name as
// the "InputMethodServerPreferencesWindowControllerClass" in Info.plist.
@objc(PreferencesWindowController) class PreferencesWindowController: NSWindowController {
    private let kLLMControlBottomInset: CGFloat = 12
    private let kLLMControlSpacing: CGFloat = 8
    private let kLLMControlExtraViewHeight: CGFloat = 472

    @IBOutlet weak var fontSizePopUpButton: NSPopUpButton!
    @IBOutlet weak var basisKeyboardLayoutButton: NSPopUpButton!
    @IBOutlet weak var selectionKeyComboBox: NSComboBox!

    @IBOutlet weak var customUserPhraseLocationEnabledButton: NSPopUpButton!
    @IBOutlet weak var userPhrasesTextField: NSTextField!
    @IBOutlet weak var chooseUserPhrasesFolderButton: NSButton!
    @IBOutlet weak var openUserPhrasesFolderButton: NSButton!

    @IBOutlet weak var basicSettingsView: NSView!
    @IBOutlet weak var userPhrasesSettingsView: NSView!
    @IBOutlet weak var advancedSettingsView: NSView!

    @IBOutlet weak var addPhraseHookPathField: NSTextField!
    private var llmRankingEnabledButton: NSButton?
    private var llmActivityIndicatorButton: NSButton?
    private var llmDebugAlertButton: NSButton?
    private var llmTimeoutLabel: NSTextField?
    private var llmTimeoutTextField: NSTextField?
    private var llmTimeoutStepper: NSStepper?
    private var llmPauseLabel: NSTextField?
    private var llmPauseTextField: NSTextField?
    private var llmPauseStepper: NSStepper?
    private var llmInputtingTriggerModeLabel: NSTextField?
    private var llmInputtingTriggerModePopUpButton: NSPopUpButton?
    private var llmGoogleModelLabel: NSTextField?
    private var llmGoogleModelTextField: NSTextField?
    private var llmGoogleEndpointLabel: NSTextField?
    private var llmGoogleEndpointTextField: NSTextField?
    private var llmGoogleAPIKeyLabel: NSTextField?
    private var llmGoogleAPIKeySecureTextField: NSSecureTextField?
    private var llmGoogleAPIKeyPlainTextField: NSTextField?
    private var llmGoogleAPIKeyRevealButton: NSButton?
    private var llmGoogleAPIKeyRevealed = false
    private var llmGoogleThinkingLevelLabel: NSTextField?
    private var llmGoogleThinkingLevelPopUpButton: NSPopUpButton?
    private var llmProviderLabel: NSTextField?
    private var llmProviderPopUpButton: NSPopUpButton?
    private var llmOllamaEndpointLabel: NSTextField?
    private var llmOllamaEndpointTextField: NSTextField?
    private var llmOllamaModelLabel: NSTextField?
    private var llmOllamaModelTextField: NSTextField?

    override func awakeFromNib() {
        let toolbar = NSToolbar(identifier: "preference toolbar")
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.sizeMode = .default
        toolbar.delegate = self
        toolbar.selectedItemIdentifier = .basic
        toolbar.showsBaselineSeparator = true
        window?.titlebarAppearsTransparent = false
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .preference
        }
        window?.toolbar = toolbar
        window?.title = NSLocalizedString("Basic", comment: "")
        use(view: basicSettingsView)

        // When the `CandidateListTextSize` is not yet populated, the pop up
        // button adds an empty item and selects that empty item. This code
        // correctly sets the default text size, and removes the empty item
        // at the end.
        let selectedSizeTitle = fontSizePopUpButton.selectedItem?.title ?? ""
        if selectedSizeTitle.isEmpty {
            let intFontSize = Int(Preferences.candidateListTextSize)
            let intFontSizeStr = String.init(format: "%d", intFontSize)

            var selected = false
            for item in fontSizePopUpButton.itemArray {
                if item.title == intFontSizeStr {
                    fontSizePopUpButton.select(item)
                    selected = true
                    break
                }
            }

            // If not selected, Preferences.candidateListTextSize is not set to
            // one of the options provided in the pop up button. Let's list the
            // option for the user.
            if !selected {
                var insertIndex = 0

                // Place the item in the right place. We take advantage of the
                // fact that Int("") returns nil, and so if the custom font size
                // is larger than the largest item in the list (say 96), this
                // code guarantees to place the custom font size item right below
                // that largest item and before the empty item (which will then
                // be removed by the code below).
                for (index, item) in fontSizePopUpButton.itemArray.enumerated() {
                    if intFontSize < (Int(item.title) ?? Int.max) {
                        insertIndex = index
                        break
                    }
                }
                fontSizePopUpButton.insertItem(withTitle: intFontSizeStr, at: insertIndex)
                fontSizePopUpButton.selectItem(at: insertIndex)
            }

            // Remove the last item if it's empty
            let items = fontSizePopUpButton.itemArray
            if let lastItem = items.last {
                if lastItem.title.isEmpty {
                    fontSizePopUpButton.removeItem(at: items.count - 1)
                }
            }
        }

        let list = TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
        var usKeyboardLayoutItem: NSMenuItem? = nil
        var chosenItem: NSMenuItem? = nil

        basisKeyboardLayoutButton.menu?.removeAllItems()

        let basisKeyboardLayoutID = Preferences.basisKeyboardLayout
        for source in list {

            func getString(_ key: CFString) -> String? {
                if let ptr = TISGetInputSourceProperty(source, key) {
                    return String(Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue())
                }
                return nil
            }

            func getBool(_ key: CFString) -> Bool? {
                if let ptr = TISGetInputSourceProperty(source, key) {
                    return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue()
                        == kCFBooleanTrue
                }
                return nil
            }

            if let category = getString(kTISPropertyInputSourceCategory) {
                if category != String(kTISCategoryKeyboardInputSource) {
                    continue
                }
            } else {
                continue
            }

            if let asciiCapable = getBool(kTISPropertyInputSourceIsASCIICapable) {
                if !asciiCapable {
                    continue
                }
            } else {
                continue
            }

            if let sourceType = getString(kTISPropertyInputSourceType) {
                if sourceType != String(kTISTypeKeyboardLayout) {
                    continue
                }
            } else {
                continue
            }

            guard let sourceID = getString(kTISPropertyInputSourceID),
                let localizedName = getString(kTISPropertyLocalizedName)
            else {
                continue
            }

            let menuItem = NSMenuItem()
            menuItem.title = localizedName
            menuItem.representedObject = sourceID

            if sourceID == "com.apple.keylayout.US" {
                usKeyboardLayoutItem = menuItem
            }
            if basisKeyboardLayoutID == sourceID {
                chosenItem = menuItem
            }
            basisKeyboardLayoutButton.menu?.addItem(menuItem)
        }

        basisKeyboardLayoutButton.select(chosenItem ?? usKeyboardLayoutItem)
        selectionKeyComboBox.usesDataSource = false
        selectionKeyComboBox.removeAllItems()
        selectionKeyComboBox.addItems(withObjectValues: Preferences.suggestedCandidateKeys)

        var candidateSelectionKeys = Preferences.candidateKeys
        if candidateSelectionKeys.isEmpty {
            candidateSelectionKeys = Preferences.defaultCandidateKeys
        }
        selectionKeyComboBox.stringValue = candidateSelectionKeys

        if #available(macOS 11.0, *) {
            chooseUserPhrasesFolderButton.image = NSImage(
                systemSymbolName: "folder", accessibilityDescription: "Folder")
        }
        let index = Preferences.useCustomUserPhraseLocation ? 1 : 0
        customUserPhraseLocationEnabledButton.selectItem(at: index)
        updateUserPhraseLocation()
        addPhraseHookPathField.stringValue = Preferences.addPhraseHookPath
        configureLLMControls()
    }

    @IBAction func updateBasisKeyboardLayoutAction(_ sender: Any) {
        if let sourceID = basisKeyboardLayoutButton.selectedItem?.representedObject as? String {
            Preferences.basisKeyboardLayout = sourceID
        }
    }

    @IBAction func changeSelectionKeyAction(_ sender: Any) {
        guard
            let keys = (sender as AnyObject).stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        else {
            return
        }
        do {
            try Preferences.validate(candidateKeys: keys)
            Preferences.candidateKeys = keys
        } catch Preferences.CandidateKeyError.empty {
            selectionKeyComboBox.stringValue = Preferences.candidateKeys
        } catch {
            if let window = window {
                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: window) { response in
                    self.selectionKeyComboBox.stringValue = Preferences.candidateKeys
                }
            }
        }
    }

    func updateUserPhraseLocation() {
        if Preferences.useCustomUserPhraseLocation {
            userPhrasesTextField.stringValue = Preferences.customUserPhraseLocation
            openUserPhrasesFolderButton.title = Preferences.customUserPhraseLocation
        } else {
            userPhrasesTextField.stringValue = ""
            openUserPhrasesFolderButton.title = UserPhraseLocationHelper.defaultUserPhraseLocation
        }
    }

    @IBAction func changeCustomUserPhraseLocationEnabledAction(_ sender: Any) {
        guard let control = sender as? NSPopUpButton else {
            return
        }
        let enabled = control.selectedTag() > 0
        Preferences.useCustomUserPhraseLocation = enabled
        if enabled {
            if Preferences.customUserPhraseLocation.isEmpty {
                Preferences.customUserPhraseLocation =
                    UserPhraseLocationHelper.defaultUserPhraseLocation
            }
        }
        updateUserPhraseLocation()
    }

    @IBAction func changeUserPhraseLocationAction(_ sender: Any) {
        guard let control = sender as? NSControl else {
            return
        }
        let path = control.stringValue.trimmingCharacters(in: .whitespaces)
        if FileManager.default.fileExists(atPath: path) == false {
            try? FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: true)
        }
        Preferences.customUserPhraseLocation = path
        updateUserPhraseLocation()
    }

    @IBAction func openUserPhrasedFolderAction(_ sender: Any) {
        let path =
            Preferences.useCustomUserPhraseLocation
            ? Preferences.customUserPhraseLocation
            : UserPhraseLocationHelper.defaultUserPhraseLocation
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    @IBAction func changeUserPhraseLocationFromPanelAction(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        let result = panel.runModal()

        if result == .OK, let url = panel.urls.first {
            let path = url.path
            Preferences.customUserPhraseLocation = path
            updateUserPhraseLocation()
        }
    }

    @IBAction func openSystemInfoReport(_ sender: Any) {
        Task { @MainActor in
            await openSystemInfoReportAsync()
        }
    }

    @objc private func toggleLLMCandidateRankingEnabled(_ sender: NSButton) {
        Preferences.llmCandidateRankingEnabled = (sender.state == .on)
        refreshLLMControlsState()
    }

    @objc private func toggleLLMActivityIndicator(_ sender: NSButton) {
        Preferences.llmShowActivityIndicator = (sender.state == .on)
        refreshLLMControlsState()
    }

    @objc private func toggleLLMDebugAlert(_ sender: NSButton) {
        Preferences.llmShowDebugAlert = (sender.state == .on)
        refreshLLMControlsState()
    }

    @objc private func changeLLMTimeoutTextField(_ sender: NSTextField) {
        Preferences.llmCandidateRankingTimeoutMs = sender.integerValue
        refreshLLMControlsState()
    }

    @objc private func changeLLMTimeoutStepper(_ sender: NSStepper) {
        Preferences.llmCandidateRankingTimeoutMs = sender.integerValue
        refreshLLMControlsState()
    }

    @objc private func changeLLMPauseTextField(_ sender: NSTextField) {
        Preferences.llmInputtingPauseMs = sender.integerValue
        refreshLLMControlsState()
    }

    @objc private func changeLLMPauseStepper(_ sender: NSStepper) {
        Preferences.llmInputtingPauseMs = sender.integerValue
        refreshLLMControlsState()
    }

    @objc private func changeLLMInputtingTriggerMode(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem else {
            return
        }
        let mode = LLMInputtingTriggerMode(rawValue: selectedItem.tag) ?? .continuous
        Preferences.llmInputtingTriggerMode = mode
        refreshLLMControlsState()
    }

    @objc private func changeLLMGoogleModel(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Preferences.llmGoogleModelName = text.isEmpty ? "gemini-2.5-flash-lite" : text
        refreshLLMControlsState()
    }

    @objc private func changeLLMGoogleEndpoint(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Preferences.llmGoogleEndpoint =
            text.isEmpty ? "https://generativelanguage.googleapis.com/v1beta" : text
        refreshLLMControlsState()
    }

    @objc private func changeLLMGoogleAPIKey(_ sender: NSTextField) {
        Preferences.llmGoogleAPIKey = sender.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines)
        refreshLLMControlsState()
    }

    @objc private func toggleLLMGoogleAPIKeyVisibility(_ sender: NSButton) {
        llmGoogleAPIKeyRevealed.toggle()
        refreshLLMControlsState()
    }

    @objc private func changeLLMProvider(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem else {
            return
        }
        let provider = LLMProvider(rawValue: selectedItem.tag) ?? .googleCloud
        Preferences.llmProvider = provider
        refreshLLMControlsState()
    }

    @objc private func changeLLMOllamaEndpoint(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Preferences.llmOllamaEndpoint = text.isEmpty ? "http://localhost:11434" : text
        refreshLLMControlsState()
    }

    @objc private func changeLLMOllamaModel(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Preferences.llmOllamaModelName = text.isEmpty ? "gemma4:e4b" : text
        refreshLLMControlsState()
    }

    @objc private func changeLLMGoogleThinkingLevel(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem else {
            return
        }
        Preferences.llmGoogleThinkingLevel =
            LLMGoogleThinkingLevel(rawValue: selectedItem.tag) ?? .off
        refreshLLMControlsState()
    }

    private func configureLLMControls() {
        if llmRankingEnabledButton != nil
            || llmTimeoutLabel != nil || llmTimeoutTextField != nil || llmTimeoutStepper != nil
            || llmPauseLabel != nil || llmPauseTextField != nil || llmPauseStepper != nil
            || llmInputtingTriggerModeLabel != nil || llmInputtingTriggerModePopUpButton != nil
            || llmActivityIndicatorButton != nil || llmDebugAlertButton != nil
            || llmProviderLabel != nil || llmProviderPopUpButton != nil
            || llmGoogleModelLabel != nil || llmGoogleModelTextField != nil
            || llmGoogleEndpointLabel != nil || llmGoogleEndpointTextField != nil
            || llmGoogleAPIKeyLabel != nil || llmGoogleAPIKeySecureTextField != nil
            || llmGoogleAPIKeyPlainTextField != nil || llmGoogleAPIKeyRevealButton != nil
            || llmGoogleThinkingLevelLabel != nil || llmGoogleThinkingLevelPopUpButton != nil
            || llmOllamaEndpointLabel != nil || llmOllamaEndpointTextField != nil
            || llmOllamaModelLabel != nil || llmOllamaModelTextField != nil
        {
            refreshLLMControlsState()
            return
        }

        var frame = advancedSettingsView.frame
        frame.size.height += kLLMControlExtraViewHeight
        advancedSettingsView.frame = frame

        let rankingButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        rankingButton.translatesAutoresizingMaskIntoConstraints = false
        rankingButton.title = NSLocalizedString("Use LLM Candidate Ranking", comment: "")
        rankingButton.target = self
        rankingButton.action = #selector(toggleLLMCandidateRankingEnabled(_:))

        let activityIndicatorButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        activityIndicatorButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorButton.title = NSLocalizedString("Show LLM Activity Indicator", comment: "")
        activityIndicatorButton.target = self
        activityIndicatorButton.action = #selector(toggleLLMActivityIndicator(_:))

        let debugAlertButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        debugAlertButton.translatesAutoresizingMaskIntoConstraints = false
        debugAlertButton.title = NSLocalizedString("Show LLM Debug Alert (Prompt/Response)", comment: "")
        debugAlertButton.target = self
        debugAlertButton.action = #selector(toggleLLMDebugAlert(_:))

        let timeoutLabel = NSTextField(labelWithString: "")
        timeoutLabel.translatesAutoresizingMaskIntoConstraints = false
        timeoutLabel.stringValue = NSLocalizedString("LLM Timeout (ms)", comment: "")

        let timeoutTextField = NSTextField(frame: .zero)
        timeoutTextField.translatesAutoresizingMaskIntoConstraints = false
        timeoutTextField.alignment = .right
        timeoutTextField.target = self
        timeoutTextField.action = #selector(changeLLMTimeoutTextField(_:))

        let timeoutStepper = NSStepper(frame: .zero)
        timeoutStepper.translatesAutoresizingMaskIntoConstraints = false
        timeoutStepper.target = self
        timeoutStepper.action = #selector(changeLLMTimeoutStepper(_:))
        timeoutStepper.minValue = 1
        timeoutStepper.maxValue = 5000
        timeoutStepper.increment = 1

        let pauseLabel = NSTextField(labelWithString: "")
        pauseLabel.translatesAutoresizingMaskIntoConstraints = false
        pauseLabel.stringValue = NSLocalizedString("LLM Pause Before Trigger (ms)", comment: "")

        let pauseTextField = NSTextField(frame: .zero)
        pauseTextField.translatesAutoresizingMaskIntoConstraints = false
        pauseTextField.alignment = .right
        pauseTextField.target = self
        pauseTextField.action = #selector(changeLLMPauseTextField(_:))

        let pauseStepper = NSStepper(frame: .zero)
        pauseStepper.translatesAutoresizingMaskIntoConstraints = false
        pauseStepper.target = self
        pauseStepper.action = #selector(changeLLMPauseStepper(_:))
        pauseStepper.minValue = 100
        pauseStepper.maxValue = 3000
        pauseStepper.increment = 50

        let triggerModeLabel = NSTextField(labelWithString: "")
        triggerModeLabel.translatesAutoresizingMaskIntoConstraints = false
        triggerModeLabel.stringValue = NSLocalizedString("LLM Trigger Mode", comment: "")

        let triggerModePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        triggerModePopUpButton.translatesAutoresizingMaskIntoConstraints = false
        triggerModePopUpButton.target = self
        triggerModePopUpButton.action = #selector(changeLLMInputtingTriggerMode(_:))
        triggerModePopUpButton.removeAllItems()
        triggerModePopUpButton.addItem(
            withTitle: NSLocalizedString("Continuous", comment: ""))
        triggerModePopUpButton.lastItem?.tag = LLMInputtingTriggerMode.continuous.rawValue
        triggerModePopUpButton.addItem(
            withTitle: NSLocalizedString("Segment End (Punctuation/Space)", comment: ""))
        triggerModePopUpButton.lastItem?.tag = LLMInputtingTriggerMode.segmentEnd.rawValue

        let googleModelLabel = NSTextField(labelWithString: "")
        googleModelLabel.translatesAutoresizingMaskIntoConstraints = false
        googleModelLabel.stringValue = NSLocalizedString("Cloud Model", comment: "")

        let googleModelTextField = NSTextField(frame: .zero)
        googleModelTextField.translatesAutoresizingMaskIntoConstraints = false
        googleModelTextField.target = self
        googleModelTextField.action = #selector(changeLLMGoogleModel(_:))

        let googleEndpointLabel = NSTextField(labelWithString: "")
        googleEndpointLabel.translatesAutoresizingMaskIntoConstraints = false
        googleEndpointLabel.stringValue = NSLocalizedString("Cloud Endpoint", comment: "")

        let googleEndpointTextField = NSTextField(frame: .zero)
        googleEndpointTextField.translatesAutoresizingMaskIntoConstraints = false
        googleEndpointTextField.target = self
        googleEndpointTextField.action = #selector(changeLLMGoogleEndpoint(_:))

        let googleAPIKeyLabel = NSTextField(labelWithString: "")
        googleAPIKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        googleAPIKeyLabel.stringValue = NSLocalizedString("Google API Key", comment: "")

        let googleAPIKeySecureTextField = NSSecureTextField(frame: .zero)
        googleAPIKeySecureTextField.translatesAutoresizingMaskIntoConstraints = false
        googleAPIKeySecureTextField.target = self
        googleAPIKeySecureTextField.action = #selector(changeLLMGoogleAPIKey(_:))

        let googleAPIKeyPlainTextField = NSTextField(frame: .zero)
        googleAPIKeyPlainTextField.translatesAutoresizingMaskIntoConstraints = false
        googleAPIKeyPlainTextField.target = self
        googleAPIKeyPlainTextField.action = #selector(changeLLMGoogleAPIKey(_:))

        let googleAPIKeyRevealButton = NSButton(title: "", target: nil, action: nil)
        googleAPIKeyRevealButton.translatesAutoresizingMaskIntoConstraints = false
        googleAPIKeyRevealButton.setButtonType(.momentaryPushIn)
        googleAPIKeyRevealButton.bezelStyle = .rounded
        googleAPIKeyRevealButton.target = self
        googleAPIKeyRevealButton.action = #selector(toggleLLMGoogleAPIKeyVisibility(_:))

        let googleThinkingLevelLabel = NSTextField(labelWithString: "")
        googleThinkingLevelLabel.translatesAutoresizingMaskIntoConstraints = false
        googleThinkingLevelLabel.stringValue = NSLocalizedString("Thinking Level", comment: "")

        let googleThinkingLevelPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        googleThinkingLevelPopUpButton.translatesAutoresizingMaskIntoConstraints = false
        googleThinkingLevelPopUpButton.target = self
        googleThinkingLevelPopUpButton.action = #selector(changeLLMGoogleThinkingLevel(_:))
        googleThinkingLevelPopUpButton.removeAllItems()
        googleThinkingLevelPopUpButton.addItem(withTitle: NSLocalizedString("Off", comment: ""))
        googleThinkingLevelPopUpButton.lastItem?.tag = LLMGoogleThinkingLevel.off.rawValue
        googleThinkingLevelPopUpButton.addItem(withTitle: NSLocalizedString("Low", comment: ""))
        googleThinkingLevelPopUpButton.lastItem?.tag = LLMGoogleThinkingLevel.low.rawValue
        googleThinkingLevelPopUpButton.addItem(withTitle: NSLocalizedString("Medium", comment: ""))
        googleThinkingLevelPopUpButton.lastItem?.tag = LLMGoogleThinkingLevel.medium.rawValue
        googleThinkingLevelPopUpButton.addItem(withTitle: NSLocalizedString("High", comment: ""))
        googleThinkingLevelPopUpButton.lastItem?.tag = LLMGoogleThinkingLevel.high.rawValue

        let providerLabel = NSTextField(labelWithString: "")
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        providerLabel.stringValue = NSLocalizedString("LLM Provider", comment: "")

        let providerPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        providerPopUpButton.translatesAutoresizingMaskIntoConstraints = false
        providerPopUpButton.target = self
        providerPopUpButton.action = #selector(changeLLMProvider(_:))
        providerPopUpButton.removeAllItems()
        providerPopUpButton.addItem(
            withTitle: NSLocalizedString("Google Cloud", comment: ""))
        providerPopUpButton.lastItem?.tag = LLMProvider.googleCloud.rawValue
        providerPopUpButton.addItem(
            withTitle: NSLocalizedString("Ollama (Local)", comment: ""))
        providerPopUpButton.lastItem?.tag = LLMProvider.ollama.rawValue

        let ollamaEndpointLabel = NSTextField(labelWithString: "")
        ollamaEndpointLabel.translatesAutoresizingMaskIntoConstraints = false
        ollamaEndpointLabel.stringValue = NSLocalizedString("Ollama Endpoint", comment: "")

        let ollamaEndpointTextField = NSTextField(frame: .zero)
        ollamaEndpointTextField.translatesAutoresizingMaskIntoConstraints = false
        ollamaEndpointTextField.target = self
        ollamaEndpointTextField.action = #selector(changeLLMOllamaEndpoint(_:))

        let ollamaModelLabel = NSTextField(labelWithString: "")
        ollamaModelLabel.translatesAutoresizingMaskIntoConstraints = false
        ollamaModelLabel.stringValue = NSLocalizedString("Ollama Model", comment: "")

        let ollamaModelTextField = NSTextField(frame: .zero)
        ollamaModelTextField.translatesAutoresizingMaskIntoConstraints = false
        ollamaModelTextField.target = self
        ollamaModelTextField.action = #selector(changeLLMOllamaModel(_:))

        advancedSettingsView.addSubview(rankingButton)
        advancedSettingsView.addSubview(activityIndicatorButton)
        advancedSettingsView.addSubview(debugAlertButton)
        advancedSettingsView.addSubview(timeoutLabel)
        advancedSettingsView.addSubview(timeoutTextField)
        advancedSettingsView.addSubview(timeoutStepper)
        advancedSettingsView.addSubview(pauseLabel)
        advancedSettingsView.addSubview(pauseTextField)
        advancedSettingsView.addSubview(pauseStepper)
        advancedSettingsView.addSubview(triggerModeLabel)
        advancedSettingsView.addSubview(triggerModePopUpButton)
        advancedSettingsView.addSubview(googleModelLabel)
        advancedSettingsView.addSubview(googleModelTextField)
        advancedSettingsView.addSubview(googleEndpointLabel)
        advancedSettingsView.addSubview(googleEndpointTextField)
        advancedSettingsView.addSubview(googleAPIKeyLabel)
        advancedSettingsView.addSubview(googleAPIKeySecureTextField)
        advancedSettingsView.addSubview(googleAPIKeyPlainTextField)
        advancedSettingsView.addSubview(googleAPIKeyRevealButton)
        advancedSettingsView.addSubview(googleThinkingLevelLabel)
        advancedSettingsView.addSubview(googleThinkingLevelPopUpButton)
        advancedSettingsView.addSubview(providerLabel)
        advancedSettingsView.addSubview(providerPopUpButton)
        advancedSettingsView.addSubview(ollamaEndpointLabel)
        advancedSettingsView.addSubview(ollamaEndpointTextField)
        advancedSettingsView.addSubview(ollamaModelLabel)
        advancedSettingsView.addSubview(ollamaModelTextField)

        NSLayoutConstraint.activate([
            rankingButton.leadingAnchor.constraint(
                equalTo: advancedSettingsView.leadingAnchor, constant: 20),
            rankingButton.bottomAnchor.constraint(
                equalTo: advancedSettingsView.bottomAnchor, constant: -kLLMControlBottomInset),
            rankingButton.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            debugAlertButton.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            debugAlertButton.bottomAnchor.constraint(
                equalTo: rankingButton.topAnchor, constant: -kLLMControlSpacing),
            debugAlertButton.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            activityIndicatorButton.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            activityIndicatorButton.bottomAnchor.constraint(
                equalTo: debugAlertButton.topAnchor, constant: -kLLMControlSpacing),
            activityIndicatorButton.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            timeoutLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            timeoutLabel.bottomAnchor.constraint(
                equalTo: activityIndicatorButton.topAnchor, constant: -kLLMControlSpacing),

            timeoutStepper.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),
            timeoutStepper.centerYAnchor.constraint(equalTo: timeoutLabel.centerYAnchor),

            timeoutTextField.widthAnchor.constraint(equalToConstant: 56),
            timeoutTextField.trailingAnchor.constraint(
                equalTo: timeoutStepper.leadingAnchor, constant: -8),
            timeoutTextField.centerYAnchor.constraint(equalTo: timeoutLabel.centerYAnchor),

            pauseLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            pauseLabel.bottomAnchor.constraint(
                equalTo: timeoutLabel.topAnchor, constant: -kLLMControlSpacing),

            pauseStepper.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),
            pauseStepper.centerYAnchor.constraint(equalTo: pauseLabel.centerYAnchor),

            pauseTextField.widthAnchor.constraint(equalToConstant: 56),
            pauseTextField.trailingAnchor.constraint(
                equalTo: pauseStepper.leadingAnchor, constant: -8),
            pauseTextField.centerYAnchor.constraint(equalTo: pauseLabel.centerYAnchor),

            triggerModeLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            triggerModeLabel.bottomAnchor.constraint(
                equalTo: pauseLabel.topAnchor, constant: -kLLMControlSpacing),

            triggerModePopUpButton.leadingAnchor.constraint(
                equalTo: triggerModeLabel.trailingAnchor, constant: 8),
            triggerModePopUpButton.centerYAnchor.constraint(equalTo: triggerModeLabel.centerYAnchor),
            triggerModePopUpButton.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            googleModelLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            googleModelLabel.bottomAnchor.constraint(
                equalTo: triggerModeLabel.topAnchor, constant: -kLLMControlSpacing),

            googleModelTextField.leadingAnchor.constraint(
                equalTo: googleModelLabel.trailingAnchor, constant: 8),
            googleModelTextField.centerYAnchor.constraint(equalTo: googleModelLabel.centerYAnchor),
            googleModelTextField.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            googleEndpointLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            googleEndpointLabel.bottomAnchor.constraint(
                equalTo: googleModelLabel.topAnchor, constant: -kLLMControlSpacing),

            googleEndpointTextField.leadingAnchor.constraint(
                equalTo: googleEndpointLabel.trailingAnchor, constant: 8),
            googleEndpointTextField.centerYAnchor.constraint(equalTo: googleEndpointLabel.centerYAnchor),
            googleEndpointTextField.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            googleAPIKeyLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            googleAPIKeyLabel.bottomAnchor.constraint(
                equalTo: googleEndpointLabel.topAnchor, constant: -kLLMControlSpacing),

            googleAPIKeyRevealButton.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),
            googleAPIKeyRevealButton.centerYAnchor.constraint(equalTo: googleAPIKeyLabel.centerYAnchor),
            googleAPIKeyRevealButton.widthAnchor.constraint(equalToConstant: 56),

            googleAPIKeySecureTextField.leadingAnchor.constraint(
                equalTo: googleAPIKeyLabel.trailingAnchor, constant: 8),
            googleAPIKeySecureTextField.centerYAnchor.constraint(equalTo: googleAPIKeyLabel.centerYAnchor),
            googleAPIKeySecureTextField.trailingAnchor.constraint(
                equalTo: googleAPIKeyRevealButton.leadingAnchor, constant: -8),

            googleAPIKeyPlainTextField.leadingAnchor.constraint(
                equalTo: googleAPIKeyLabel.trailingAnchor, constant: 8),
            googleAPIKeyPlainTextField.centerYAnchor.constraint(equalTo: googleAPIKeyLabel.centerYAnchor),
            googleAPIKeyPlainTextField.trailingAnchor.constraint(
                equalTo: googleAPIKeyRevealButton.leadingAnchor, constant: -8),

            googleThinkingLevelLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            googleThinkingLevelLabel.bottomAnchor.constraint(
                equalTo: googleAPIKeyLabel.topAnchor, constant: -kLLMControlSpacing),

            googleThinkingLevelPopUpButton.leadingAnchor.constraint(
                equalTo: googleThinkingLevelLabel.trailingAnchor, constant: 8),
            googleThinkingLevelPopUpButton.centerYAnchor.constraint(
                equalTo: googleThinkingLevelLabel.centerYAnchor),
            googleThinkingLevelPopUpButton.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            providerLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            providerLabel.bottomAnchor.constraint(
                equalTo: googleThinkingLevelLabel.topAnchor, constant: -kLLMControlSpacing),

            providerPopUpButton.leadingAnchor.constraint(
                equalTo: providerLabel.trailingAnchor, constant: 8),
            providerPopUpButton.centerYAnchor.constraint(equalTo: providerLabel.centerYAnchor),
            providerPopUpButton.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            ollamaModelLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            ollamaModelLabel.bottomAnchor.constraint(
                equalTo: providerLabel.topAnchor, constant: -kLLMControlSpacing),

            ollamaModelTextField.leadingAnchor.constraint(
                equalTo: ollamaModelLabel.trailingAnchor, constant: 8),
            ollamaModelTextField.centerYAnchor.constraint(equalTo: ollamaModelLabel.centerYAnchor),
            ollamaModelTextField.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),

            ollamaEndpointLabel.leadingAnchor.constraint(equalTo: rankingButton.leadingAnchor),
            ollamaEndpointLabel.bottomAnchor.constraint(
                equalTo: ollamaModelLabel.topAnchor, constant: -kLLMControlSpacing),

            ollamaEndpointTextField.leadingAnchor.constraint(
                equalTo: ollamaEndpointLabel.trailingAnchor, constant: 8),
            ollamaEndpointTextField.centerYAnchor.constraint(equalTo: ollamaEndpointLabel.centerYAnchor),
            ollamaEndpointTextField.trailingAnchor.constraint(
                lessThanOrEqualTo: advancedSettingsView.trailingAnchor, constant: -20),
        ])

        llmRankingEnabledButton = rankingButton
        llmActivityIndicatorButton = activityIndicatorButton
        llmDebugAlertButton = debugAlertButton
        llmTimeoutLabel = timeoutLabel
        llmTimeoutTextField = timeoutTextField
        llmTimeoutStepper = timeoutStepper
        llmPauseLabel = pauseLabel
        llmPauseTextField = pauseTextField
        llmPauseStepper = pauseStepper
        llmInputtingTriggerModeLabel = triggerModeLabel
        llmInputtingTriggerModePopUpButton = triggerModePopUpButton
        llmGoogleModelLabel = googleModelLabel
        llmGoogleModelTextField = googleModelTextField
        llmGoogleEndpointLabel = googleEndpointLabel
        llmGoogleEndpointTextField = googleEndpointTextField
        llmGoogleAPIKeyLabel = googleAPIKeyLabel
        llmGoogleAPIKeySecureTextField = googleAPIKeySecureTextField
        llmGoogleAPIKeyPlainTextField = googleAPIKeyPlainTextField
        llmGoogleAPIKeyRevealButton = googleAPIKeyRevealButton
        llmGoogleThinkingLevelLabel = googleThinkingLevelLabel
        llmGoogleThinkingLevelPopUpButton = googleThinkingLevelPopUpButton
        llmProviderLabel = providerLabel
        llmProviderPopUpButton = providerPopUpButton
        llmOllamaEndpointLabel = ollamaEndpointLabel
        llmOllamaEndpointTextField = ollamaEndpointTextField
        llmOllamaModelLabel = ollamaModelLabel
        llmOllamaModelTextField = ollamaModelTextField
        refreshLLMControlsState()
    }

    private func refreshLLMControlsState() {
        let isEnabled = Preferences.llmCandidateRankingEnabled
        llmRankingEnabledButton?.state = isEnabled ? .on : .off
        llmActivityIndicatorButton?.state = Preferences.llmShowActivityIndicator ? .on : .off
        llmDebugAlertButton?.state = Preferences.llmShowDebugAlert ? .on : .off
        llmActivityIndicatorButton?.isEnabled = isEnabled
        llmDebugAlertButton?.isEnabled = isEnabled
        llmTimeoutLabel?.isEnabled = isEnabled
        llmTimeoutTextField?.isEnabled = isEnabled
        llmTimeoutStepper?.isEnabled = isEnabled
        llmPauseLabel?.isEnabled = isEnabled
        llmPauseTextField?.isEnabled = isEnabled
        llmPauseStepper?.isEnabled = isEnabled
        llmInputtingTriggerModeLabel?.isEnabled = isEnabled
        llmInputtingTriggerModePopUpButton?.isEnabled = isEnabled
        llmInputtingTriggerModePopUpButton?.selectItem(
            withTag: Preferences.llmInputtingTriggerMode.rawValue)
        llmTimeoutTextField?.integerValue = Preferences.llmCandidateRankingTimeoutMs
        llmTimeoutStepper?.integerValue = Preferences.llmCandidateRankingTimeoutMs
        llmPauseTextField?.integerValue = Preferences.llmInputtingPauseMs
        llmPauseStepper?.integerValue = Preferences.llmInputtingPauseMs

        llmProviderLabel?.isEnabled = isEnabled
        llmProviderPopUpButton?.isEnabled = isEnabled
        llmProviderPopUpButton?.selectItem(withTag: Preferences.llmProvider.rawValue)

        let isGoogleCloud = Preferences.llmProvider == .googleCloud
        let googleEnabled = isEnabled && isGoogleCloud
        llmGoogleModelLabel?.isEnabled = googleEnabled
        llmGoogleModelTextField?.isEnabled = googleEnabled
        llmGoogleEndpointLabel?.isEnabled = googleEnabled
        llmGoogleEndpointTextField?.isEnabled = googleEnabled
        llmGoogleAPIKeyLabel?.isEnabled = googleEnabled
        llmGoogleAPIKeySecureTextField?.isEnabled = googleEnabled
        llmGoogleAPIKeyPlainTextField?.isEnabled = googleEnabled
        llmGoogleAPIKeyRevealButton?.isEnabled = googleEnabled
        llmGoogleThinkingLevelLabel?.isEnabled = googleEnabled
        llmGoogleThinkingLevelPopUpButton?.isEnabled = googleEnabled
        llmGoogleModelTextField?.stringValue = Preferences.llmGoogleModelName
        llmGoogleEndpointTextField?.stringValue = Preferences.llmGoogleEndpoint
        llmGoogleAPIKeySecureTextField?.stringValue = Preferences.llmGoogleAPIKey
        llmGoogleAPIKeyPlainTextField?.stringValue = Preferences.llmGoogleAPIKey
        llmGoogleAPIKeySecureTextField?.isHidden = llmGoogleAPIKeyRevealed
        llmGoogleAPIKeyPlainTextField?.isHidden = !llmGoogleAPIKeyRevealed
        llmGoogleAPIKeyRevealButton?.title =
            llmGoogleAPIKeyRevealed
            ? NSLocalizedString("Hide", comment: "")
            : NSLocalizedString("Show", comment: "")
        llmGoogleThinkingLevelPopUpButton?.selectItem(
            withTag: Preferences.llmGoogleThinkingLevel.rawValue)

        let isOllama = Preferences.llmProvider == .ollama
        let ollamaEnabled = isEnabled && isOllama
        llmOllamaEndpointLabel?.isEnabled = ollamaEnabled
        llmOllamaEndpointTextField?.isEnabled = ollamaEnabled
        llmOllamaModelLabel?.isEnabled = ollamaEnabled
        llmOllamaModelTextField?.isEnabled = ollamaEnabled
        llmOllamaEndpointTextField?.stringValue = Preferences.llmOllamaEndpoint
        llmOllamaModelTextField?.stringValue = Preferences.llmOllamaModelName
    }
}

extension PreferencesWindowController {
    func openSystemInfoReportAsync() async {
        var report = ""
        report += await InfoCollector.generate()
        report += Preferences.createReport()
        // Write report to a temporary file
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let randomName = "SystemInfoReport-\(UUID().uuidString).txt"
        let fileURL = tempDir.appendingPathComponent(randomName)
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
        } catch {
            NSLog("Failed to write report to temporary file: \(error)")
            return
        }
    }
}

extension PreferencesWindowController: NSToolbarDelegate {
    func use(view: NSView) {
        guard let window = window else {
            return
        }
        window.contentView?.subviews.first?.removeFromSuperview()
        let viewFrame = view.frame
        var windowRect = window.frame
        windowRect.size.height = kWindowTitleHeight + viewFrame.height
        windowRect.size.width = viewFrame.width
        windowRect.origin.y = window.frame.maxY - (viewFrame.height + kWindowTitleHeight)
        window.setFrame(windowRect, display: true, animate: true)
        window.contentView?.frame = view.bounds
        window.contentView?.addSubview(view)
    }

    @objc func showBasicView(_ sender: Any?) {
        use(view: basicSettingsView)
        window?.toolbar?.selectedItemIdentifier = .basic
        window?.title = NSLocalizedString("Basic", comment: "")
    }

    @objc func showUserPhrasesView(_ sender: Any?) {
        use(view: userPhrasesSettingsView)
        window?.toolbar?.selectedItemIdentifier = .userPhrases
        window?.title = NSLocalizedString("User Phrases", comment: "")
    }

    @objc func showAdvancedView(_ sender: Any?) {
        use(view: advancedSettingsView)
        window?.toolbar?.selectedItemIdentifier = .advanced
        window?.title = NSLocalizedString("Advanced", comment: "")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.basic, .userPhrases, .advanced]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.basic, .userPhrases, .advanced]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.basic, .userPhrases, .advanced]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self
        switch itemIdentifier {
        case .basic:
            let title = NSLocalizedString("Basic", comment: "")
            item.label = title
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: title)
            } else {
                item.image = NSImage(named: NSImage.preferencesGeneralName)
            }
            item.action = #selector(showBasicView(_:))
        case .userPhrases:
            let title = NSLocalizedString("User Phrases", comment: "")
            item.label = title
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: title)
            } else {
                item.image = NSImage(named: NSImage.folderName)
            }
            item.action = #selector(showUserPhrasesView(_:))
        case .advanced:
            let title = NSLocalizedString("Advanced", comment: "")
            item.label = title
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: title)
            } else {
                item.image = NSImage(named: NSImage.advancedName)
            }
            item.action = #selector(showAdvancedView(_:))
        default:
            return nil
        }
        return item
    }
}

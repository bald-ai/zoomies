import AppKit

/// Settings window with controls for max size, note prefix, and
/// global shortcut configuration.
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let settingsStore: SettingsStore
    private let hotKeyService: HotKeyService

    // UI elements we need to read/write after initialization.
    private let maxSizePopUp: NSPopUpButton
    private let frameRatePopUp: NSPopUpButton
    private let confirmBeforeClosingCheckbox: NSButton
    private let notePrefixCheckbox: NSButton
    private let notePrefixField: NSTextField
    private let notePrefixCountLabel: NSTextField
    private let filenameTemplateEditor: FilenameTemplateEditorView

    private let areaShortcutRecorder: ShortcutRecorderView
    private let fullShortcutRecorder: ShortcutRecorderView
    private let reopenShortcutRecorder: ShortcutRecorderView
    private let scratchpadShortcutRecorder: ShortcutRecorderView
    private let recordingShortcutRecorder: ShortcutRecorderView
    private let duplicateWarningLabel: NSTextField

    /// Fixed set of max-width options shown in the dropdown.
    private let maxWidthOptions: [Int] = [0, 800, 1200, 1600, 1920, 2400]

    /// Supported recording frame rates shown in the dropdown.
    private let frameRateOptions: [Int] = [30, 60]

    init(settingsStore: SettingsStore, hotKeyService: HotKeyService) {
        self.settingsStore = settingsStore
        self.hotKeyService = hotKeyService

        maxSizePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        frameRatePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        confirmBeforeClosingCheckbox = NSButton(
            checkboxWithTitle: "Confirm before deleting or closing",
            target: nil,
            action: nil
        )
        notePrefixCheckbox = NSButton(checkboxWithTitle: "Note prefix for screenshots", target: nil, action: nil)
        notePrefixField = NSTextField(string: "")
        notePrefixCountLabel = NSTextField(labelWithString: "0/50")
        filenameTemplateEditor = FilenameTemplateEditorView(settingsStore: settingsStore)

        areaShortcutRecorder = ShortcutRecorderView(frame: .zero)
        fullShortcutRecorder = ShortcutRecorderView(frame: .zero)
        reopenShortcutRecorder = ShortcutRecorderView(frame: .zero)
        scratchpadShortcutRecorder = ShortcutRecorderView(frame: .zero)
        recordingShortcutRecorder = ShortcutRecorderView(frame: .zero)
        duplicateWarningLabel = NSTextField(labelWithString: "")

        let contentRect = NSRect(x: 0, y: 0, width: 660, height: 700)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        let window = NSWindow(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        window.center()
        window.title = "Zoomies Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        AppTheme.apply(to: window)

        super.init(window: window)

        window.delegate = self
        configureContent()
        populateFromSettings()
    }
    
    /// Returns true while the user is actively recording a shortcut.
    /// Used to ignore global hotkeys during recording (prevents accidental triggers).
    var isRecordingAnyShortcut: Bool {
        areaShortcutRecorder.isRecordingShortcut
        || fullShortcutRecorder.isRecordingShortcut
        || reopenShortcutRecorder.isRecordingShortcut
        || scratchpadShortcutRecorder.isRecordingShortcut
        || recordingShortcutRecorder.isRecordingShortcut
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Configuration

    private func configureContent() {
        guard let contentView = window?.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        let surface = MenuSurfaceMaterial.makeFillingView(frame: contentView.bounds)
        contentView.addSubview(surface)

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(tabs)

        func page(_ title: String) -> NSStackView {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            let container = NSView()
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
            ])
            item.view = container
            tabs.addTabViewItem(item)
            return stack
        }

        func addRow(_ title: String, control: NSView, to stack: NSStackView) {
            let label = NSTextField(labelWithString: title)
            label.setContentHuggingPriority(.required, for: .horizontal)
            let row = NSStackView(views: [label, NSView(), control])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        func description(_ text: String, in stack: NSStackView) {
            let label = NSTextField(wrappingLabelWithString: text)
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let screenshots = page("Screenshots")
        let videos = page("Videos")
        let notes = page("Notes")

        configureMaxSizePopUp()
        addRow("Maximum image width", control: maxSizePopUp, to: screenshots)

        notePrefixCheckbox.target = self
        notePrefixCheckbox.action = #selector(notePrefixToggled(_:))
        screenshots.addArrangedSubview(notePrefixCheckbox)
        description("Adds this text before notes attached to screenshots.", in: screenshots)
        notePrefixField.delegate = self
        notePrefixField.target = self
        notePrefixField.action = #selector(notePrefixFieldEdited(_:))
        notePrefixCountLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        notePrefixCountLabel.textColor = .secondaryLabelColor
        notePrefixCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        let prefixControls = NSStackView(views: [notePrefixField, notePrefixCountLabel])
        prefixControls.spacing = 8
        prefixControls.widthAnchor.constraint(equalToConstant: 420).isActive = true
        addRow("Prefix text", control: prefixControls, to: screenshots)
        screenshots.addArrangedSubview(makeSeparator())
        screenshots.addArrangedSubview(filenameTemplateEditor)
        filenameTemplateEditor.widthAnchor.constraint(equalTo: screenshots.widthAnchor).isActive = true
        screenshots.addArrangedSubview(makeSeparator())

        let recorders = [areaShortcutRecorder, fullShortcutRecorder, reopenShortcutRecorder,
                         scratchpadShortcutRecorder, recordingShortcutRecorder]
        for recorder in recorders {
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 280).isActive = true
            recorder.setContentHuggingPriority(.required, for: .horizontal)
            recorder.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        scratchpadShortcutRecorder.setAccessibilityIdentifier("settings.shortcut.scratchpad")
        areaShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .area, newValue: $0) }
        fullShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .full, newValue: $0) }
        reopenShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .reopenFinderSelection, newValue: $0) }
        scratchpadShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .scratchpad, newValue: $0) }
        recordingShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .recording, newValue: $0) }
        addRow("Capture area", control: areaShortcutRecorder, to: screenshots)
        addRow("Capture full screen", control: fullShortcutRecorder, to: screenshots)
        addRow("Reopen Finder image", control: reopenShortcutRecorder, to: screenshots)

        configureFrameRatePopUp()
        addRow("Recording frame rate", control: frameRatePopUp, to: videos)
        addRow("Start / stop recording", control: recordingShortcutRecorder, to: videos)
        description("Videos use a generated Recording filename. You can rename each video after recording.", in: videos)

        addRow("Create note", control: scratchpadShortcutRecorder, to: notes)
        description("Standalone notes are saved as Markdown files. You can name each note when creating it.", in: notes)

        // This preference currently applies to both image and video workflows.
        confirmBeforeClosingCheckbox.title = "Confirm before deleting or closing screenshots and videos"
        confirmBeforeClosingCheckbox.target = self
        confirmBeforeClosingCheckbox.action = #selector(confirmBeforeClosingToggled(_:))
        confirmBeforeClosingCheckbox.toolTip = "Ask before deleting or closing in screenshot and video workflows."
        confirmBeforeClosingCheckbox.setAccessibilityIdentifier("settings.confirmBeforeClosing")
        confirmBeforeClosingCheckbox.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(confirmBeforeClosingCheckbox)
        duplicateWarningLabel.textColor = .systemRed
        duplicateWarningLabel.isHidden = true
        duplicateWarningLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(duplicateWarningLabel)

        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.topAnchor, constant: 12),
            tabs.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            tabs.bottomAnchor.constraint(equalTo: confirmBeforeClosingCheckbox.topAnchor, constant: -16),
            confirmBeforeClosingCheckbox.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            confirmBeforeClosingCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -24),
            confirmBeforeClosingCheckbox.bottomAnchor.constraint(equalTo: duplicateWarningLabel.topAnchor, constant: -8),
            duplicateWarningLabel.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            duplicateWarningLabel.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -24),
            duplicateWarningLabel.bottomAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func configureMaxSizePopUp() {
        maxSizePopUp.removeAllItems()

        for width in maxWidthOptions {
            let title: String
            if width == 0 {
                title = "Original (no resize)"
            } else {
                title = "\(width) px"
            }

            maxSizePopUp.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "")
            if let item = maxSizePopUp.lastItem {
                item.tag = width
            }
        }

        maxSizePopUp.target = self
        maxSizePopUp.action = #selector(maxSizeChanged(_:))
    }

    private func configureFrameRatePopUp() {
        frameRatePopUp.removeAllItems()

        for rate in frameRateOptions {
            frameRatePopUp.menu?.addItem(withTitle: "\(rate) FPS", action: nil, keyEquivalent: "")
            if let item = frameRatePopUp.lastItem {
                item.tag = rate
            }
        }

        frameRatePopUp.target = self
        frameRatePopUp.action = #selector(frameRateChanged(_:))
    }

    private func populateFromSettings() {
        let settings = settingsStore.settings

        // Max width
        let indexForCurrent = maxSizePopUp.indexOfItem(withTag: settings.maxWidth)
        if indexForCurrent != -1 {
            maxSizePopUp.selectItem(at: indexForCurrent)
        } else {
            let indexForOriginal = maxSizePopUp.indexOfItem(withTag: 0)
            if indexForOriginal != -1 {
                maxSizePopUp.selectItem(at: indexForOriginal)
            }
        }

        // Recording frame rate (unsupported values fall back to 30).
        let rate = (settings.recordingFrameRate == 60) ? 60 : 30
        let indexForRate = frameRatePopUp.indexOfItem(withTag: rate)
        if indexForRate != -1 {
            frameRatePopUp.selectItem(at: indexForRate)
        }

        // Note prefix
        confirmBeforeClosingCheckbox.state = settings.confirmBeforeClosing ? .on : .off
        notePrefixCheckbox.state = settings.notePrefixEnabled ? .on : .off
        notePrefixField.stringValue = settings.notePrefix
        notePrefixField.isEnabled = settings.notePrefixEnabled
        notePrefixCountLabel.isEnabled = settings.notePrefixEnabled
        updateNotePrefixCountLabel(for: settings.notePrefix)

        // Filename template
        filenameTemplateEditor.reloadFromSettings()

        // Shortcuts
        applyShortcutsToRecorders(from: settings.shortcuts)
    }

    private func applyShortcutsToRecorders(from shortcuts: Shortcuts) {
        areaShortcutRecorder.recordedShortcut = .init(from: shortcuts.screenshotArea)
        fullShortcutRecorder.recordedShortcut = .init(from: shortcuts.screenshotFull)
        reopenShortcutRecorder.recordedShortcut = .init(from: shortcuts.reopenFinderSelection)
        scratchpadShortcutRecorder.recordedShortcut = .init(from: shortcuts.openScratchpad)
        recordingShortcutRecorder.recordedShortcut = .init(from: shortcuts.toggleRecording)
    }

    // MARK: - Actions

    @objc private func maxSizeChanged(_ sender: NSPopUpButton) {
        let width = sender.selectedItem?.tag ?? 0
        settingsStore.update { settings in
            settings.maxWidth = width
        }
    }

    @objc private func frameRateChanged(_ sender: NSPopUpButton) {
        let rate = sender.selectedItem?.tag ?? 30
        settingsStore.update { settings in
            settings.recordingFrameRate = rate
        }
    }

    @objc private func confirmBeforeClosingToggled(_ sender: NSButton) {
        let isOn = sender.state == .on
        settingsStore.update { settings in
            settings.confirmBeforeClosing = isOn
        }
    }

    @objc private func notePrefixToggled(_ sender: NSButton) {
        let isOn = sender.state == .on
        notePrefixField.isEnabled = isOn
        notePrefixCountLabel.isEnabled = isOn
        settingsStore.update { settings in
            settings.notePrefixEnabled = isOn
        }
    }

    @objc private func notePrefixFieldEdited(_ sender: NSTextField) {
        var text = sender.stringValue
        if text.count > 50 {
            text = String(text.prefix(50))
            sender.stringValue = text
        }
        updateNotePrefixCountLabel(for: text)

        settingsStore.update { settings in
            settings.notePrefix = text
        }
    }

    private enum ShortcutKind {
        case area
        case full
        case reopenFinderSelection
        case scratchpad
        case recording
    }

    private func handleShortcutChange(kind: ShortcutKind, newValue: ShortcutRecorderView.RecordedShortcut) {
        duplicateWarningLabel.isHidden = true
        duplicateWarningLabel.stringValue = ""

        let newShortcut = Shortcut(keyCode: newValue.keyCode, modifierFlags: newValue.carbonFlags)
        var shortcuts = settingsStore.settings.shortcuts

        switch kind {
        case .area:
            shortcuts.screenshotArea = newShortcut
        case .full:
            shortcuts.screenshotFull = newShortcut
        case .reopenFinderSelection:
            shortcuts.reopenFinderSelection = newShortcut
        case .scratchpad:
            shortcuts.openScratchpad = newShortcut
        case .recording:
            shortcuts.toggleRecording = newShortcut
        }

        if hasDuplicate(shortcuts: shortcuts) {
            NSSound.beep()
            duplicateWarningLabel.isHidden = false
            duplicateWarningLabel.stringValue = "Shortcut already in use. Please choose a different combination."

            // Revert recorder to the previous value from persisted settings.
            let currentShortcuts = settingsStore.settings.shortcuts
            applyShortcutsToRecorders(from: currentShortcuts)
            return
        }

        settingsStore.update { settings in
            settings.shortcuts = shortcuts
            settings.shortcutsCustomized = true
        }

        // Re-apply in case normalization changed anything, then update hotkeys.
        applyShortcutsToRecorders(from: settingsStore.settings.shortcuts)
        hotKeyService.updateShortcuts(settings: settingsStore.settings)
    }

    private func hasDuplicate(shortcuts: Shortcuts) -> Bool {
        let values: [Shortcut] = [
            shortcuts.screenshotArea,
            shortcuts.screenshotFull,
            shortcuts.reopenFinderSelection,
            shortcuts.openScratchpad,
            shortcuts.toggleRecording
        ]
        let set = Set(values)
        return set.count < values.count
    }

    // MARK: - NSTextFieldDelegate

    private func updateNotePrefixCountLabel(for text: String) {
        let count = text.count
        notePrefixCountLabel.stringValue = "\(count)/50"
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === notePrefixField else { return }

        var text = field.stringValue
        if text.count > 50 {
            text = String(text.prefix(50))
            field.stringValue = text
        }
        updateNotePrefixCountLabel(for: text)

        settingsStore.update { settings in
            settings.notePrefix = text
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // When the settings window is closed, return the app to accessory mode
        // so it behaves like a menubar app again.
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }
}

private extension ShortcutRecorderView.RecordedShortcut {
    init(from shortcut: Shortcut) {
        self.init(keyCode: shortcut.keyCode, carbonFlags: shortcut.modifierFlags)
    }
}

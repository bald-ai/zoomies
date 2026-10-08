import AppKit
import Carbon

/// Zoomies has no main menu, so Settings handles its own keys: Command+W or
/// Escape closes, and text fields get the standard editing keys. A shortcut
/// recorder that is recording keeps every key for itself.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // A recorder that is recording takes any combo, Command+W included.
        if (firstResponder as? ShortcutRecorderView)?.isRecordingShortcut == true {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command], chars == "w" {
            performClose(nil)
            return true
        }
        if StandardEditingKeys.perform(event, in: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    // Reached only when nothing focused used the key.
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { performClose(nil) }
}

/// One scrolling page of grouped settings: shortcuts, capture, editor, colors.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsFieldEditor: NSTextView = {
        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.selectedTextAttributes = [
            .backgroundColor: NSColor(srgbRed: 0.26, green: 0.34, blue: 0.38, alpha: 1),
            .foregroundColor: NSColor.white
        ]
        return editor
    }()

    private let settingsStore: SettingsStore
    private let hotKeyService: HotKeyService

    // UI elements we need to read/write after initialization.
    private let maxSizePopUp: NSPopUpButton
    private let frameRatePopUp: NSPopUpButton
    private let confirmBeforeClosingCheckbox: NSButton

    private let areaShortcutRecorder: ShortcutRecorderView
    private let fullShortcutRecorder: ShortcutRecorderView
    private let reopenShortcutRecorder: ShortcutRecorderView
    private let scratchpadShortcutRecorder: ShortcutRecorderView
    private let recordingShortcutRecorder: ShortcutRecorderView
    private let duplicateWarningLabel: NSTextField

    /// Fixed set of max-width options shown in the dropdown.
    private let maxWidthOptions: [Int] = [0, 800, 1200, 1600, 1920, 2400]

    /// Supported recording frame rates shown in the dropdown.
    private let frameRateOptions: [Int] = [30, 60, 120]

    init(settingsStore: SettingsStore, hotKeyService: HotKeyService) {
        self.settingsStore = settingsStore
        self.hotKeyService = hotKeyService

        maxSizePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        frameRatePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        confirmBeforeClosingCheckbox = MutedSettingsCheckbox(checkboxWithTitle: "", target: nil, action: nil)

        areaShortcutRecorder = ShortcutRecorderView(frame: .zero)
        fullShortcutRecorder = ShortcutRecorderView(frame: .zero)
        reopenShortcutRecorder = ShortcutRecorderView(frame: .zero)
        scratchpadShortcutRecorder = ShortcutRecorderView(frame: .zero)
        recordingShortcutRecorder = ShortcutRecorderView(frame: .zero)
        duplicateWarningLabel = NSTextField(wrappingLabelWithString: "")

        let contentRect = NSRect(x: 0, y: 0, width: 600, height: 720)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        let window = SettingsWindow(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        window.title = "Zoomies Settings"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        AppTheme.apply(to: window)
        window.appearance = NSAppearance(named: .darkAqua)

        super.init(window: window)

        window.delegate = self
        configureContent()
        populateFromSettings()
        window.center()
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
        guard let window, let contentView = window.contentView else { return }
        contentView.subviews.forEach { $0.removeFromSuperview() }
        // Match the editor’s translucent material.
        let surface = MenuSurfaceMaterial.makeFillingView(frame: contentView.bounds)
        contentView.addSubview(surface)

        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 6
        page.edgeInsets = NSEdgeInsets(top: 8, left: 24, bottom: 24, right: 24)
        page.translatesAutoresizingMaskIntoConstraints = false

        func header(_ title: String) {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            if let previous = page.arrangedSubviews.last { page.setCustomSpacing(22, after: previous) }
            page.addArrangedSubview(label)
            label.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 26).isActive = true
            page.setCustomSpacing(8, after: label)
        }
        func add(_ view: NSView, inset: CGFloat = 0) {
            page.addArrangedSubview(view)
            view.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24 + inset).isActive = true
            view.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24 - inset).isActive = true
        }

        let recorders = [areaShortcutRecorder, fullShortcutRecorder, reopenShortcutRecorder,
                         scratchpadShortcutRecorder, recordingShortcutRecorder]
        for recorder in recorders {
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 200).isActive = true
            recorder.setContentHuggingPriority(.required, for: .horizontal)
            recorder.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        scratchpadShortcutRecorder.setAccessibilityIdentifier("settings.shortcut.scratchpad")
        areaShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .area, newValue: $0) }
        fullShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .full, newValue: $0) }
        reopenShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .reopenFinderSelection, newValue: $0) }
        scratchpadShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .scratchpad, newValue: $0) }
        recordingShortcutRecorder.onChange = { [weak self] in self?.handleShortcutChange(kind: .recording, newValue: $0) }

        header("Shortcuts")
        add(SettingsGroupView(rows: [
            SettingsGroupView.row("Capture area", control: areaShortcutRecorder),
            SettingsGroupView.row("Capture full screen", control: fullShortcutRecorder),
            SettingsGroupView.row("Start or stop recording", control: recordingShortcutRecorder),
            SettingsGroupView.row("New note", control: scratchpadShortcutRecorder),
            SettingsGroupView.row("Reopen image selected in Finder", control: reopenShortcutRecorder)
        ]))
        duplicateWarningLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        duplicateWarningLabel.textColor = .systemRed
        duplicateWarningLabel.isHidden = true
        add(duplicateWarningLabel, inset: 14)
        add(SettingsGroupView.footnote("To edit a saved screenshot or note again, select it in Finder and press the Reopen shortcut."), inset: 14)

        configureMaxSizePopUp()
        configureFrameRatePopUp()
        header("Capture")
        add(SettingsGroupView(rows: [
            SettingsGroupView.row("Maximum screenshot width", control: maxSizePopUp),
            SettingsGroupView.row("Recording frame rate", control: frameRatePopUp)
        ]))
        add(SettingsGroupView.footnote("Screenshots save to the Desktop as Screenshot_2024-01-30_14.23.45_1.png."), inset: 14)

        // This preference applies to both image and video workflows.
        confirmBeforeClosingCheckbox.target = self
        confirmBeforeClosingCheckbox.action = #selector(confirmBeforeClosingToggled(_:))
        confirmBeforeClosingCheckbox.setAccessibilityLabel("Confirm before deleting or closing")
        confirmBeforeClosingCheckbox.setAccessibilityIdentifier("settings.confirmBeforeClosing")
        header("Editor")
        add(SettingsGroupView(rows: [
            SettingsGroupView.row("Confirm before deleting or closing", control: confirmBeforeClosingCheckbox)
        ]))
        add(SettingsGroupView.footnote("Applies to screenshots and videos."), inset: 14)

        header("Colors")
        add(EditorPaletteSettingsView(settingsStore: settingsStore))


        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(page)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            page.topAnchor.constraint(equalTo: document.topAnchor),
            page.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])

        // Fit the window to the page, scrolling only on short screens.
        surface.layoutSubtreeIfNeeded()
        let titlebar = window.frame.height - window.contentLayoutRect.height
        let available = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        let height = min(page.fittingSize.height + titlebar, available)
        window.setContentSize(NSSize(width: 600, height: height))
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
        let rate = frameRateOptions.contains(settings.recordingFrameRate) ? settings.recordingFrameRate : 30
        let indexForRate = frameRatePopUp.indexOfItem(withTag: rate)
        if indexForRate != -1 {
            frameRatePopUp.selectItem(at: indexForRate)
        }

        confirmBeforeClosingCheckbox.state = settings.confirmBeforeClosing ? .on : .off

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

    // MARK: - NSWindowDelegate

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        settingsFieldEditor
    }

    func windowWillClose(_ notification: Notification) {
        // When the settings window is closed, return the app to accessory mode
        // so it behaves like a menubar app again.
        NSApp.setActivationPolicy(.accessory)
    }
}

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

private extension ShortcutRecorderView.RecordedShortcut {
    init(from shortcut: Shortcut) {
        self.init(keyCode: shortcut.keyCode, carbonFlags: shortcut.modifierFlags)
    }
}

/// Keep standard checkbox interaction and accessibility, with a subdued fill.
final class MutedSettingsCheckbox: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 1, y: (bounds.height - 15) / 2, width: 15, height: 15)
        let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        (state == .on ? NSColor(srgbRed: 0.26, green: 0.34, blue: 0.38, alpha: 1) : NSColor(white: 0.2, alpha: 0.7)).setFill()
        path.fill()
        NSColor(white: 0.6, alpha: isEnabled ? 0.7 : 0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
        if state == .on {
            let tick = NSBezierPath()
            // Express the checkmark from the top edge in either view orientation.
            func point(_ x: CGFloat, _ yFromTop: CGFloat) -> NSPoint {
                NSPoint(x: box.minX + x,
                        y: isFlipped ? box.minY + yFromTop : box.maxY - yFromTop)
            }
            tick.move(to: point(3, 7.5))
            tick.line(to: point(6, 11))
            tick.line(to: point(12, 4))
            tick.lineWidth = 1.8
            tick.lineCapStyle = .round
            NSColor(white: 0.9, alpha: isEnabled ? 1 : 0.4).setStroke()
            tick.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: 22, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

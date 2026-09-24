import AppKit

enum NotePanelAction {
    case save(text: String)
    case copyAndSave(text: String)
    case copyAndDelete(text: String)
    case delete
    case close
    case backToRename(text: String)
    case goToEditor(text: String)

    var completion: (action: ScreenshotFinalAction, note: String?)? {
        switch self {
        case .save(let text): return (.saveOnly, text)
        case .copyAndSave(let text): return (.copyAndSave, text)
        case .copyAndDelete(let text): return (.copyAndDelete, text)
        case .delete: return (.deleteOnly, nil)
        case .close: return (.closeOnly, nil)
        case .backToRename, .goToEditor: return nil
        }
    }
}

class NotePanelController: NSWindowController {
    var onAction: ((NotePanelAction) -> Void)?

    private let textView = LockedWhiteNoteTextView(frame: .zero, textContainer: nil)
    private let limitLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var escapeKeyDeletesFile: Bool = true
    private var showsCopyAndDelete: Bool = true
    private var showsEditorShortcut: Bool = true
    private var showsNewlineShortcut: Bool = false

    static let standaloneMaxLength = 100_000
    private var maxLength = 1000
    private var layout = ScreenshotNotePanelController.layout

    var text: String {
        get { String(textView.string.prefix(maxLength)) }
        set { textView.setFixedWhiteString(String(newValue.prefix(maxLength))) }
    }

    init(initialText: String,
                     escapeKeyDeletesFile: Bool = true,
                     showsCopyAndDelete: Bool = true,
                     showsEditorShortcut: Bool = true,
                     showsNewlineShortcut: Bool = false,
                     maxLength: Int = 1000,
                     layout: NotePanelLayout = ScreenshotNotePanelController.layout) {
        let contentRect = NSRect(origin: .zero, size: layout.size)
        let panel = FloatingInputPanel(contentRect: contentRect)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        super.init(window: panel)
        self.layout = layout
        self.maxLength = max(1, maxLength)
        textView.characterLimit = self.maxLength
        self.escapeKeyDeletesFile = escapeKeyDeletesFile
        self.showsCopyAndDelete = showsCopyAndDelete
        self.showsEditorShortcut = showsEditorShortcut
        self.showsNewlineShortcut = showsNewlineShortcut
        configureUI(initialText: initialText)
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func handleKeyCommand(_ command: KeyCommand) {
        let value = String(textView.string.prefix(maxLength))
        let actions: [KeyCommand: NotePanelAction?] = [
            .enter: .save(text: value),
            .commandEnter: .copyAndSave(text: value),
            .commandShiftEnter: .copyAndSave(text: value),
            .commandBackspace: showsCopyAndDelete ? .copyAndDelete(text: value) : nil,
            .escape: escapeKeyDeletesFile ? .delete : .close,
            .tab: showsEditorShortcut ? .goToEditor(text: value) : nil,
            .shiftTab: .backToRename(text: value)
        ]
        if let action = actions[command] ?? nil { onAction?(action) }
    }

    private func configureUI(initialText: String) {
        guard let contentView = window?.contentView else { return }

        let container = MenuSurfaceMaterial.makeFillingView(frame: contentView.bounds)
        contentView.addSubview(container)

        let titleLabel = NSTextField(labelWithString: "Note")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        limitLabel.font = NSFont.systemFont(ofSize: 10)
        limitLabel.textColor = .secondaryLabelColor
        limitLabel.stringValue = "\(maxLength.formatted())-character limit"
        limitLabel.isHidden = true
        textView.onLimitReached = { [weak self] in
            guard let self else { return }
            self.limitLabel.stringValue = "\(self.maxLength.formatted())-character limit"
            self.limitLabel.isHidden = false
        }
        textView.onEdited = { [weak self] in
            guard let self else { return }
            self.limitLabel.isHidden = self.textView.string.count < self.maxLength
        }

        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.configureFixedWhiteText()
        textView.setFixedWhiteString(String(initialText.prefix(maxLength)))

        textView.keyCommandHandler = { [weak self] command in self?.handleKeyCommand(command) }

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = layout.hasVerticalScroller
        scrollView.autohidesScrollers = layout.autohidesScrollers
        if let scrollerStyle = layout.scrollerStyle {
            scrollView.scrollerStyle = scrollerStyle
        }
        scrollView.documentView = textView

        [titleLabel, limitLabel, scrollView, shortcutLabel].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        shortcutLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutLabel.textColor = NSColor.secondaryLabelColor
        shortcutLabel.lineBreakMode = .byWordWrapping
        let escapeLabel = escapeKeyDeletesFile ? "Delete" : "Close"
        var shortcutParts = ["Enter: Save"]
        if showsNewlineShortcut {
            shortcutParts.append("Shift+↩: new line")
        }
        shortcutParts.append("⌘↩: Copy+Save")
        if showsCopyAndDelete {
            shortcutParts.append("⌘⌫: Copy+Delete")
        }
        shortcutParts.append("Esc: \(escapeLabel)")
        shortcutParts.append("Shift+Tab: Rename")
        if showsEditorShortcut {
            shortcutParts.append("Tab: Editor")
        }
        shortcutLabel.stringValue = shortcutParts.joined(separator: "    ")

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            limitLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            limitLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: layout.minimumTextHeight),

            shortcutLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            shortcutLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            shortcutLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            layout.fillsAvailableHeight
                ? shortcutLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
                : shortcutLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12)
        ])

        window?.initialFirstResponder = textView
    }

    func show() {
        guard let window = window else { return }
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(textView)
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }
}

private final class LockedWhiteNoteTextView: NSTextView {
    var characterLimit = 1000
    var onLimitReached: (() -> Void)?
    var onEdited: (() -> Void)?

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let current = string as NSString
        if let replacementString,
           affectedCharRange.location <= current.length,
           affectedCharRange.length <= current.length - affectedCharRange.location {
            let updated = current.replacingCharacters(in: affectedCharRange, with: replacementString)
            guard updated.count <= characterLimit else {
                onLimitReached?()
                return false
            }
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    var keyCommandHandler: ((KeyCommand) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        if let container {
            super.init(frame: frameRect, textContainer: container)
        } else {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(size: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            super.init(frame: frameRect, textContainer: textContainer)
        }

        isEditable = true
        isSelectable = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        textContainerInset = NSSize(width: 4, height: 4)
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(width: frameRect.width, height: .greatestFiniteMagnitude)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionDidChange),
            name: NSTextView.didChangeSelectionNotification,
            object: self
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configureFixedWhiteText() {
        textColor = .white
        insertionPointColor = .white
        enforceTypingColor()
    }

    func setFixedWhiteString(_ value: String) {
        string = value
        textColor = .white
        enforceTypingColor()
    }

    override func keyDown(with event: NSEvent) {
        if let command = interpretNoteKeyCommand(from: event) {
            keyCommandHandler?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        enforceTypingColor()
        onEdited?()
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        enforceTypingColor()
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        enforceTypingColor()
        return becameFirstResponder
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enforceTypingColor()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        enforceTypingColor()
        let plainText = (insertString as? NSAttributedString)?.string ?? insertString
        super.insertText(plainText, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any?) {
        enforceTypingColor()
        super.pasteAsPlainText(sender)
    }

    private func enforceTypingColor() {
        var attributes = typingAttributes
        if let font {
            attributes[.font] = font
        }
        attributes[.foregroundColor] = NSColor.white
        typingAttributes = attributes
    }

    @objc private func handleSelectionDidChange() {
        enforceTypingColor()
    }
}

func interpretNoteKeyCommand(from event: NSEvent) -> KeyCommand? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    switch event.keyCode {
    case 36, 76:
        // Shift+Enter falls through to super.keyDown so the text view inserts
        // a newline; plain Enter still saves. Mirrors EditorInlineTextView.
        return noteEnterCommand(flags: flags)
    case 51:
        return flags.contains(.command) ? .commandBackspace : nil
    case 53:
        return .escape
    case 48:
        return flags.contains(.shift) ? .shiftTab : .tab
    default:
        return nil
    }
}

private func noteEnterCommand(flags: NSEvent.ModifierFlags) -> KeyCommand? {
    if flags.contains(.command) { return .commandEnter }
    return flags.contains(.shift) ? nil : .enter
}

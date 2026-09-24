import AppKit

final class FloatingInputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private let sendEditingAction: (Selector, Any?) -> Bool

    init(contentRect: NSRect,
         sendEditingAction: @escaping (Selector, Any?) -> Bool = { NSApp.sendAction($0, to: nil, from: $1) }) {
        self.sendEditingAction = sendEditingAction
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        // The workflow is keyboard-first, but clicking anywhere on a panel must
        // restore key focus after the user switches to another window.
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = NSColor.clear
        hasShadow = true
        isReleasedWhenClosed = false
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.cornerCurve = .continuous
        contentView?.layer?.masksToBounds = true
        AppTheme.apply(to: self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased()

        if performTextUndo(chars: chars, flags: flags) { return true }
        if flags == [.command], let chars,
           let selector = Self.editingSelectors[chars], sendEditingAction(selector, self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // NSText has no undo: action; its first-responder undo manager owns edits.
    private func performTextUndo(chars: String?, flags: NSEvent.ModifierFlags) -> Bool {
        guard chars == "z", let textView = firstResponder as? NSTextView else { return false }
        if flags == [.command] { textView.undoManager?.undo(); return true }
        if flags == [.command, .shift] { textView.undoManager?.redo(); return true }
        return false
    }

    private static let editingSelectors: [String: Selector] = [
        "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "x": #selector(NSText.cut(_:)), "a": #selector(NSText.selectAll(_:))
    ]
}

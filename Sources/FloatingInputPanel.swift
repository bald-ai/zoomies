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
        if StandardEditingKeys.perform(event, in: self, send: sendEditingAction) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Zoomies has no main menu, so windows with text fields route the standard
/// Edit-menu keys themselves: copy, paste, cut, select all, undo and redo.
enum StandardEditingKeys {
    private static let selectors: [String: Selector] = [
        "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "x": #selector(NSText.cut(_:)), "a": #selector(NSText.selectAll(_:))
    ]

    static func perform(_ event: NSEvent, in window: NSWindow,
                        send: (Selector, Any?) -> Bool = { NSApp.sendAction($0, to: nil, from: $1) }) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let chars = event.charactersIgnoringModifiers?.lowercased()
        // NSText has no undo: action; its first-responder undo manager owns edits.
        if chars == "z", let textView = window.firstResponder as? NSTextView {
            if flags == [.command] { textView.undoManager?.undo(); return true }
            if flags == [.command, .shift] { textView.undoManager?.redo(); return true }
        }
        guard flags == [.command], let chars, let selector = selectors[chars] else { return false }
        return send(selector, window)
    }
}

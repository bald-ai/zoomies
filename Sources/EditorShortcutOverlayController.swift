import AppKit

/// A cancelled hold cannot rearm until Command is fully released.
struct EditorShortcutHoldState {
    static let delay: TimeInterval = 0.5
    private(set) var deadline: TimeInterval?
    private(set) var isVisible = false
    private var commandDown = false
    private var blocked = false

    mutating func modifiersChanged(_ flags: NSEvent.ModifierFlags, now: TimeInterval) {
        let command = flags.contains(.command)
        let other = !flags.intersection([.shift, .control, .option, .function]).isEmpty
        if !command {
            commandDown = false
            blocked = false
            deadline = nil
            isVisible = false
            return
        }
        let freshPress = !commandDown
        commandDown = true
        if other {
            cancel()
        } else if freshPress && !blocked {
            deadline = now + Self.delay
        }
    }

    mutating func focusGained(flags: NSEvent.ModifierFlags, now: TimeInterval) {
        self = EditorShortcutHoldState()
        if flags.contains(.command) {
            modifiersChanged(flags, now: now)
            cancel()
        }
    }

    mutating func keyPressed() {
        if commandDown { cancel() }
    }

    mutating func cancel() {
        blocked = commandDown
        deadline = nil
        isVisible = false
    }

    mutating func advance(to now: TimeInterval) {
        guard let deadline, now >= deadline, commandDown, !blocked else { return }
        self.deadline = nil
        isVisible = true
    }
}

/// A help view inside the editor; never takes key-window or first-responder status.
final class EditorShortcutOverlayController {
    private weak var window: NSWindow?
    private let hints: () -> [EditorShortcutHint]
    private var state = EditorShortcutHoldState()
    private var timer: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private(set) var overlayView: NSView?

    init(window: NSWindow, hints: @escaping () -> [EditorShortcutHint]) {
        self.window = window
        self.hints = hints
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.cancel()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.state.focusGained(flags: NSEvent.modifierFlags, now: ProcessInfo.processInfo.systemUptime)
            self?.update()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancel()
        })
    }

    deinit {
        timer?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        overlayView?.removeFromSuperview()
    }

    /// Called by the editor's existing local monitor BEFORE its shortcut routing.
    func handle(_ event: NSEvent) {
        guard window?.isKeyWindow == true, window?.isVisible == true else {
            cancel()
            return
        }
        if event.type == .keyDown {
            state.keyPressed()
        } else if event.type == .flagsChanged {
            state.modifiersChanged(event.modifierFlags, now: ProcessInfo.processInfo.systemUptime)
        } else {
            return
        }
        update()
    }

    func cancel() {
        state.cancel()
        update()
    }

    private func update() {
        timer?.cancel()
        timer = nil
        if state.isVisible {
            show()
        } else {
            overlayView?.removeFromSuperview()
            overlayView = nil
        }
        guard let deadline = state.deadline else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.window?.isKeyWindow == true, self.window?.isVisible == true else { return }
            self.state.advance(to: ProcessInfo.processInfo.systemUptime)
            self.update()
        }
        timer = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: task)
    }

    func refreshLabels() {
        guard overlayView != nil else { return }
        overlayView?.removeFromSuperview()
        overlayView = nil
        show()
    }

    private func show() {
        guard overlayView == nil, let host = window?.contentView else { return }
        let layer = makeView(in: host)
        host.addSubview(layer, positioned: .above, relativeTo: nil)
        overlayView = layer
    }

    func makeView(in host: NSView) -> NSView {
        let layer = EditorShortcutHintLayer(frame: host.bounds)
        layer.autoresizingMask = [.width, .height]
        let visibleHints = hints().filter { !$0.view.isHiddenOrHasHiddenAncestor && $0.view.window === host.window }
        let anchors = visibleHints.map { $0.view.convert($0.view.bounds, to: host) }
        // Every toolbar control shares the same badge baseline, regardless of
        // its own intrinsic height (swatch, text label, icon or save button).
        let baseline = (anchors.map(\.minY).min() ?? 20) - 14
        var hoverTargets: [(NSRect, EditorShortcutHint)] = []
        for (hint, anchor) in zip(visibleHints, anchors) where host.bounds.intersects(anchor) {
            let badge = EditorShortcutBadge(key: hint.key)
            badge.frame.origin = NSPoint(x: anchor.midX - badge.frame.width / 2, y: baseline)
            badge.setAccessibilityLabel(hint.label + ": " + hint.key)
            layer.addSubview(badge)
            hoverTargets.append((anchor.union(badge.frame), hint))
        }
        layer.configure(hoverTargets: hoverTargets,
                        toolbarTop: anchors.map(\.maxY).max() ?? baseline + 30)
        return layer
    }
}

struct EditorShortcutHint {
    let view: NSView
    let key: String
    let label: String
}

/// Tracking areas provide hover help without intercepting toolbar clicks.
private final class EditorShortcutHintLayer: NSView {
    private var hoverTargets: [(NSRect, EditorShortcutHint)] = []
    private let help = NSTextField(wrappingLabelWithString: "")
    private let panel = NSView()

    func configure(hoverTargets: [(NSRect, EditorShortcutHint)], toolbarTop: CGFloat) {
        self.hoverTargets = hoverTargets
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 0.97).cgColor
        panel.layer?.cornerRadius = 7
        panel.frame = NSRect(x: max(8, (bounds.width - 560) / 2),
                             y: min(toolbarTop + 12, bounds.height - 36),
                             width: min(560, bounds.width - 16), height: 28)
        help.font = .systemFont(ofSize: 13, weight: .medium)
        help.textColor = .white
        help.alignment = .center
        help.frame = panel.bounds.insetBy(dx: 12, dy: 5)
        panel.addSubview(help)
        addSubview(panel)
        showHelp(for: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        for (index, target) in hoverTargets.enumerated() {
            addTrackingArea(NSTrackingArea(rect: target.0,
                                          options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                          owner: self, userInfo: ["index": index]))
        }
        // Also reveal help if Command was held with the pointer already on a control.
        if let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            showHelp(for: hoverTargets.first { $0.0.contains(point) }?.1)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let index = event.trackingArea?.userInfo?["index"] as? Int,
              hoverTargets.indices.contains(index) else { return }
        showHelp(for: hoverTargets[index].1)
    }

    override func mouseExited(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        showHelp(for: hoverTargets.first { $0.0.contains(point) }?.1)
    }

    private func showHelp(for hint: EditorShortcutHint?) {
        if let hint {
            help.stringValue = "\(Self.spelledOut(hint.label)): \(Self.spelledOut(hint.key))"
        } else {
            help.stringValue = "Hover over a shortcut to see it spelled out."
        }
    }

    private static func spelledOut(_ text: String) -> String {
        text.replacingOccurrences(of: "⌘", with: "Command + ")
            .replacingOccurrences(of: "⇧", with: "Shift + ")
            .replacingOccurrences(of: "⌥", with: "Option + ")
            .replacingOccurrences(of: "⌫", with: "Delete")
            .replacingOccurrences(of: "↩", with: "Return")
            .replacingOccurrences(of: "−", with: "Minus")
            .replacingOccurrences(of: "Esc", with: "Escape")
            .replacingOccurrences(of: " + +", with: " + Plus")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class EditorShortcutBadge: NSView {
    init(key: String) {
        let label = NSTextField(labelWithString: key)
        label.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: 26, height: 16)
        if label.frame.width > 22 {
            label.font = .monospacedSystemFont(ofSize: 9 * 22 / label.frame.width, weight: .medium)
            label.sizeToFit()
        }
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 0.97).cgColor
        layer?.cornerRadius = 4
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 0.8).cgColor
        label.frame.origin = NSPoint(x: (size.width - label.frame.width) / 2,
                                     y: (size.height - label.frame.height) / 2)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

import AppKit

/// Manages the NSStatusItem (menubar icon and menu).
final class TrayService {
    private let statusItem: NSStatusItem
    private let onShowSettings: () -> Void

    init(onShowSettings: @escaping () -> Void) {
        self.onShowSettings = onShowSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        restoreStatusImage()
        // AppKit anchors the menu to its status item, including across displays.
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        AppTheme.apply(to: menu)

        menu.addItem(NSMenuItem(title: "Settings", action: #selector(didSelectSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(didSelectQuit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        menu.items.forEach { item in
            item.target = self
        }

        return menu
    }

    /// Red recording dot and elapsed time on the status button.
    func updateRecording(state: ScreenRecordingService.State, elapsed: TimeInterval) {
        guard let button = statusItem.button else { return }
        switch state {
        case .idle:
            button.attributedTitle = NSAttributedString(string: "")
            button.contentTintColor = nil
            restoreStatusImage()
        case .starting:
            setRecordingTitle("●")
        case .recording:
            setRecordingTitle("● \(Self.formatElapsed(elapsed))")
        case .stopping:
            setRecordingTitle("●")
        }
    }

    private func setRecordingTitle(_ title: String) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        ])
    }

    private static func formatElapsed(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func restoreStatusImage() {
        guard let button = statusItem.button else { return }
        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "Zoomies")
        }
    }

    @objc private func didSelectSettings() {
        onShowSettings()
    }

    @objc private func didSelectQuit() {
        NSApp.terminate(nil)
    }
}

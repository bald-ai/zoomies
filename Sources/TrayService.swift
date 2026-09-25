import AppKit

/// Manages the NSStatusItem (menubar icon and menu).
final class TrayService {
    private let statusItem: NSStatusItem?
    private let button: NSButton?
    private let onQuit: () -> Void
    private(set) var menu: NSMenu!
    private let onShowSettings: () -> Void

    convenience init(onShowSettings: @escaping () -> Void) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.init(statusItem: statusItem, button: statusItem.button, onShowSettings: onShowSettings)
    }

    init(statusItem: NSStatusItem? = nil, button: NSButton?, onShowSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void = { NSApp.terminate(nil) }) {
        self.onShowSettings = onShowSettings
        self.onQuit = onQuit
        self.statusItem = statusItem
        self.button = button
        restoreStatusImage()
        menu = makeMenu()
        statusItem?.menu = menu
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

    /// Compact elapsed seconds, capped at the recording limit.
    @MainActor
    func updateRecording(state: ScreenRecordingService.State, elapsed: TimeInterval) {
        guard let button else { return }
        switch state {
        case .idle:
            button.attributedTitle = NSAttributedString(string: "")
            button.contentTintColor = nil
            restoreStatusImage()
        case .starting:
            setRecordingTitle("0")
        case .recording, .stopping:
            let limit = Int(ScreenRecordingService.maxDuration)
            let seconds = min(limit, max(0, Int(elapsed)))
            setRecordingTitle(String(seconds))
        }
    }

    private func setRecordingTitle(_ title: String) {
        guard let button else { return }
        button.image = nil
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        ])
    }

    private func restoreStatusImage() {
        guard let button else { return }
        button.image = NSImage(systemSymbolName: "camera", accessibilityDescription: "Zoomies")
    }

    @objc private func didSelectSettings() {
        onShowSettings()
    }

    @objc private func didSelectQuit() {
        onQuit()
    }
}

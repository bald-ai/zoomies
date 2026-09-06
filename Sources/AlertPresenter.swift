import AppKit

enum AlertPresenter {
    /// Seams so tests can verify activation without showing a modal.
    static var appActivator: () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    static var modalRunner: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }

    /// Keep floating workflow panels below the modal while it is running.
    /// Setting only the alert's level before runModal is not sufficient: modal
    /// presentation manages the alert's level itself.
    static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previousKeyWindow = NSApp.keyWindow
        let elevatedWindows = NSApp.windows
            .filter { $0.isVisible && $0 !== alert.window && $0.level.rawValue > NSWindow.Level.normal.rawValue }
            .map { (window: $0, level: $0.level) }
        for entry in elevatedWindows {
            entry.window.level = .normal
        }
        defer {
            for entry in elevatedWindows {
                entry.window.level = entry.level
            }
            if let previousKeyWindow, previousKeyWindow.isVisible {
                previousKeyWindow.makeKeyAndOrderFront(nil)
            }
        }
        appActivator()
        alert.window.level = .modalPanel
        alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        return modalRunner(alert)
    }

    static func presentWarning(title: String, message: String) {
        let showAlert = {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            _ = runModal(alert)
        }

        if Thread.isMainThread {
            showAlert()
        } else {
            DispatchQueue.main.async(execute: showAlert)
        }
    }

    static func presentWarningWithSettingsButton(title: String, message: String,
                                                  settingsURL: String = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        let showAlert = {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            let response = runModal(alert)
            if response == .alertFirstButtonReturn {
                if let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        if Thread.isMainThread {
            showAlert()
        } else {
            DispatchQueue.main.async(execute: showAlert)
        }
    }
}

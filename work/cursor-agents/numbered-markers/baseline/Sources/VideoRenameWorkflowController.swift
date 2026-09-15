import AppKit

/// Post-recording rename flow for a saved video file.
///
/// Reuses `RenamePanelController` with note navigation disabled: no note
/// panel and no image editor. One instance exists per recording and is owned
/// by `AppDelegate`, which keeps it retained until the flow finishes.
final class VideoRenameWorkflowController {
    typealias ErrorPresenter = (_ title: String, _ message: String) -> Void
    typealias DeleteConfirmer = () -> Bool

    private var fileURL: URL
    private let settingsStore: SettingsStore
    private let clipboardService: ClipboardService
    private let errorPresenter: ErrorPresenter
    private let deleteConfirmer: DeleteConfirmer

    private var renameController: RenamePanelController?
    private var hasFinished = false
    private var publishedCopyAndDeleteURL: URL?

    /// Optional callback invoked once the flow has fully completed.
    var onFinish: (() -> Void)?

    /// True from `start()` until the flow finishes. AppDelegate gates new
    /// recordings, screenshots, scratchpad, and Finder-reopen work on this.
    var isBusyForUserCommands: Bool { !hasFinished }

    init(fileURL: URL,
         settingsStore: SettingsStore,
         clipboardService: ClipboardService,
         errorPresenter: @escaping ErrorPresenter = { title, message in
             AlertPresenter.presentWarning(title: title, message: message)
         },
         deleteConfirmer: DeleteConfirmer? = nil) {
        self.fileURL = fileURL
        self.settingsStore = settingsStore
        self.clipboardService = clipboardService
        self.errorPresenter = errorPresenter
        let store = settingsStore
        self.deleteConfirmer = deleteConfirmer ?? {
            VideoRenameWorkflowController.defaultDeleteConfirmation(
                confirmBeforeClosing: store.settings.confirmBeforeClosing
            )
        }
    }

    func start() {
        if Thread.isMainThread {
            presentRenamePanel()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.presentRenamePanel()
            }
        }
    }

    // MARK: - Panels

    private func presentRenamePanel() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.presentRenamePanel()
            }
            return
        }
        let controller = RenamePanelController(
            initialFilename: fileURL.lastPathComponent,
            allowsNoteNavigation: false
        )
        controller.onAction = { [weak self] action in
            self?.handleRenameAction(action)
        }
        renameController = controller
        centerOnScreenUnderMouse(controller.window)
        // Same as the image flow: avoid activating the app or switching Spaces.
        controller.show()
    }

    private func centerOnScreenUnderMouse(_ window: NSWindow?) {
        guard let window else { return }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            let frame = screen.visibleFrame
            let size = window.frame.size
            let origin = NSPoint(x: frame.midX - size.width / 2,
                                 y: frame.midY - size.height / 2)
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
    }

    // MARK: - Rename handling

    func handleRenameAction(_ action: RenamePanelAction) {
        guard !hasFinished else { return }

        switch action {
        case .save(let newName):
            guard applyRenameIfNeeded(newName: newName) else { return }
            closeAndFinish()

        case .copyAndSave(let newName):
            guard applyRenameIfNeeded(newName: newName) else { return }
            // The save already stands; warn and stay open so the user can retry.
            guard clipboardService.copyFile(at: fileURL, useCache: false) != nil else {
                presentError(
                    title: "Copy failed",
                    message: "Zoomies couldn't copy the recording to the clipboard, but your save was kept. You can try Copy + Save again."
                )
                return
            }
            closeAndFinish()

        case .copyAndDelete(let newName):
            guard applyRenameIfNeeded(newName: newName) else { return }
            if let published = publishedCopyAndDeleteURL,
               FileManager.default.fileExists(atPath: published.path) {
                guard deleteRecording() else { return }
                closeAndFinish()
                return
            }
            // Confirm the cached copy and clipboard operation succeeded
            // before deleting the original.
            guard let published = clipboardService.copyFile(at: fileURL, useCache: true) else {
                presentError(
                    title: "Copy failed",
                    message: "Zoomies couldn’t copy the recording to the clipboard, so the original file was left in place. You can try Copy + Delete again."
                )
                return
            }
            publishedCopyAndDeleteURL = published
            guard deleteRecording() else { return }
            closeAndFinish()

        case .delete:
            guard deleteConfirmer() else { return }
            guard deleteRecording() else { return }
            closeAndFinish()

        case .close:
            closeAndFinish()

        case .goToNote:
            // Note navigation is disabled for video; ignore defensively.
            break
        }
    }

    private func applyRenameIfNeeded(newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        let sanitizedFullName = WorkflowFilenameLogic.sanitizeFilename(trimmed, preservingExtensionOf: fileURL)
        if sanitizedFullName == fileURL.lastPathComponent {
            return true
        }

        let directory = fileURL.deletingLastPathComponent()
        let requestedURL = directory.appendingPathComponent(sanitizedFullName)
        let targetURL = urlsReferToSameFile(fileURL, requestedURL)
            ? requestedURL
            : WorkflowFilenameLogic.uniqueURL(forProposedName: sanitizedFullName, in: directory) { path in
                FileManager.default.fileExists(atPath: path)
            }

        do {
            try FileManager.default.moveItem(at: fileURL, to: targetURL)
            fileURL = targetURL
            return true
        } catch {
            presentError(title: "Rename failed", message: error.localizedDescription)
            return false
        }
    }

    private func urlsReferToSameFile(_ first: URL, _ second: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: second.path),
              let firstIdentifier = fileIdentifier(for: first),
              let secondIdentifier = fileIdentifier(for: second) else {
            return false
        }
        return firstIdentifier.isEqual(secondIdentifier)
    }

    private func fileIdentifier(for url: URL) -> NSObject? {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]) else {
            return nil
        }
        return values.fileResourceIdentifier as? NSObject
    }

    private func deleteRecording() -> Bool {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                presentError(
                    title: "Couldn't delete recording",
                    message: "The original file is still on disk. You can try again."
                )
                return false
            }
        }
        return true
    }

    private func closeAndFinish() {
        guard !hasFinished else { return }
        hasFinished = true
        renameController?.close()
        renameController = nil
        onFinish?()
    }

    private func presentError(title: String, message: String) {
        errorPresenter(title, message)
    }

    /// When a confirmation is shown, Return confirms and Escape cancels.
    static func makeDeleteConfirmationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete this recording?"
        alert.informativeText = "This permanently deletes the recording file. This can't be undone.\n\nYou can disable this confirmation in Settings."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert
    }

    static func defaultDeleteConfirmation(confirmBeforeClosing: Bool = true) -> Bool {
        guard confirmBeforeClosing else { return true }
        var confirmed = false
        let ask = {
            confirmed = AlertPresenter.runModal(makeDeleteConfirmationAlert()) == .alertFirstButtonReturn
        }
        if Thread.isMainThread {
            ask()
        } else {
            DispatchQueue.main.sync(execute: ask)
        }
        return confirmed
    }
}

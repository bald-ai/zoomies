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
    private let presentPanel: (RenamePanelController) -> Void
    private let removeFile: (URL) throws -> Void

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
         deleteConfirmer: DeleteConfirmer? = nil,
         removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         presentPanel: @escaping (RenamePanelController) -> Void = { $0.show() }) {
        self.fileURL = fileURL
        self.settingsStore = settingsStore
        self.clipboardService = clipboardService
        self.errorPresenter = errorPresenter
        self.removeFile = removeFile
        self.presentPanel = presentPanel
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
        presentPanel(controller)
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

        // Video has no note panel, so navigation has no completion to perform.
        guard let completion = action.completion else { return }
        if let name = completion.newName, !applyRenameIfNeeded(newName: name) { return }
        guard performCompletion(completion.action) else { return }
        closeAndFinish()
    }

    private func performCompletion(_ action: ScreenshotFinalAction) -> Bool {
        switch action {
        case .saveOnly, .closeOnly: return true
        case .copyAndSave:
            guard clipboardService.copyFile(at: fileURL, useCache: false) != nil else {
                presentError(title: "Copy failed",
                             message: "Zoomies couldn't copy the recording to the clipboard, but your save was kept. You can try Copy + Save again.")
                return false
            }
            return true
        case .copyAndDelete: return copyRecordingForDeletion() && deleteRecording()
        case .deleteOnly: return deleteConfirmer() && deleteRecording()
        }
    }

    /// Retain a published cache URL across deletion retries so a successful
    /// clipboard handoff is not replaced with duplicate cached files.
    private func copyRecordingForDeletion() -> Bool {
        if let published = publishedCopyAndDeleteURL,
           FileManager.default.fileExists(atPath: published.path) {
            return true
        }
        guard let published = clipboardService.copyFile(at: fileURL, useCache: true) else {
            presentError(title: "Copy failed",
                         message: "Zoomies couldn’t copy the recording to the clipboard, so the original file was left in place. You can try Copy + Delete again.")
            return false
        }
        publishedCopyAndDeleteURL = published
        return true
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
                try removeFile(fileURL)
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

    /// When a confirmation is shown, Escape confirms and R returns to the workflow.
    static func makeDeleteConfirmationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete this recording?"
        alert.informativeText = "This permanently deletes the recording file. This can't be undone.\n\nYou can disable this confirmation in Settings."
        alert.addButton(withTitle: "Delete (Esc)")
        alert.addButton(withTitle: "Go Back (R)")
        alert.buttons.first?.keyEquivalent = "\u{1b}"
        alert.buttons.first?.keyEquivalentModifierMask = []
        alert.buttons.last?.keyEquivalent = "r"
        alert.buttons.last?.keyEquivalentModifierMask = []
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

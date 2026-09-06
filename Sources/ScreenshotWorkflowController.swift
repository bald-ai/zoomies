import AppKit

/// Coordinates the post-capture flow for a single screenshot:
/// rename popup, optional note popup, and final actions
/// (save, copy+save, copy+delete, delete).
///
/// One instance exists per screenshot and is owned by `ScreenshotService`.
final class ScreenshotWorkflowController {
    typealias ImageDataWriter = (_ data: Data, _ outputURL: URL, _ originalURL: URL) throws -> URL
    typealias ErrorPresenter = (_ title: String, _ message: String) -> Void
    typealias FileRemover = (_ url: URL) throws -> Void
    typealias DeleteConfirmer = () -> Bool

    enum FinalAction {
        case saveOnly
        case copyAndSave
        case copyAndDelete
        case deleteOnly
        case closeOnly
    }

    private var fileURL: URL
    private var initialImage: NSImage?
    private var initialFilePersistence: Task<URL, Error>?
    private var initialFileReadyURL: URL?
    private let initialScreenshotCounter: Int?
    private let settingsStore: SettingsStore
    private let clipboardService: ClipboardService
    private let backupService: BackupService
    private let sourceScreen: NSScreen?
    private let escapeKeyDeletesFile: Bool
    private let imageDataWriter: ImageDataWriter
    private let errorPresenter: ErrorPresenter
    private let removeFile: FileRemover
    private let deleteConfirmer: DeleteConfirmer

    /// The clean (pre-note) original used to round-trip prompt edits when a saved
    /// PNG is reopened. For a fresh capture this is the in-memory image; for a
    /// reopened Zoomies PNG it is the original recovered from embedded metadata,
    /// so repeated re-edits never bake a note on top of an already-burned image.
    private let cleanOriginalPNG: Data?
    private let initialEditorState: EditorCanvasState?

    private var renameController: RenamePanelController?
    private var noteController: NotePanelController?
    private var editorController: EditorWindowController?

    var pendingNoteText: String = ""
    private var pendingEditedImage: NSImage?
    private var pendingEditorState: EditorCanvasState?
    private var burnedNoteText: String = ""
    private var hasCreatedBackup = false
    private var backupOriginalURL: URL?
    private var isFinalActionInProgress = false
    private var hasFinished = false
    private var publishedCopyAndDeleteURL: URL?

    /// Optional callback invoked once the workflow has fully completed.
    var onFinish: (() -> Void)?

    init(fileURL: URL,
         initialImage: NSImage? = nil,
         initialFilePersistence: Task<URL, Error>? = nil,
         initialScreenshotCounter: Int? = nil,
         settingsStore: SettingsStore,
         clipboardService: ClipboardService,
         backupService: BackupService,
         sourceScreen: NSScreen?,
         escapeKeyDeletesFile: Bool,
         imageDataWriter: @escaping ImageDataWriter = { data, outputURL, originalURL in
             try WorkflowImagePersistenceLogic.writeEncodedImageData(
                 data,
                 to: outputURL,
                 originalURL: originalURL
             )
         },
         errorPresenter: @escaping ErrorPresenter = { title, message in
             AlertPresenter.presentWarning(title: title, message: message)
         },
         removeFile: @escaping FileRemover = { url in
             try FileManager.default.removeItem(at: url)
         },
         deleteConfirmer: DeleteConfirmer? = nil) {
        self.fileURL = fileURL
        self.initialFilePersistence = initialFilePersistence
        self.initialScreenshotCounter = initialScreenshotCounter
        self.settingsStore = settingsStore
        self.clipboardService = clipboardService
        self.backupService = backupService
        self.sourceScreen = sourceScreen
        self.escapeKeyDeletesFile = escapeKeyDeletesFile
        self.imageDataWriter = imageDataWriter
        self.errorPresenter = errorPresenter
        self.removeFile = removeFile
        self.deleteConfirmer = deleteConfirmer ?? {
            ScreenshotWorkflowController.defaultDeleteConfirmation(
                confirmBeforeClosing: settingsStore.settings.confirmBeforeClosing
            )
        }

        let reopen = WorkflowReopenMetadataLogic.resolve(fileURL: fileURL, initialImage: initialImage)
        self.cleanOriginalPNG = reopen.cleanOriginalPNG
        self.initialEditorState = reopen.editorState
        // Swap the burned-on-disk image for the recovered clean original and
        // pre-fill the prompt the user previously typed.
        self.initialImage = reopen.image ?? initialImage
        if let prompt = reopen.prompt {
            self.pendingNoteText = prompt
        }
    }

    // MARK: - Public API

    func start() {
        // Ensure UI operations happen on main thread
        if Thread.isMainThread {
            presentRenamePanel()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.presentRenamePanel()
            }
        }
    }

    func cancel() {
        guard !hasFinished else { return }
        hasFinished = true
        isFinalActionInProgress = false
        // Close any open panels
        renameController?.close()
        noteController?.close()
        editorController?.dismissWithoutCompletion()
        renameController = nil
        noteController = nil
        editorController = nil
        pendingEditedImage = nil
        pendingEditorState = nil
    }

    // MARK: - Panels

    private func presentRenamePanel() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.presentRenamePanel()
            }
            return
        }
        let controller = RenamePanelController(initialFilename: fileURL.lastPathComponent,
                                               escapeKeyDeletesFile: escapeKeyDeletesFile)
        controller.onAction = { [weak self] action in
            self?.handleRenameAction(action)
        }
        renameController = controller
        center(controller.window, on: sourceScreen)
        // Do NOT activate or change activation policy here.
        // Activating the app can yank the user out of their current Space/fullscreen app
        // (it often looks like being “sent to Desktop”). We want a Spotlight-like panel.
        controller.show()
    }

    private func presentNotePanel(existingText: String = "") {
        let initialText = existingText.isEmpty ? pendingNoteText : existingText
        let controller = NotePanelController(initialText: initialText,
                                             escapeKeyDeletesFile: escapeKeyDeletesFile)
        controller.onAction = { [weak self] action in
            self?.handleNoteAction(action)
        }
        noteController = controller
        center(controller.window, on: sourceScreen)
        // Same rationale as rename: avoid activating the app (Space/Desktop jump).
        controller.show()
    }

    private func center(_ window: NSWindow?, on screen: NSScreen?) {
        guard let window = window else { return }

        if let screen = screen {
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
        guard !hasFinished, !isFinalActionInProgress else { return }

        // Carry any text typed in the Note panel across a Shift+Tab return to Rename,
        // so saving from Rename still burns the pending note onto the screenshot.
        let carriedNote = pendingNoteText.isEmpty ? nil : pendingNoteText

        switch action {
        case .save(let newName):
            guard applyRenameIfNeeded(newName: newName) else {
                return
            }
            complete(action: .saveOnly, note: carriedNote)

        case .copyAndSave(let newName):
            guard applyRenameIfNeeded(newName: newName) else {
                return
            }
            complete(action: .copyAndSave, note: carriedNote)

        case .copyAndDelete(let newName):
            guard applyRenameIfNeeded(newName: newName) else {
                return
            }
            complete(action: .copyAndDelete, note: carriedNote)

        case .delete:
            complete(action: .deleteOnly, note: nil)

        case .close:
            closeWorkflowWithoutDeleting()

        case .goToNote(let newName):
            guard applyRenameIfNeeded(newName: newName) else {
                return
            }
            presentNotePanel(existingText: pendingNoteText)
            renameController?.close()
            renameController = nil
        }
    }

    private func applyRenameIfNeeded(newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        let sanitizedFullName = sanitizeFilename(trimmed, preservingExtensionOf: fileURL)
        if sanitizedFullName == fileURL.lastPathComponent {
            return true
        }

        let directory = fileURL.deletingLastPathComponent()
        let requestedURL = directory.appendingPathComponent(sanitizedFullName)
        let targetURL = urlsReferToSameFile(fileURL, requestedURL)
            ? requestedURL
            : uniqueURL(forProposedName: sanitizedFullName, in: directory)

        if isWaitingForInitialFilePersistence || hasUnpersistedInitialCapture {
            fileURL = targetURL
            return true
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

    private func sanitizeFilename(_ input: String, preservingExtensionOf url: URL) -> String {
        WorkflowFilenameLogic.sanitizeFilename(input, preservingExtensionOf: url)
    }

    private func uniqueURL(forProposedName name: String, in directory: URL) -> URL {
        WorkflowFilenameLogic.uniqueURL(
            forProposedName: name,
            in: directory,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
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
        guard let values = try? url.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ) else {
            return nil
        }
        return values.fileResourceIdentifier as? NSObject
    }

    // MARK: - Note handling

    func handleNoteAction(_ action: NotePanelAction) {
        guard !hasFinished, !isFinalActionInProgress else { return }

        switch action {
        case .save(let text):
            complete(action: .saveOnly, note: text)

        case .copyAndSave(let text):
            complete(action: .copyAndSave, note: text)

        case .copyAndDelete(let text):
            complete(action: .copyAndDelete, note: text)

        case .delete:
            complete(action: .deleteOnly, note: nil)

        case .close:
            closeWorkflowWithoutDeleting()

        case .backToRename(let text):
            pendingNoteText = text
            // Open the destination panel first, then close the source panel.
            // This avoids focus arbitration delays and "no key window" glitches.
            presentRenamePanel()
            noteController?.close()
            noteController = nil

        case .goToEditor(let text):
            pendingNoteText = text
            openEditor(withNote: text)
        }
    }

    // MARK: - Editor

    private func openEditor(withNote text: String) {
        // Close the note panel; the rename panel is already closed by this point.
        noteController?.close()
        noteController = nil

        if let existing = editorController {
            // Rebuild the editor from the current composite image so a changed note
            // preview is reflected when returning Note -> Editor.
            pendingEditedImage = existing.currentCompositeImage()
            pendingEditorState = existing.currentEditableState()
            existing.dismissWithoutCompletion()
            editorController = nil
        }

        let editor: EditorWindowController?
        if let pendingEditedImage {
            editor = EditorWindowController(image: pendingEditedImage,
                                            settingsStore: settingsStore,
                                            notePreview: text,
                                            targetScreen: sourceScreen,
                                            escapeKeyDeletesFile: escapeKeyDeletesFile,
                                            initialState: pendingEditorState)
        } else if let initialImage {
            editor = EditorWindowController(image: initialImage,
                                            settingsStore: settingsStore,
                                            notePreview: text,
                                            targetScreen: sourceScreen,
                                            escapeKeyDeletesFile: escapeKeyDeletesFile,
                                            initialState: initialEditorState)
        } else {
            editor = EditorWindowController(imageURL: fileURL,
                                            settingsStore: settingsStore,
                                            notePreview: text,
                                            targetScreen: sourceScreen,
                                            escapeKeyDeletesFile: escapeKeyDeletesFile)
        }

        guard let editor else {
            // If the editor fails to load, fall back to a regular save.
            complete(action: .saveOnly, note: nil)
            return
        }

        editor.onComplete = { [weak self] image, action, editorState in
            self?.handleEditorCompletion(editedImage: image, action: action, editorState: editorState)
        }
        // The editor confirms Esc/X cancellation itself so a Cancel leaves the
        // window open with drawings intact. The workflow never re-asks, which
        // also keeps fresh captures to a single prompt after persistence lands.
        editor.onConfirmDelete = deleteConfirmer
        editor.onConfirmClose = {
            ScreenshotWorkflowController.defaultCloseConfirmation()
        }
        editor.onBackToNote = { [weak self] in
            self?.returnToNoteFromEditor()
        }

        editorController = editor
        editor.show()
    }

    private func returnToNoteFromEditor() {
        if let editor = editorController {
            pendingEditedImage = editor.currentCompositeImage()
            pendingEditorState = editor.currentEditableState()
            editor.dismissWithoutCompletion()
            editorController = nil
        }
        presentNotePanel(existingText: pendingNoteText)
    }

    func handleEditorCompletion(editedImage: NSImage?, action: FinalAction, editorState: EditorCanvasState? = nil) {
        guard !hasFinished, !isFinalActionInProgress else { return }

        pendingEditedImage = editedImage
        pendingEditorState = editorState
        let shouldReopenEditorOnFailure = editorController != nil

        if action != .closeOnly && isWaitingForInitialFilePersistence {
            isFinalActionInProgress = true
            waitForInitialFilePersistence { [weak self] ready in
                guard let self else { return }
                self.isFinalActionInProgress = false
                guard ready else {
                    self.reopenEditorIfNeeded(afterFailure: shouldReopenEditorOnFailure)
                    return
                }
                self.handleEditorCompletion(editedImage: editedImage, action: action, editorState: editorState)
            }
            return
        }

        isFinalActionInProgress = true
        guard retryInitialCapturePersistenceIfNeeded() else {
            isFinalActionInProgress = false
            reopenEditorIfNeeded(afterFailure: shouldReopenEditorOnFailure)
            return
        }

        editorController?.dismissWithoutCompletion()
        editorController = nil

        if action == .closeOnly {
            // Cancel/close: do not write to disk or composite discarded edits.
            guard restoreOriginalFromBackupIfAvailable() else {
                isFinalActionInProgress = false
                reopenEditorIfNeeded(afterFailure: shouldReopenEditorOnFailure)
                return
            }
            removeBackupIfNeeded()
            clearPendingEditorState()
            finishWorkflow()
            return
        }

        if action == .deleteOnly {
            guard deleteSourceFileAndBackup() else {
                isFinalActionInProgress = false
                reopenEditorIfNeeded(afterFailure: shouldReopenEditorOnFailure)
                return
            }
            clearPendingEditorState()
            finishWorkflow()
            return
        }

        var finalImage: NSImage?
        var baselinePNG: Data?
        var embedPrompt: String?
        var embedEditorState: EditorCanvasState?
        if let image = editedImage {
            // Editor returns a flattened image. If there's a pending note, burn it once
            // right before saving/copying so it never stacks/duplicates.
            if let preparedNote = WorkflowNoteRenderer.prepareNoteText(pendingNoteText, settings: settingsStore.settings),
               let noted = WorkflowNoteRenderer.burn(note: preparedNote.rendered, into: image) {
                finalImage = noted
                burnedNoteText = preparedNote.identity
                // Editor edits become the new clean baseline; only the note is round-tripped.
                baselinePNG = baselinePNGForEmbedding(preNoteImage: image)
                embedPrompt = preparedNote.identity
                embedEditorState = editorState
            } else {
                finalImage = image
                burnedNoteText = ""
                embedEditorState = editorState
            }
        }

        if let finalImage,
           (action == .saveOnly || action == .copyAndSave) {
            // Save the final (possibly noted) image to disk.
            guard saveEditedImage(finalImage,
                                  baselinePNG: baselinePNG,
                                  prompt: embedPrompt,
                                  editorState: embedEditorState) else {
                isFinalActionInProgress = false
                reopenEditorIfNeeded(afterFailure: shouldReopenEditorOnFailure)
                return
            }
            // Workflow finished normally: remove backup if one was created.
            removeBackupIfNeeded()
        }

        guard performFinalActionEffects(action, copyAndDeleteImage: finalImage) else {
            isFinalActionInProgress = false
            reopenEditorIfNeeded(afterFailure: shouldReopenEditorOnFailure)
            return
        }
        clearPendingEditorState()
        finishWorkflow()
    }

    private func saveEditedImage(_ image: NSImage,
                                 baselinePNG: Data?,
                                 prompt: String?,
                                 editorState: EditorCanvasState?) -> Bool {
        ensureBackupExists()
        return encodeAndWriteImage(image,
                                   baselinePNG: baselinePNG,
                                   prompt: prompt,
                                   editorState: editorState,
                                   errorTitle: "Failed to save image")
    }

    /// Returns the PNG bytes to embed as the round-trip original for an image the
    /// note will be burned onto, or nil when the output is not a PNG.
    private func baselinePNGForEmbedding(preNoteImage: NSImage) -> Data? {
        guard fileURL.pathExtension.lowercased() == "png" else { return nil }
        return ScreenshotServiceCoreLogic.pngData(from: preNoteImage)
    }

    private func encodeAndWriteImage(_ image: NSImage,
                                     baselinePNG: Data?,
                                     prompt: String?,
                                     editorState: EditorCanvasState?,
                                     errorTitle: String) -> Bool {
        guard let encoded = WorkflowImagePersistenceLogic.encodedImageData(
            from: image,
            originalURL: fileURL,
            cleanOriginalPNG: baselinePNG,
            prompt: prompt,
            editorState: editorState,
            uniqueURL: { name, directory in
                WorkflowFilenameLogic.uniqueURL(forProposedName: name,
                                                in: directory,
                                                fileExists: { FileManager.default.fileExists(atPath: $0) })
            }
        ) else {
            presentError(title: errorTitle, message: "Could not encode the image.")
            return false
        }

        do {
            let finalURL = try imageDataWriter(encoded.data, encoded.outputURL, fileURL)
            if finalURL != fileURL {
                fileURL = finalURL
            }
            return true
        } catch {
            presentError(title: errorTitle, message: error.localizedDescription)
            return false
        }
    }

    private func ensureBackupExists() {
        guard !hasCreatedBackup else { return }
        if backupService.createBackup(forOriginalURL: fileURL) {
            hasCreatedBackup = true
            backupOriginalURL = fileURL
        } else {
            presentError(
                title: "Couldn't back up screenshot",
                message: "Zoomies couldn't back up the original file, so restoring it later may not work. Your save will continue."
            )
        }
    }

    private func removeBackupIfNeeded() {
        guard hasCreatedBackup else { return }
        backupService.removeBackup(forOriginalURL: backupOriginalURL ?? fileURL)
        hasCreatedBackup = false
        backupOriginalURL = nil
    }

    private var isWaitingForInitialFilePersistence: Bool {
        initialFileReadyURL == nil && initialFilePersistence != nil
    }

    private var hasUnpersistedInitialCapture: Bool {
        initialFileReadyURL == nil
            && initialFilePersistence == nil
            && initialImage != nil
            && initialScreenshotCounter != nil
    }

    private func retryInitialCapturePersistenceIfNeeded() -> Bool {
        guard hasUnpersistedInitialCapture else { return true }
        guard let initialImage,
              let imageData = ScreenshotServiceCoreLogic.pngData(from: initialImage) else {
            presentError(title: "Failed to save image", message: "Could not encode the screenshot.")
            return false
        }

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try imageData.write(to: fileURL, options: .atomic)
            if let initialScreenshotCounter {
                settingsStore.update { settings in
                    settings.screenshotCounter = max(
                        settings.screenshotCounter,
                        Settings.nextScreenshotCounter(after: initialScreenshotCounter)
                    )
                }
            }
            initialFileReadyURL = fileURL
            self.initialImage = nil
            return true
        } catch {
            presentError(title: "Failed to save image", message: error.localizedDescription)
            return false
        }
    }

    private func waitForInitialFilePersistence(completion: @escaping (Bool) -> Void) {
        if let initialFileReadyURL {
            fileURL = initialFileReadyURL
            completion(true)
            return
        }

        guard let initialFilePersistence else {
            completion(true)
            return
        }

        Task { [weak self] in
            guard let self else { return }

            do {
                let writtenURL = try await initialFilePersistence.value
                await MainActor.run {
                    do {
                        try self.reconcileInitialFileWriteIfNeeded(writtenURL: writtenURL)
                        completion(true)
                    } catch {
                        self.presentError(title: "Failed to save image", message: error.localizedDescription)
                        completion(false)
                    }
                }
            } catch {
                await MainActor.run {
                    self.initialFilePersistence = nil
                    self.presentError(title: "Failed to save image", message: error.localizedDescription)
                    completion(false)
                }
            }
        }
    }

    private func reconcileInitialFileWriteIfNeeded(writtenURL: URL) throws {
        if let initialFileReadyURL {
            fileURL = initialFileReadyURL
            return
        }

        if writtenURL != fileURL {
            try FileManager.default.moveItem(at: writtenURL, to: fileURL)
        } else {
            fileURL = writtenURL
        }

        initialFileReadyURL = fileURL
        initialFilePersistence = nil
        initialImage = nil
    }

    // MARK: - Completion

    private func complete(action: FinalAction, note: String?) {
        guard !hasFinished, !isFinalActionInProgress else { return }

        if action == .closeOnly {
            closeWorkflowWithoutDeleting()
            return
        }

        if isWaitingForInitialFilePersistence {
            isFinalActionInProgress = true
            waitForInitialFilePersistence { [weak self] ready in
                guard let self else { return }
                self.isFinalActionInProgress = false
                guard ready else { return }
                self.complete(action: action, note: note)
            }
            return
        }

        isFinalActionInProgress = true
        guard retryInitialCapturePersistenceIfNeeded() else {
            isFinalActionInProgress = false
            return
        }

        if action == .deleteOnly {
            guard deleteConfirmer() else {
                isFinalActionInProgress = false
                return
            }
            guard deleteSourceFileAndBackup() else {
                isFinalActionInProgress = false
                return
            }
            closeInputControllers()
            clearPendingEditorState()
            finishWorkflow()
            return
        }

        let pendingImage: NSImage? = {
            if let editor = editorController {
                let image = editor.currentCompositeImage()
                pendingEditorState = editor.currentEditableState()
                editor.dismissWithoutCompletion()
                editorController = nil
                return image
            }
            return pendingEditedImage
        }()

        let imageToPersist: NSImage?
        var baselinePNG: Data?
        var embedPrompt: String?
        var embedEditorState: EditorCanvasState?
        if let pendingImage {
            var finalImage = pendingImage
            if let note,
               let preparedNote = WorkflowNoteRenderer.prepareNoteText(note, settings: settingsStore.settings) {
                guard let noted = WorkflowNoteRenderer.burn(note: preparedNote.rendered, into: finalImage) else {
                    presentError(title: "Failed to apply note", message: "Could not render the note text.")
                    isFinalActionInProgress = false
                    return
                }
                finalImage = noted
                burnedNoteText = preparedNote.identity
                // Carried editor edits become the new baseline; only the note round-trips.
                baselinePNG = baselinePNGForEmbedding(preNoteImage: pendingImage)
                embedPrompt = preparedNote.identity
                embedEditorState = pendingEditorState
            } else {
                burnedNoteText = ""
                embedEditorState = pendingEditorState
            }
            imageToPersist = finalImage
        } else {
            imageToPersist = nil
            if let note {
                guard applyNoteIfNeeded(note) else {
                    isFinalActionInProgress = false
                    return
                }
            }
        }

        guard persistImageIfNeeded(imageToPersist,
                                   for: action,
                                   baselinePNG: baselinePNG,
                                   prompt: embedPrompt,
                                   editorState: embedEditorState) else {
            isFinalActionInProgress = false
            return
        }
        guard performFinalActionEffects(action, copyAndDeleteImage: nil) else {
            isFinalActionInProgress = false
            return
        }
        if action == .saveOnly || action == .copyAndSave {
            removeBackupIfNeeded()
        }

        closeInputControllers()
        clearPendingEditorState()
        finishWorkflow()
    }

    private func deleteSourceFileAndBackup() -> Bool {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try removeFile(fileURL)
            } catch {
                presentError(
                    title: "Couldn't delete screenshot",
                    message: "The original file is still on disk. You can try again."
                )
                return false
            }
        }
        backupService.removeBackup(forOriginalURL: backupOriginalURL ?? fileURL)
        hasCreatedBackup = false
        backupOriginalURL = nil
        return true
    }

    // MARK: - Note rendering

    @discardableResult
    private func applyNoteIfNeeded(_ rawText: String) -> Bool {
        guard let preparedNote = WorkflowNoteRenderer.prepareNoteText(rawText, settings: settingsStore.settings) else { return true }

        if preparedNote.identity == burnedNoteText {
            return true
        }

        ensureBackupExists()

        // Prefer the recovered clean original so re-saving a reopened Zoomies PNG
        // never bakes a note on top of an already-burned image.
        guard let base = initialImage ?? NSImage(contentsOf: fileURL) else {
            presentError(title: "Failed to apply note", message: "Could not read the screenshot image.")
            return false
        }
        // A reopened annotated file carries its drawings in initialEditorState
        // while initialImage is the bare base. Composite first so a note-only
        // save keeps the visible drawings instead of flattening over the base.
        let image = annotatedBaseImage(from: base)
        guard let updated = WorkflowNoteRenderer.burn(note: preparedNote.rendered, into: image) else {
            presentError(title: "Failed to apply note", message: "Could not render the note text.")
            return false
        }

        // Editor-state-only reopens have no recovered clean original; fall back
        // to the composited pre-note image so the prompt still embeds and
        // round-trips instead of being silently dropped.
        let baseline = cleanOriginalPNG ?? baselinePNGForEmbedding(preNoteImage: image)
        guard encodeAndWriteImage(updated,
                                  baselinePNG: baseline,
                                  prompt: preparedNote.identity,
                                  editorState: initialEditorState,
                                  errorTitle: "Failed to apply note") else {
            return false
        }
        burnedNoteText = preparedNote.identity
        return true
    }

    /// Rebuilds the visible annotated image for a note-only save on a reopened
    /// file. Returns the base unchanged when there is no carried editor state.
    private func annotatedBaseImage(from base: NSImage) -> NSImage {
        guard let state = initialEditorState,
              state.isSafeToRestore(),
              !state.items.isEmpty else {
            return base
        }
        // Mirror EditorWindowController: redraw the carried annotations over
        // the state's own clean base exactly once.
        let canvasBase = NSImage(data: state.baseImagePNG) ?? base
        return EditorCanvasView(image: canvasBase, initialState: state).compositeImage()
    }

    private func persistImageIfNeeded(_ image: NSImage?,
                                      for action: FinalAction,
                                      baselinePNG: Data?,
                                      prompt: String?,
                                      editorState: EditorCanvasState?) -> Bool {
        guard let image else { return true }

        switch action {
        case .saveOnly, .copyAndSave, .copyAndDelete:
            return saveEditedImage(image, baselinePNG: baselinePNG, prompt: prompt, editorState: editorState)
        case .deleteOnly, .closeOnly:
            return true
        }
    }

    private func performFinalActionEffects(_ action: FinalAction, copyAndDeleteImage: NSImage?) -> Bool {
        switch action {
        case .saveOnly:
            break
        case .copyAndSave:
            // The save already persisted above, so the save stands; warn and
            // stay open so the user can retry the copy.
            guard clipboardService.copyFile(at: fileURL, useCache: false) != nil else {
                presentError(
                    title: "Copy failed",
                    message: "Zoomies couldn't copy the screenshot to the clipboard, but your save was kept. You can try Copy + Save again."
                )
                return false
            }
        case .copyAndDelete:
            if let published = publishedCopyAndDeleteURL,
               FileManager.default.fileExists(atPath: published.path) {
                return deleteSourceFileAndBackup()
            }
            let published: URL?
            if let copyAndDeleteImage {
                published = clipboardService.copyImageAsFile(copyAndDeleteImage, fileName: fileURL.lastPathComponent)
            } else {
                published = clipboardService.copyFile(at: fileURL, useCache: true)
            }
            guard let published else {
                presentError(
                    title: "Copy failed",
                    message: "Zoomies couldn’t copy the screenshot to the clipboard, so the original file was left in place. You can try Copy + Delete again."
                )
                return false
            }
            publishedCopyAndDeleteURL = published
            return deleteSourceFileAndBackup()
        case .deleteOnly:
            return deleteSourceFileAndBackup()
        case .closeOnly:
            return false
        }
        return true
    }

    private func restoreOriginalFromBackupIfAvailable() -> Bool {
        let originalURL = backupOriginalURL ?? fileURL
        let backupURL = backupService.backupURL(forOriginalURL: originalURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupURL.path) else { return true }

        do {
            if fm.fileExists(atPath: fileURL.path), fileURL != originalURL {
                // If format conversion changed the output URL (e.g. a non-PNG
                // original rewritten to .png), remove the converted file before
                // restoring the original.
                try? fm.removeItem(at: fileURL)
            }
            if fm.fileExists(atPath: originalURL.path) {
                try fm.removeItem(at: originalURL)
            }
            try fm.copyItem(at: backupURL, to: originalURL)
            fileURL = originalURL
            return true
        } catch {
            presentError(title: "Failed to restore original", message: error.localizedDescription)
            return false
        }
    }

    private func closeWorkflowWithoutDeleting() {
        guard !hasFinished, !isFinalActionInProgress else { return }
        isFinalActionInProgress = true

        // Cancel/close semantics for "reopen" flow: close panels without deleting the file.
        // If we have a backup (note/editor touched disk), restore it first.
        if !restoreOriginalFromBackupIfAvailable() {
            isFinalActionInProgress = false
            return
        }
        removeBackupIfNeeded()

        closeInputControllers()
        clearPendingEditorState()
        finishWorkflow()
    }

    private func closeInputControllers() {
        renameController?.close()
        noteController?.close()
        editorController?.dismissWithoutCompletion()
        renameController = nil
        noteController = nil
        editorController = nil
    }

    private func clearPendingEditorState() {
        pendingEditedImage = nil
        pendingEditorState = nil
        burnedNoteText = ""
    }

    private func reopenEditorIfNeeded(afterFailure shouldReopen: Bool) {
        guard shouldReopen else { return }
        editorController = nil
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.hasFinished,
                  !self.isFinalActionInProgress,
                  self.editorController == nil else {
                return
            }
            self.openEditor(withNote: self.pendingNoteText)
        }
    }

    private func finishWorkflow() {
        guard !hasFinished else { return }
        hasFinished = true
        isFinalActionInProgress = false
        onFinish?()
    }

    // MARK: - Errors

    private func presentError(title: String, message: String) {
        errorPresenter(title, message)
    }

    /// When a confirmation is shown, Return confirms and Escape cancels.
    static func makeDeleteConfirmationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete this screenshot?"
        alert.informativeText = "This permanently deletes the screenshot file. This can't be undone.\n\nYou can disable this confirmation in Settings."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert
    }

    static func defaultDeleteConfirmation(confirmBeforeClosing: Bool = true) -> Bool {
        guard confirmBeforeClosing else { return true }
        return presentCancellationConfirmation(makeDeleteConfirmationAlert)
    }

    static func makeCloseConfirmationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Close this editing session?"
        alert.informativeText = "Unsaved edits will be discarded. The original image will not be deleted.\n\nYou can disable this confirmation in Settings."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.keyEquivalent = "\r"
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert
    }

    static func defaultCloseConfirmation() -> Bool {
        presentCancellationConfirmation(makeCloseConfirmationAlert)
    }

    private static func presentCancellationConfirmation(_ makeAlert: @escaping () -> NSAlert) -> Bool {
        var confirmed = false
        let ask = {
            confirmed = AlertPresenter.runModal(makeAlert()) == .alertFirstButtonReturn
        }
        if Thread.isMainThread {
            ask()
        } else {
            DispatchQueue.main.sync(execute: ask)
        }
        return confirmed
    }
}

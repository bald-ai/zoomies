import AppKit

/// Runs the note flow with the screenshot flow's tab-swapping screens:
/// rename ⇄ note ⇄ editor. It starts on the note window; Shift+Tab goes to
/// rename and Tab to the note editor. A note saves as a PNG (the drawing with
/// the Note box burned in below it) carrying the editable note, so
/// Option+Shift+2 reopens it.
@MainActor
final class ScratchpadService {
    enum PresentedPanel: Equatable { case rename, note, editor }

    private let fileManager: FileManager
    private let clipboardService: ClipboardService
    private let settingsStore: SettingsStore?
    private let directory: URL
    private let showNote: @MainActor (DedicatedNotePanelController) -> Void
    private let showRename: @MainActor (RenamePanelController) -> Void
    private let showEditor: @MainActor (InkNoteWindowController) -> Void
    private let errorPresenter: (String, String) -> Void
    private let confirmDiscard: @MainActor () -> Bool

    private(set) var renamePanel: RenamePanelController?
    private(set) var notePanel: DedicatedNotePanelController?
    private(set) var editor: InkNoteWindowController?
    /// Which screen the flow is showing; `nil` when no note is open.
    private(set) var presentedPanel: PresentedPanel?
    private(set) var document = InkNoteDocument(note: "")
    private var savedDocument = InkNoteDocument(note: "")
    private var baseName = ""
    /// The file this note was opened from or last saved to; saving replaces it.
    private(set) var fileURL: URL?

    /// Notes never block captures: screenshotting while writing a note is normal.
    var isBusyForUserCommands: Bool { false }

    init(fileManager: FileManager = .default,
         clipboardService: ClipboardService,
         settingsStore: SettingsStore? = nil,
         desktopDirectory: URL? = nil,
         showNote: @escaping @MainActor (DedicatedNotePanelController) -> Void = { $0.show() },
         showRename: @escaping @MainActor (RenamePanelController) -> Void = { $0.show() },
         showEditor: @escaping @MainActor (InkNoteWindowController) -> Void = { $0.present() },
         errorPresenter: @escaping (String, String) -> Void = { AlertPresenter.presentWarning(title: $0, message: $1) },
         confirmDiscard: @escaping @MainActor () -> Bool = ScratchpadService.defaultConfirmDiscard) {
        self.fileManager = fileManager
        self.clipboardService = clipboardService
        self.settingsStore = settingsStore
        self.showNote = showNote
        self.showRename = showRename
        self.showEditor = showEditor
        self.errorPresenter = errorPresenter
        self.confirmDiscard = confirmDiscard
        directory = desktopDirectory
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Starts a new note on the note window, or brings back the open one.
    func open(date: Date = Date()) {
        guard !bringFlowForward() else { return }
        start(InkNoteDocument(note: ""), baseName: ScratchpadFilenameLogic.defaultBaseName(date: date), fileURL: nil)
    }

    /// Reopens a saved note on its note window; saving replaces the file.
    func open(existing url: URL, document: InkNoteDocument) {
        guard !bringFlowForward() else { return }
        start(document, baseName: url.deletingPathExtension().lastPathComponent, fileURL: url)
    }

    private func start(_ document: InkNoteDocument, baseName: String, fileURL: URL?) {
        self.document = document
        savedDocument = document
        self.baseName = baseName
        self.fileURL = fileURL
        presentNotePanel()
    }

    private func bringFlowForward() -> Bool {
        switch presentedPanel {
        case .rename: renamePanel.map(showRename)
        case .note: notePanel.map(showNote)
        case .editor: editor.map(showEditor)
        case nil: return false
        }
        return true
    }

    // MARK: - Screens

    private func presentNotePanel() {
        let controller = DedicatedNotePanelController(initialText: document.note)
        controller.onAction = { [weak self] action in self?.handleNoteAction(action) }
        closeScreens()
        notePanel = controller
        presentedPanel = .note
        centerOnActiveScreen(controller.window)
        showNote(controller)
    }

    private func presentRenamePanel() {
        let controller = RenamePanelController(initialFilename: baseName + ".png",
                                               escapeKeyDeletesFile: false,
                                               showsCopyAndDiscard: false)
        controller.onAction = { [weak self] action in self?.handleRenameAction(action) }
        closeScreens()
        renamePanel = controller
        presentedPanel = .rename
        centerOnActiveScreen(controller.window)
        showRename(controller)
    }

    private func presentEditor() {
        let controller = InkNoteWindowController(noteDocument: document, title: baseName, settingsStore: settingsStore)
        controller.onAction = { [weak self] action in self?.handleEditorAction(action) }
        closeScreens()
        editor = controller
        presentedPanel = .editor
        showEditor(controller)
    }

    func handleNoteAction(_ action: NotePanelAction) {
        switch action {
        case .save(let text):
            document.note = text
            save(copy: false)
        case .copyAndSave(let text):
            document.note = text
            save(copy: true)
        case .goToEditor(let text):
            document.note = text
            presentEditor()
        case .backToRename(let text):
            document.note = text
            presentRenamePanel()
        case .close, .delete:
            requestClose()
        case .copyAndDelete:
            break
        }
    }

    func handleRenameAction(_ action: RenamePanelAction) {
        switch action {
        case .save(let name):
            baseName = ScratchpadFilenameLogic.resolveBaseName(userInput: name, fallback: baseName)
            save(copy: false)
        case .copyAndSave(let name):
            baseName = ScratchpadFilenameLogic.resolveBaseName(userInput: name, fallback: baseName)
            save(copy: true)
        case .goToNote(let name):
            baseName = ScratchpadFilenameLogic.resolveBaseName(userInput: name, fallback: baseName)
            presentNotePanel()
        case .close, .delete:
            requestClose()
        case .copyAndDelete:
            break
        }
    }

    func handleEditorAction(_ action: InkNoteWindowController.Action) {
        switch action {
        case .save(let note):
            document = note
            save(copy: false)
        case .copyAndSave(let note):
            document = note
            save(copy: true)
        case .backToNote(let note):
            document = note
            presentNotePanel()
        case .close(let note):
            document = note
            requestClose()
        }
    }

    // MARK: - Completion

    /// Writes the PNG. An untouched note leaves no file. If copying fails the
    /// note stays open, already saved, so Copy + Save can be tried again.
    private func save(copy: Bool) {
        guard !document.isEmpty else {
            closeFlow()
            return
        }
        guard let data = InkNoteRenderer.pngData(for: document) else {
            errorPresenter("Couldn't save note", "The note could not be drawn into an image.")
            return
        }
        let folder = fileURL?.deletingLastPathComponent() ?? directory
        let name = baseName + ".png"
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = fileURL.flatMap { $0.lastPathComponent == name ? $0 : nil }
                ?? UniqueFileURLLogic.uniqueURL(forProposedName: name, in: folder,
                                                fileExists: { [fileManager] in fileManager.fileExists(atPath: $0) })
            try data.write(to: target, options: .atomic)
            // Renaming a saved note moves it rather than leaving a copy behind.
            if let fileURL, fileURL != target { try? fileManager.removeItem(at: fileURL) }
            fileURL = target
            baseName = target.deletingPathExtension().lastPathComponent
            savedDocument = document
            if copy, clipboardService.copyFile(at: target, useCache: false) == nil {
                errorPresenter("Couldn't copy note",
                               "\(target.lastPathComponent) was saved, but could not be copied to the clipboard. Try Copy + Save again.")
                return
            }
            closeFlow()
        } catch {
            errorPresenter("Couldn't save note", error.localizedDescription)
        }
    }

    /// Esc anywhere in the flow. Unsaved text or drawing asks first, unless
    /// that confirmation is turned off in Settings.
    private func requestClose() {
        if let notePanel { document.note = notePanel.text }
        let unsaved = document != savedDocument && !document.isEmpty
        if unsaved, settingsStore?.settings.confirmBeforeClosing ?? true, !confirmDiscard() { return }
        closeFlow()
    }

    private func closeScreens() {
        renamePanel?.close()
        notePanel?.close()
        editor?.close()
        renamePanel = nil
        notePanel = nil
        editor = nil
    }

    private func closeFlow() {
        closeScreens()
        presentedPanel = nil
        document = InkNoteDocument(note: "")
        savedDocument = document
        baseName = ""
        fileURL = nil
    }

    static func defaultConfirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard this note?"
        alert.informativeText = "Its text and drawing have not been saved.\n\nYou can disable this confirmation in Settings."
        alert.addButton(withTitle: "Discard (Esc)")
        alert.addButton(withTitle: "Go Back (R)")
        alert.buttons.first?.keyEquivalent = "\u{1b}"
        alert.buttons.first?.keyEquivalentModifierMask = []
        alert.buttons.last?.keyEquivalent = "r"
        alert.buttons.last?.keyEquivalentModifierMask = []
        AlertPresenter.keepLetterShortcutsWorking(in: alert)
        return AlertPresenter.runModal(alert) == .alertFirstButtonReturn
    }

    private func centerOnActiveScreen(_ window: NSWindow?) {
        guard let window else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else {
            window.center()
            return
        }
        window.setFrameOrigin(FloatingPanelPositionLogic.centeredOrigin(windowSize: window.frame.size, in: screen.visibleFrame))
    }
}

import AppKit

/// Starts a new note in the ink note editor. Notes save as PNGs on the
/// Desktop and reopen with Option+Shift+2, like screenshots; this flow never
/// writes Markdown.
@MainActor
final class ScratchpadService {
    private let fileManager: FileManager
    private let clipboardService: ClipboardService
    private let directory: URL
    private let present: @MainActor (InkNoteWindowController) -> Void
    /// Names handed to notes this session, so two notes opened within the same
    /// second never share a file before either is saved.
    private var reservedPaths: Set<String> = []

    /// Lets the app track the new note window like any other open note.
    var onOpen: ((InkNoteWindowController) -> Void)?

    /// Note windows never block captures: screenshotting while writing a note is normal.
    var isBusyForUserCommands: Bool { false }

    init(fileManager: FileManager = .default,
         clipboardService: ClipboardService,
         desktopDirectory: URL? = nil,
         present: @escaping @MainActor (InkNoteWindowController) -> Void = { $0.present() }) {
        self.fileManager = fileManager
        self.clipboardService = clipboardService
        self.present = present
        directory = desktopDirectory
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    @discardableResult
    func open(date: Date = Date()) -> InkNoteWindowController {
        let noteURL = UniqueFileURLLogic.uniqueURL(
            forProposedName: ScratchpadFilenameLogic.defaultBaseName(date: date) + ".png",
            in: directory,
            fileExists: { [fileManager, reservedPaths] path in fileManager.fileExists(atPath: path) || reservedPaths.contains(path) }
        )
        reservedPaths.insert(noteURL.path)
        let editor = InkNoteWindowController(opened: .init(noteURL: noteURL, sourceURL: noteURL, document: InkNoteDocument(text: "")))
        editor.copyFile = { [clipboardService] url in _ = clipboardService.copyFile(at: url, useCache: false) }
        onOpen?(editor)
        present(editor)
        return editor
    }
}

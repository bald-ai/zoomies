import XCTest
import AppKit
@testable import Zoomies

@MainActor
final class ScratchpadServiceTests: XCTestCase {
    @MainActor private final class Fixture {
        let root: URL
        var shownNotes: [DedicatedNotePanelController] = []
        var shownRenames: [RenamePanelController] = []
        var shownEditors: [InkNoteWindowController] = []
        var errors: [String] = []
        var copied: [URL] = []
        var acceptsClipboard = true
        var confirms = 0
        var confirmAnswer = true
        var service: ScratchpadService!
        var desktop: URL { root.appendingPathComponent("desktop") }

        init(settingsStore: SettingsStore? = nil) throws {
            _ = NSApplication.shared
            root = try TestSupport.makeTemporaryDirectory()
            let clipboard = ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { [unowned self] objects in
                guard acceptsClipboard else { return false }
                copied.append(objects[0] as! URL); return true
            })
            service = ScratchpadService(clipboardService: clipboard, settingsStore: settingsStore, desktopDirectory: desktop,
                                        showNote: { [unowned self] in shownNotes.append($0) },
                                        showRename: { [unowned self] in shownRenames.append($0) },
                                        showEditor: { [unowned self] in shownEditors.append($0) },
                                        errorPresenter: { [unowned self] title, _ in errors.append(title) },
                                        confirmDiscard: { [unowned self] in confirms += 1; return confirmAnswer })
        }
        func files() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: desktop.path))?.sorted() ?? [] }
        deinit { TestSupport.removeIfExists(root) }
    }

    private var date: Date { Date(timeIntervalSince1970: 1_790_000_000) }
    private var defaultName: String { ScratchpadFilenameLogic.defaultBaseName(date: date) }

    func testANewNoteStartsOnTheNoteWindowAndTabsBetweenRenameNoteAndEditor() throws {
        let f = try Fixture()
        f.service.open(date: date)
        XCTAssertEqual(f.service.presentedPanel, .note)
        XCTAssertEqual(f.shownNotes.count, 1)
        XCTAssertFalse(f.service.isBusyForUserCommands, "An open note never blocks a capture")

        f.service.handleNoteAction(.goToEditor(text: "Check the header"))
        XCTAssertEqual(f.service.presentedPanel, .editor)
        let editor = try XCTUnwrap(f.shownEditors.last)
        XCTAssertEqual(editor.noteDocument.note, "Check the header")
        XCTAssertEqual(InkNoteRenderer.pageText(editor.noteDocument), "Check the header", "The note window's text is the page")
        XCTAssertTrue(editor.noteBar.isHidden, "No marker lines yet, so no Note box")
        XCTAssertEqual(editor.window?.title, defaultName)
        XCTAssertNil(f.service.notePanel, "Only one screen of the flow is open at a time")

        editor.perform(.tool(.marker))
        editor.addMarker(at: CGPoint(x: 100, y: 100))
        editor.setMarkerNote(1, text: "too small")
        editor.perform(.backToNote)
        XCTAssertEqual(f.service.presentedPanel, .note)
        XCTAssertEqual(f.service.notePanel?.text, "Check the header\n\n\n1: too small", "Marker lines are part of the note")
        XCTAssertEqual(f.service.document.markers.count, 1, "The drawing survives going back to the note")

        f.service.handleNoteAction(.backToRename(text: "Check the header"))
        XCTAssertEqual(f.service.presentedPanel, .rename)
        XCTAssertEqual(f.shownRenames.count, 1)
        f.service.handleRenameAction(.goToNote(newName: "Header"))
        XCTAssertEqual(f.service.presentedPanel, .note)
        f.service.handleNoteAction(.goToEditor(text: "Check the header"))
        XCTAssertEqual(f.shownEditors.last?.window?.title, "Header")
        XCTAssertEqual(f.shownEditors.last?.noteDocument.markers.count, 1)
    }

    func testOpeningAgainBringsTheOpenNoteForward() throws {
        let f = try Fixture()
        f.service.open(date: date)
        f.service.handleNoteAction(.goToEditor(text: "One"))
        f.service.open(date: date)
        XCTAssertEqual(f.shownEditors.count, 2, "The open editor is shown again")
        XCTAssertTrue(f.shownEditors[0] === f.shownEditors[1])
        XCTAssertEqual(f.shownNotes.count, 1, "No second note is started")
    }

    func testEnterSavesAPNGWithTheNoteBurnedInAndTheEditableNoteInside() throws {
        let f = try Fixture()
        f.service.open(date: date)
        f.service.handleNoteAction(.save(text: "Fix the label clipping."))
        XCTAssertNil(f.service.presentedPanel)
        XCTAssertEqual(f.files(), [defaultName + ".png"])
        let data = try Data(contentsOf: f.desktop.appendingPathComponent(defaultName + ".png"))
        XCTAssertNotNil(NSImage(data: data))
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: data)?.note, "Fix the label clipping.")
        XCTAssertTrue(f.copied.isEmpty)
    }

    func testAnUntouchedNoteLeavesNoFile() throws {
        let f = try Fixture()
        f.service.open(date: date)
        f.service.handleNoteAction(.save(text: "  "))
        XCTAssertNil(f.service.presentedPanel)
        XCTAssertEqual(f.files(), [])
        f.service.open(date: date)
        f.service.handleNoteAction(.close)
        XCTAssertEqual(f.confirms, 0, "Nothing to lose, nothing to ask")
    }

    func testSavingFromTheEditorAndRenameCopiesAndReopenReplacesTheFile() throws {
        let f = try Fixture()
        f.service.open(date: date)
        f.service.handleNoteAction(.goToEditor(text: "Note"))
        let editor = try XCTUnwrap(f.shownEditors.last)
        editor.perform(.tool(.marker))
        editor.addMarker(at: CGPoint(x: 200, y: 150))
        editor.perform(.copyAndSave)
        let url = f.desktop.appendingPathComponent(defaultName + ".png")
        XCTAssertEqual(f.copied, [url])
        XCTAssertEqual(f.files(), [url.lastPathComponent])
        let saved = try XCTUnwrap(PNGMetadata.extractInkNote(fromPNG: Data(contentsOf: url)))
        XCTAssertEqual(saved.markers.count, 1)

        f.service.open(existing: url, document: saved)
        XCTAssertEqual(f.service.presentedPanel, .note, "A reopened note starts on its note window too")
        XCTAssertEqual(f.service.notePanel?.text, "Note")
        f.service.handleNoteAction(.save(text: "Note, edited"))
        XCTAssertEqual(f.files(), [url.lastPathComponent], "Saving a reopened note replaces it")
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: try Data(contentsOf: url))?.note, "Note, edited")
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: try Data(contentsOf: url))?.markers.count, 1)

        f.service.open(existing: url, document: try XCTUnwrap(PNGMetadata.extractInkNote(fromPNG: Data(contentsOf: url))))
        f.service.handleNoteAction(.backToRename(text: "Note, edited"))
        f.service.handleRenameAction(.save(newName: "Login bug.png"))
        XCTAssertEqual(f.files(), ["Login bug.png"], "Renaming a saved note moves it")
    }

    func testANewNoteNeverOverwritesAnExistingFile() throws {
        let f = try Fixture()
        try FileManager.default.createDirectory(at: f.desktop, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: f.desktop.appendingPathComponent(defaultName + ".png"))
        f.service.open(date: date)
        f.service.handleNoteAction(.save(text: "New"))
        XCTAssertEqual(f.files().count, 2)
        XCTAssertEqual(try Data(contentsOf: f.desktop.appendingPathComponent(defaultName + ".png")), Data("other".utf8))
    }

    func testEscapeAsksBeforeDiscardingUnlessTurnedOff() throws {
        let f = try Fixture()
        f.service.open(date: date)
        f.service.handleNoteAction(.goToEditor(text: "Important"))
        f.confirmAnswer = false
        f.shownEditors.last?.perform(.close)
        XCTAssertEqual(f.confirms, 1)
        XCTAssertEqual(f.service.presentedPanel, .editor, "Go Back keeps the note open")
        f.confirmAnswer = true
        f.shownEditors.last?.perform(.close)
        XCTAssertNil(f.service.presentedPanel)
        XCTAssertEqual(f.files(), [])

        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        store.update { $0.confirmBeforeClosing = false }
        let quiet = try Fixture(settingsStore: store)
        quiet.service.open(date: date)
        quiet.service.notePanel?.text = "Typed but not saved"
        quiet.service.handleNoteAction(.close)
        XCTAssertEqual(quiet.confirms, 0)
        XCTAssertNil(quiet.service.presentedPanel)
    }

    func testCopyFailureSavesAndKeepsTheNoteOpenForRetry() throws {
        let f = try Fixture()
        f.service.open(date: date)
        f.acceptsClipboard = false
        f.service.handleNoteAction(.copyAndSave(text: "Keep this note"))
        XCTAssertEqual(f.errors, ["Couldn't copy note"])
        XCTAssertEqual(f.service.presentedPanel, .note, "Clipboard failure must leave the note available for retry")
        XCTAssertEqual(f.files(), [defaultName + ".png"], "The save itself went through")

        f.acceptsClipboard = true
        f.service.handleNoteAction(.copyAndSave(text: "Keep this note"))
        XCTAssertEqual(f.copied, [f.desktop.appendingPathComponent(defaultName + ".png")])
        XCTAssertEqual(f.files(), [defaultName + ".png"], "The retry saves over the same file")
        XCTAssertNil(f.service.presentedPanel)
    }
}

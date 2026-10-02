import XCTest
import AppKit
@testable import Zoomies

@MainActor
final class ScratchpadServiceTests: XCTestCase {
    @MainActor private final class Fixture {
        let root: URL
        var presented: [InkNoteWindowController] = []
        var copied: [URL] = []
        var acceptsClipboard = true
        var service: ScratchpadService!
        init() throws {
            _ = NSApplication.shared
            root = try TestSupport.makeTemporaryDirectory()
            let clipboard = ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { [unowned self] objects in
                guard acceptsClipboard else { return false }
                copied.append(objects[0] as! URL); return true
            })
            service = ScratchpadService(clipboardService: clipboard, desktopDirectory: root.appendingPathComponent("desktop"),
                                        present: { [unowned self] in presented.append($0) })
        }
        deinit { TestSupport.removeIfExists(root) }
    }

    private var date: Date { Date(timeIntervalSince1970: 1_790_000_000) }

    func testNewNoteIsADrawablePNGNoteAndNeverMarkdown() throws {
        let f = try Fixture()
        var opened: [InkNoteWindowController] = []
        f.service.onOpen = { opened.append($0) }
        let editor = f.service.open(date: date)
        defer { editor.window?.close() }
        XCTAssertTrue(f.presented == [editor] && opened == [editor])
        XCTAssertEqual(editor.noteURL.deletingLastPathComponent().lastPathComponent, "desktop")
        XCTAssertEqual(editor.noteURL.lastPathComponent, ScratchpadFilenameLogic.defaultBaseName(date: date) + ".png")
        XCTAssertEqual(editor.textView.string, "")
        XCTAssertFalse(editor.hasUnsavedChanges, "An untouched note closes without asking and leaves no file")
        XCTAssertFalse(f.service.isBusyForUserCommands)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("desktop").path))
    }

    func testSavingWritesOnlyThePNGAndCopyPutsItOnTheClipboard() throws {
        let f = try Fixture()
        let editor = f.service.open(date: date)
        defer { editor.window?.close() }
        editor.textView.insertText("Fix the label clipping.", replacementRange: NSRange(location: 0, length: 0))
        editor.copyAndSave()
        XCTAssertEqual(f.copied, [editor.noteURL])
        let files = try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("desktop").path)
        XCTAssertEqual(files, [editor.noteURL.lastPathComponent])
        let note = try XCTUnwrap(PNGMetadata.extractInkNote(fromPNG: Data(contentsOf: editor.noteURL)))
        XCTAssertEqual(note.text, "Fix the label clipping.")
    }

    func testNotesOpenedInTheSameSecondGetSeparateFiles() throws {
        let f = try Fixture()
        let first = f.service.open(date: date)
        let second = f.service.open(date: date)
        defer { first.window?.close(); second.window?.close() }
        XCTAssertNotEqual(first.noteURL, second.noteURL)
        XCTAssertEqual(second.noteURL.pathExtension, "png")
    }

    func testCopyFailureSavesKeepsTheNoteOpenAndAllowsRetry() throws {
        let f = try Fixture()
        let runner = AlertPresenter.modalRunner
        let activator = AlertPresenter.appActivator
        defer { AlertPresenter.modalRunner = runner; AlertPresenter.appActivator = activator }
        var warnings: [String] = []
        AlertPresenter.appActivator = {}
        AlertPresenter.modalRunner = { warnings.append($0.messageText); return .alertFirstButtonReturn }
        let editor = f.service.open(date: date)
        defer { editor.window?.close() }
        var closed = false
        editor.onClose = { closed = true }
        editor.textView.insertText("Keep this note", replacementRange: NSRange(location: 0, length: 0))
        f.acceptsClipboard = false

        editor.copyAndSave()

        XCTAssertEqual(warnings, ["Cannot Copy Note"])
        XCTAssertFalse(closed, "Clipboard failure must leave the note available for retry")
        XCTAssertTrue(f.copied.isEmpty)
        XCTAssertFalse(editor.hasUnsavedChanges, "The successful save is retained")
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: try Data(contentsOf: editor.noteURL))?.text, "Keep this note")

        f.acceptsClipboard = true
        editor.copyAndSave()
        XCTAssertEqual(f.copied, [editor.noteURL])
        XCTAssertTrue(closed)
        XCTAssertEqual(warnings.count, 1)
    }
}

import AppKit
import XCTest
@testable import Zoomies

final class ScratchpadWorkflowTests: XCTestCase {
    private final class Fixture {
        let root: URL
        var notes: [DedicatedNotePanelController] = []
        var renames: [RenamePanelController] = []
        var copied: [URL] = []
        var errors: [String] = []
        var service: ScratchpadService!
        init() throws {
            root = try TestSupport.makeTemporaryDirectory()
            service = ScratchpadService(
                clipboardService: ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { [unowned self] objects in
                    copied.append(objects[0] as! URL); return true
                }), desktopDirectory: root.appendingPathComponent("notes"),
                showNote: { [unowned self] in notes.append($0) },
                showRename: { [unowned self] in renames.append($0) },
                errorPresenter: { [unowned self] title, _ in errors.append(title) })
        }
        deinit { TestSupport.removeIfExists(root) }
    }
    func testReturningThroughRenamePreservesTextAndCopiesActualSavedFile() throws {
        let f = try Fixture()
        f.service.open()
        XCTAssertTrue(f.service.isBusyForUserCommands)
        XCTAssertEqual(f.service.presentedPanel, .note)
        f.service.open()
        XCTAssertTrue(f.notes[0] === f.notes[1])
        f.service.handleNoteAction(.backToRename(text: "first\nΔ note"))
        XCTAssertEqual(f.service.presentedPanel, .rename)
        f.service.open()
        XCTAssertTrue(f.renames[0] === f.renames[1])
        f.service.handleRenameAction(.copyAndSave(newName: "My note.md"))
        XCTAssertFalse(f.service.isBusyForUserCommands)
        XCTAssertNil(f.service.presentedPanel)
        let file = f.root.appendingPathComponent("notes/My note.md")
        XCTAssertEqual(f.copied, [file])
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "first\nΔ note")
        XCTAssertTrue(f.errors.isEmpty)
    }

    func testRenamingThenReturningToNoteSavesNewestText() throws {
        let f = try Fixture()
        f.service.open()
        f.service.handleNoteAction(.backToRename(text: "old"))
        f.service.handleRenameAction(.goToNote(newName: "renamed.md"))
        XCTAssertEqual(f.service.presentedPanel, .note)
        f.service.handleNoteAction(.save(text: "new"))
        XCTAssertEqual(try String(contentsOf: f.root.appendingPathComponent("notes/renamed.md"), encoding: .utf8), "new")
        XCTAssertTrue(f.copied.isEmpty)
        XCTAssertFalse(f.service.isBusyForUserCommands)
    }

    func testNoteCopyAndSavePublishesReadableMarkdownAndNewFlowResetsText() throws {
        let f = try Fixture()
        f.service.open()
        f.service.handleNoteAction(.copyAndSave(text: "copied text"))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(f.copied.first), encoding: .utf8), "copied text")
        f.service.open()
        f.service.handleNoteAction(.backToRename(text: ""))
        f.service.handleRenameAction(.save(newName: "empty"))
        XCTAssertEqual(try String(contentsOf: f.root.appendingPathComponent("notes/empty.md"), encoding: .utf8), "")
    }

    func testSaveFailureKeepsDraftAvailableForRetry() throws {
        let f = try Fixture()
        let blocked = f.root.appendingPathComponent("notes")
        try Data("blocker".utf8).write(to: blocked)
        f.service.open()
        f.service.handleNoteAction(.backToRename(text: "retained draft"))
        f.service.handleRenameAction(.save(newName: "draft"))
        XCTAssertEqual(f.errors, ["Couldn't save note"])
        XCTAssertTrue(f.service.isBusyForUserCommands)
        XCTAssertEqual(f.service.presentedPanel, .rename)
        try FileManager.default.removeItem(at: blocked)
        f.service.handleRenameAction(.save(newName: "draft"))
        XCTAssertEqual(try String(contentsOf: blocked.appendingPathComponent("draft.md"), encoding: .utf8), "retained draft")
        XCTAssertFalse(f.service.isBusyForUserCommands)
    }

    func testUnsupportedActionsAndCancellationNeverWriteFiles() throws {
        let f = try Fixture()
        f.service.open()
        f.service.handleNoteAction(.copyAndDelete(text: "discard"))
        f.service.handleNoteAction(.delete)
        f.service.handleNoteAction(.goToEditor(text: "discard"))
        XCTAssertEqual(f.service.presentedPanel, .note)
        f.service.handleNoteAction(.close)
        XCTAssertFalse(f.service.isBusyForUserCommands)
        f.service.open()
        f.service.handleNoteAction(.backToRename(text: "discard"))
        f.service.handleRenameAction(.copyAndDelete(newName: "discard"))
        XCTAssertEqual(f.service.presentedPanel, .rename)
        f.service.handleRenameAction(.close)
        f.service.open()
        f.service.handleNoteAction(.backToRename(text: "discard"))
        f.service.handleRenameAction(.delete)
        XCTAssertFalse(f.service.isBusyForUserCommands)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("notes").path))
        XCTAssertTrue(f.copied.isEmpty)
    }
}

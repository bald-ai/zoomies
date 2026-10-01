import AppKit
import XCTest
@testable import Zoomies

@MainActor
final class MarkdownEditorTests: XCTestCase {
    private func editor(_ text: String) throws -> (MarkdownEditorWindowController, URL) {
        _ = NSApplication.shared
        let root = try TestSupport.makeTemporaryDirectory()
        let url = root.appendingPathComponent("plan.md")
        try Data(text.utf8).write(to: url)
        return (try MarkdownEditorWindowController(url: url), root)
    }
    func testAttachmentDeletionUndoAndRedoKeepNoteTogether() throws {
        let (editor, root) = try editor("hello[^1]\n\n[^1]: note\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        XCTAssertEqual(editor.textView.string, "hello\u{fffc}")
        editor.textView.setSelectedRange(NSRange(location: 5, length: 1))
        editor.textView.deleteBackward(nil)
        XCTAssertEqual(editor.mainText, "hello")
        XCTAssertNil(editor.notes[1])
        editor.textView.history.undo()
        XCTAssertEqual(editor.mainText, "hello[^1]")
        XCTAssertEqual(editor.notes[1], "note")
        XCTAssertFalse(editor.hasUnsavedChanges)
        editor.textView.history.redo()
        XCTAssertEqual(editor.mainText, "hello")
        XCTAssertNil(editor.notes[1])
    }
    func testCutClipboardAndPasteMoveMarkerWithoutDuplicates() throws {
        let (editor, root) = try editor("hello[^1]\n\n[^1]: note")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.textView.setSelectedRange(NSRange(location: 5, length: 1))
        editor.textView.cut(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "[^1]")
        XCTAssertEqual(editor.notes[1], "note")
        XCTAssertTrue(editor.anchorNumbers.isEmpty)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.paste(nil)
        XCTAssertEqual(editor.textView.string, "\u{fffc}hello")
        XCTAssertEqual(editor.mainText, "[^1]hello")
        editor.textView.paste(nil)
        XCTAssertEqual(editor.textView.string, "\u{fffc}[^1]hello")
        editor.textView.history.undo()
        editor.textView.history.undo()
        XCTAssertTrue(editor.anchorNumbers.isEmpty)
        XCTAssertEqual(editor.notes[1], "note")
        editor.textView.history.undo()
        XCTAssertEqual(editor.mainText, "hello[^1]")
    }
    func testNewMarkerCancelCommitAndEmptyNoteAreAtomicUndoSteps() throws {
        let (editor, root) = try editor("hello")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.window?.orderFront(nil)
        editor.textView.setSelectedRange(NSRange(location: 1, length: 3))
        editor.insertMarker()
        XCTAssertEqual(editor.mainText, "hell[^1]o")
        editor.cancelPopover()
        XCTAssertEqual(editor.mainText, "hello")
        XCTAssertFalse(editor.hasUnsavedChanges)
        editor.insertMarker()
        editor.commitMarkerNote("first\nsecond")
        XCTAssertEqual(editor.notes[1], "first second")
        editor.textView.history.undo()
        XCTAssertEqual(editor.mainText, "hello")
        XCTAssertTrue(editor.notes.isEmpty)
        editor.textView.history.redo()
        XCTAssertEqual(editor.mainText, "hell[^1]o")
        XCTAssertEqual(editor.notes[1], "first second")
        // An empty newly inserted note removes only that new marker.
        editor.insertMarker()
        editor.commitMarkerNote("")
        XCTAssertEqual(editor.mainText, "hell[^1]o")
        XCTAssertEqual(editor.notes, [1: "first second"])
    }

    func testChangedOnDiskCancelReloadAndOverwrite() throws {
        let (editor, root) = try editor("old")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        let runner = AlertPresenter.modalRunner
        let activator = AlertPresenter.appActivator
        defer { AlertPresenter.modalRunner = runner; AlertPresenter.appActivator = activator }
        AlertPresenter.appActivator = {}
        try Data("agent update".utf8).write(to: editor.url)
        AlertPresenter.modalRunner = { alert in
            XCTAssertEqual(alert.messageText, "File changed on disk")
            XCTAssertEqual(alert.buttons.map(\.title), ["Overwrite", "Reload", "Cancel"])
            return .alertThirdButtonReturn
        }
        XCTAssertFalse(editor.save())
        XCTAssertEqual(try String(contentsOf: editor.url), "agent update")
        AlertPresenter.modalRunner = { _ in .alertSecondButtonReturn }
        XCTAssertTrue(editor.save())
        XCTAssertEqual(editor.mainText, "agent update")
        XCTAssertFalse(editor.hasUnsavedChanges)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.insertText("my ", replacementRange: NSRange(location: NSNotFound, length: 0))
        try Data("another update".utf8).write(to: editor.url)
        AlertPresenter.modalRunner = { _ in .alertFirstButtonReturn }
        XCTAssertTrue(editor.save())
        XCTAssertEqual(try String(contentsOf: editor.url), "my agent update")
    }

    func testPasteReplacingSelectedCirclePreservesItsNote() throws {
        let (editor, root) = try editor("hello[^1]\n\n[^1]: note")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.textView.setSelectedRange(NSRange(location: 5, length: 1))
        editor.textView.copy(nil)
        editor.textView.paste(nil)
        XCTAssertEqual(editor.textView.string, "hello\u{fffc}")
        XCTAssertEqual(editor.notes[1], "note")
    }

    func testUnchangedSavePreservesPlainBytesAndAnchorSpelling() throws {
        for text in ["body\r\n\r\n", "body[^1]\r\n\r\n[^1]: note\r\n", "body[^01]\n\n[^1]: note\n", "[^foo]\n\n[^foo]: named"] {
            let (editor, root) = try editor(text)
            defer { editor.window?.close(); TestSupport.removeIfExists(root) }
            XCTAssertTrue(editor.save())
            XCTAssertEqual(try Data(contentsOf: editor.url), Data(text.utf8))
            XCTAssertFalse(editor.hasUnsavedChanges)
        }
    }
    func testAnchorWithoutDefinitionAndOrphanNoteAppearInModel() throws {
        let (editor, root) = try editor("body[^1]\n\n[^9]: orphan")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        XCTAssertEqual(editor.notes, [9: "orphan"])
        XCTAssertEqual(editor.anchorNumbers, [1])
        XCTAssertTrue(editor.save())
        XCTAssertEqual(try String(contentsOf: editor.url, encoding: .utf8), "body[^1]\n\n[^9]: orphan")
    }
    func testSaveKeepsFootnotesDefinedOutsideTrailingBlock() throws {
        let text = "text[^1]\n[^1]: source\n"
        let (editor, root) = try editor(text)
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        XCTAssertTrue(editor.save())
        XCTAssertEqual(try String(contentsOf: editor.url, encoding: .utf8), text)
    }
    func testSaveRecreatesFileRemovedFromDisk() throws {
        let (editor, root) = try editor("body\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.textView.insertText("more ", replacementRange: NSRange(location: 0, length: 0))
        try FileManager.default.removeItem(at: editor.url)
        XCTAssertTrue(editor.save())
        XCTAssertEqual(try String(contentsOf: editor.url, encoding: .utf8), "more body\n")
    }
}

import AppKit
import XCTest
@testable import Zoomies

final class VideoRenameWorkflowControllerTests: XCTestCase {
    func testStartConfiguresHiddenRenamePanelAndRoutesItsSaveCallback() throws {
        _ = NSApplication.shared
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let file = root.appendingPathComponent("recording.mp4")
        try Data("video fixture".utf8).write(to: file)
        var panel: RenamePanelController?
        var finishes = 0
        let workflow = VideoRenameWorkflowController(fileURL: file,
            settingsStore: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
            clipboardService: ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { _ in true }),
            errorPresenter: { _, _ in XCTFail("Unexpected error") }, presentPanel: { panel = $0 })
        workflow.onFinish = { finishes += 1 }
        workflow.start()
        let shown = try XCTUnwrap(panel)
        XCTAssertFalse(try XCTUnwrap(shown.window).isVisible)
        XCTAssertTrue(workflow.isBusyForUserCommands)
        shown.onAction?(.save(newName: "renamed"))
        XCTAssertEqual(finishes, 1)
        XCTAssertFalse(workflow.isBusyForUserCommands)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("renamed.mp4")), Data("video fixture".utf8))
    }

    func testDeleteConfirmationReturnsTheInjectedModalDecision() {
        _ = NSApplication.shared
        let activate = AlertPresenter.appActivator
        let modal = AlertPresenter.modalRunner
        defer { AlertPresenter.appActivator = activate; AlertPresenter.modalRunner = modal }
        AlertPresenter.appActivator = {}
        AlertPresenter.modalRunner = { alert in
            XCTAssertEqual(alert.messageText, "Delete this recording?")
            return .alertSecondButtonReturn
        }
        XCTAssertFalse(VideoRenameWorkflowController.defaultDeleteConfirmation())
        AlertPresenter.modalRunner = { _ in .alertFirstButtonReturn }
        XCTAssertTrue(VideoRenameWorkflowController.defaultDeleteConfirmation())
        XCTAssertTrue(VideoRenameWorkflowController.defaultDeleteConfirmation(confirmBeforeClosing: false))
    }

    private final class Fixture {
        let root: URL
        let original: URL
        let bytes = Data("controlled video bytes".utf8)
        var published: [URL] = []
        var errors: [String] = []
        var messages: [String] = []
        var finishes = 0
        var acceptsCopy = true
        var confirmsDelete = true
        var failsDelete = false
        var workflow: VideoRenameWorkflowController!

        init() throws {
            root = try TestSupport.makeTemporaryDirectory()
            original = root.appendingPathComponent("original.mp4")
            try bytes.write(to: original)
            let clipboard = ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { [unowned self] objects in
                published.append(objects[0] as! URL)
                return acceptsCopy
            })
            workflow = VideoRenameWorkflowController(fileURL: original,
                settingsStore: SettingsStore(fileURL: root.appendingPathComponent("settings.json")),
                clipboardService: clipboard,
                errorPresenter: { [unowned self] title, message in
                    errors.append(title)
                    messages.append(message)
                },
                deleteConfirmer: { [unowned self] in confirmsDelete },
                removeFile: { [unowned self] url in
                    if failsDelete { throw NSError(domain: "controlled delete", code: 1) }
                    try FileManager.default.removeItem(at: url)
                })
            workflow.onFinish = { [unowned self] in finishes += 1 }
        }
        deinit { TestSupport.removeIfExists(root) }
    }

    func testSaveSanitizesNamePreservesExtensionAndNeverOverwritesCollision() throws {
        let f = try Fixture()
        let collision = f.root.appendingPathComponent("clip.mp4")
        try Data("existing".utf8).write(to: collision)
        f.workflow.handleRenameAction(.save(newName: " clip.mp4 "))
        XCTAssertEqual(try Data(contentsOf: collision), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: f.root.appendingPathComponent("clip_2.mp4")), f.bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.original.path))
        XCTAssertFalse(f.workflow.isBusyForUserCommands)
        XCTAssertEqual(f.finishes, 1)
        f.workflow.handleRenameAction(.delete)
        XCTAssertEqual(f.finishes, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: collision.path))
    }

    func testBlankAndUnchangedNamesKeepOriginal() throws {
        for name in [" \n", "original.mp4"] {
            let f = try Fixture()
            f.workflow.handleRenameAction(.save(newName: name))
            XCTAssertEqual(try Data(contentsOf: f.original), f.bytes)
            XCTAssertEqual(f.finishes, 1)
        }
    }

    func testRenameFailureLeavesWorkflowOpenWithoutCopying() throws {
        let f = try Fixture()
        try FileManager.default.removeItem(at: f.original)
        f.workflow.handleRenameAction(.copyAndSave(newName: "new"))
        XCTAssertEqual(f.errors, ["Rename failed"])
        XCTAssertTrue(f.published.isEmpty)
        XCTAssertEqual(f.finishes, 0)
        XCTAssertTrue(f.workflow.isBusyForUserCommands)
    }

    func testCopyAndSaveFailureKeepsRenamedFileAndAllowsRetry() throws {
        let f = try Fixture()
        f.acceptsCopy = false
        f.workflow.handleRenameAction(.copyAndSave(newName: "renamed"))
        let renamed = f.root.appendingPathComponent("renamed.mp4")
        XCTAssertEqual(try Data(contentsOf: renamed), f.bytes)
        XCTAssertEqual(f.errors, ["Copy failed"])
        XCTAssertEqual(f.messages, ["Zoomies couldn't copy the recording to the clipboard, but your save was kept. You can try Copy + Save again."])
        XCTAssertEqual(f.finishes, 0)
        f.acceptsCopy = true
        f.workflow.handleRenameAction(.copyAndSave(newName: "renamed"))
        XCTAssertEqual(f.published, [renamed, renamed])
        XCTAssertEqual(f.finishes, 1)
        XCTAssertEqual(try Data(contentsOf: renamed), f.bytes)
    }

    func testCopyAndDeleteFailurePreservesOriginalThenPublishesDurableCopyBeforeDeleting() throws {
        let f = try Fixture()
        f.acceptsCopy = false
        f.workflow.handleRenameAction(.copyAndDelete(newName: "original"))
        XCTAssertEqual(try Data(contentsOf: f.original), f.bytes)
        XCTAssertEqual(f.finishes, 0)
        XCTAssertEqual(f.errors, ["Copy failed"])
        XCTAssertEqual(f.messages, ["Zoomies couldn’t copy the recording to the clipboard, so the original file was left in place. You can try Copy + Delete again."])
        f.acceptsCopy = true
        f.workflow.handleRenameAction(.copyAndDelete(newName: "original"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.original.path))
        let cached = try XCTUnwrap(f.published.last)
        XCTAssertNotEqual(cached, f.original)
        XCTAssertEqual(try Data(contentsOf: cached), f.bytes)
        XCTAssertEqual(f.finishes, 1)
    }

    func testDeleteRetryReusesPublishedCopyUnlessCacheDisappears() throws {
        for removeCache in [false, true] {
            let f = try Fixture()
            f.failsDelete = true
            let action = RenamePanelAction.copyAndDelete(newName: "original")
            f.workflow.handleRenameAction(action)
            XCTAssertEqual(f.errors, ["Couldn't delete recording"])
            XCTAssertEqual(try Data(contentsOf: f.original), f.bytes)
            XCTAssertEqual(f.finishes, 0)
            if removeCache { try FileManager.default.removeItem(at: XCTUnwrap(f.published.first)) }
            f.failsDelete = false
            f.workflow.handleRenameAction(action)
            XCTAssertEqual(f.published.count, removeCache ? 2 : 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(f.published.last)), f.bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.original.path))
            XCTAssertEqual(f.finishes, 1)
        }
    }

    func testDeleteCancellationAndFailureKeepFileAndWorkflowOpen() throws {
        let f = try Fixture()
        f.confirmsDelete = false
        f.workflow.handleRenameAction(.delete)
        XCTAssertEqual(try Data(contentsOf: f.original), f.bytes)
        XCTAssertEqual(f.finishes, 0)
        f.confirmsDelete = true
        f.failsDelete = true
        f.workflow.handleRenameAction(.delete)
        XCTAssertEqual(f.errors, ["Couldn't delete recording"])
        XCTAssertEqual(f.finishes, 0)
        f.failsDelete = false
        f.workflow.handleRenameAction(.delete)
        XCTAssertEqual(f.finishes, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.original.path))
    }

    func testAlreadyMissingFileDeleteFinishesAndCloseNeverDeletes() throws {
        let f = try Fixture()
        f.workflow.handleRenameAction(.goToNote(newName: "ignored"))
        XCTAssertEqual(f.finishes, 0)
        f.workflow.handleRenameAction(.close)
        XCTAssertEqual(try Data(contentsOf: f.original), f.bytes)
        XCTAssertEqual(f.finishes, 1)
        let missing = try Fixture()
        try FileManager.default.removeItem(at: missing.original)
        missing.workflow.handleRenameAction(.delete)
        XCTAssertEqual(missing.finishes, 1)
        XCTAssertTrue(missing.errors.isEmpty)
    }
}

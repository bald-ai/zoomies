import AppKit
import XCTest
@testable import Zoomies

final class ScreenshotNavigationTests: XCTestCase {
    private final class Fixture {
        let root: URL
        let original: URL
        let originalBytes: Data
        var renames: [RenamePanelController] = []
        var notes: [ScreenshotNotePanelController] = []
        var editors: [EditorWindowController] = []
        var finishes = 0
        var errors: [String] = []
        var failsWrite = false
        var workflow: ScreenshotWorkflowController!
        init() throws {
            root = try TestSupport.makeTemporaryDirectory()
            original = root.appendingPathComponent("original.png")
            originalBytes = try TestSupport.noiseImagePNGData(width: 40, height: 30)
            try originalBytes.write(to: original)
            let settings = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            settings.update { $0.notePrefixEnabled = false; $0.confirmBeforeClosing = false }
            workflow = ScreenshotWorkflowController(fileURL: original,
                settingsStore: settings,
                clipboardService: ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { _ in true }),
                backupService: BackupService(backupsDirectory: root.appendingPathComponent("backups")),
                sourceScreen: nil, escapeKeyDeletesFile: false,
                imageDataWriter: { [unowned self] data, output, original in
                    if failsWrite { throw NSError(domain: "write fixture", code: 1) }
                    return try WorkflowImagePersistenceLogic.writeEncodedImageData(data, to: output, originalURL: original)
                }, errorPresenter: { [unowned self] title, _ in errors.append(title) },
                deleteConfirmer: { true },
                presentation: .init(rename: { [unowned self] in renames.append($0) },
                                    note: { [unowned self] in notes.append($0) },
                                    editor: { [unowned self] in editors.append($0) }))
            workflow.onFinish = { [unowned self] in finishes += 1 }
        }
        deinit { workflow.cancel(); TestSupport.removeIfExists(root) }
    }

    func testRenameNoteEditorReturnAndSaveRoundTripWithoutPresentingWindows() throws {
        let f = try Fixture()
        f.workflow.start()
        XCTAssertEqual(f.renames.count, 1)
        f.renames.last?.onAction?(.goToNote(newName: "renamed"))
        XCTAssertEqual(f.notes.count, 1)
        f.notes.last?.onAction?(.goToEditor(text: "first prompt"))
        let editor = try XCTUnwrap(f.editors.last)
        let canvas = try XCTUnwrap(findCanvas(editor.window?.contentView))
        canvas.setTool(.rectangle)
        canvas.mouseDown(with: mouse(.leftMouseDown, canvas: canvas, x: 15, y: 15))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, canvas: canvas, x: 30, y: 25))
        canvas.mouseUp(with: mouse(.leftMouseUp, canvas: canvas, x: 30, y: 25))
        XCTAssertEqual(editor.currentEditableState()?.items.count, 1)
        editor.onBackToNote?()
        XCTAssertEqual(f.notes.count, 2)
        f.notes.last?.onAction?(.backToRename(text: "revised prompt"))
        XCTAssertEqual(f.renames.count, 2)
        f.renames.last?.onAction?(.save(newName: "renamed"))
        XCTAssertEqual(f.finishes, 1)
        let bytes = try Data(contentsOf: f.root.appendingPathComponent("renamed.png"))
        let state = try XCTUnwrap(PNGMetadata.extractEditorState(fromPNG: bytes))
        XCTAssertEqual(state.items.count, 1)
        let restoredBase = try XCTUnwrap(NSBitmapImageRep(data: state.baseImagePNG))
        let originalBase = try XCTUnwrap(NSBitmapImageRep(data: f.originalBytes))
        XCTAssertEqual(restoredBase.pixelsWide, originalBase.pixelsWide)
        XCTAssertEqual(restoredBase.pixelsHigh, originalBase.pixelsHigh)
        for y in 0..<originalBase.pixelsHigh {
            for x in 0..<originalBase.pixelsWide {
                let expected = try XCTUnwrap(originalBase.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let actual = try XCTUnwrap(restoredBase.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 1.0 / 255)
                XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 1.0 / 255)
                XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 1.0 / 255)
                XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 1.0 / 255)
            }
        }
        let reopen = WorkflowReopenMetadataLogic.resolve(fileData: bytes)
        XCTAssertEqual(reopen.prompt, "revised prompt")
        XCTAssertTrue(f.errors.isEmpty)
        XCTAssertTrue(f.renames.allSatisfy { $0.window?.isVisible == false })
        XCTAssertTrue(f.notes.allSatisfy { $0.window?.isVisible == false })
        XCTAssertTrue(f.editors.allSatisfy { $0.window?.isVisible == false })
    }

    @MainActor
    func testEditorSaveFailureReopensDraftAndRetryFinishesWithNoteAndState() async throws {
        let f = try Fixture()
        f.workflow.handleNoteAction(.goToEditor(text: "keep note"))
        let editor = try XCTUnwrap(f.editors.last)
        let state = try XCTUnwrap(editor.currentEditableState())
        f.failsWrite = true
        editor.onComplete?(editor.currentCompositeImage(), .saveOnly, state)
        XCTAssertEqual(f.finishes, 0)
        for _ in 0..<100 {
            if f.editors.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(f.editors.count, 2)
        XCTAssertFalse(f.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: f.original), f.originalBytes)
        f.failsWrite = false
        let retry = try XCTUnwrap(f.editors.last)
        retry.onComplete?(retry.currentCompositeImage(), .saveOnly, retry.currentEditableState())
        XCTAssertEqual(f.finishes, 1)
        let reopened = WorkflowReopenMetadataLogic.resolve(fileData: try Data(contentsOf: f.original))
        XCTAssertEqual(reopened.prompt, "keep note")
        XCTAssertNotNil(reopened.editorState)
    }

    func testEditorCloseAndWorkflowCancellationPreserveOriginalAndIgnoreLateActions() throws {
        let f = try Fixture()
        f.workflow.handleNoteAction(.goToEditor(text: "discard note"))
        f.editors.last?.onComplete?(nil, .closeOnly, nil)
        XCTAssertEqual(f.finishes, 1)
        XCTAssertEqual(try Data(contentsOf: f.original), f.originalBytes)
        f.workflow.handleRenameAction(.delete)
        XCTAssertEqual(try Data(contentsOf: f.original), f.originalBytes)
        let cancelled = try Fixture()
        cancelled.workflow.start()
        cancelled.workflow.cancel()
        cancelled.renames.last?.onAction?(.delete)
        XCTAssertEqual(cancelled.finishes, 0)
        XCTAssertEqual(try Data(contentsOf: cancelled.original), cancelled.originalBytes)
    }

    private func findCanvas(_ view: NSView?) -> EditorCanvasView? {
        if let canvas = view as? EditorCanvasView { return canvas }
        for child in view?.subviews ?? [] {
            if let found = findCanvas(child) { return found }
        }
        return nil
    }
    private func mouse(_ type: NSEvent.EventType, canvas: EditorCanvasView, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: x, y: y), to: nil),
                          modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                          eventNumber: 0, clickCount: 1, pressure: 0)!
    }
}

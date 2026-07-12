import AppKit
import XCTest
@testable import Zoomies

final class EditorWindowControllerTests: XCTestCase {
    func testEditableStateUsesCleanBaseInsteadOfPendingComposite() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let basePNG = try TestSupport.solidImagePNGData(width: 100, height: 80, color: .systemBlue)
        let state = EditorCanvasState(baseImagePNG: basePNG, items: [
            .arrow(start: .init(NSPoint(x: 30, y: 40)), end: .init(NSPoint(x: 70, y: 40)),
                   color: .init(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 0.5)), lineWidth: 4)
        ])
        let baseImage = try XCTUnwrap(NSImage(data: basePNG))
        let sourceCanvas = EditorCanvasView(image: baseImage, initialState: state)
        let pendingComposite = sourceCanvas.compositeImage()
        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )

        let controller = EditorWindowController(image: pendingComposite,
                                                settingsStore: settingsStore,
                                                initialState: state)
        defer { controller.dismissWithoutCompletion() }

        let expected = try color(in: pendingComposite, at: NSPoint(x: 26, y: 16))
        let actual = try color(in: controller.currentCompositeImage(), at: NSPoint(x: 26, y: 16))
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.02)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.02)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.02)
    }

    func testRedCloseDeletesNewScreenshotLikeEscape() throws {
        try assertRedCloseAction(escapeKeyDeletesFile: true) { action in
            guard case .deleteOnly = action else {
                return XCTFail("Expected red close to delete a new screenshot")
            }
        }
    }

    func testRedCloseDiscardsEditsToExistingImageLikeEscape() throws {
        try assertRedCloseAction(escapeKeyDeletesFile: false) { action in
            guard case .closeOnly = action else {
                return XCTFail("Expected red close to discard edits without deleting the original")
            }
        }
    }

    private func assertRedCloseAction(
        escapeKeyDeletesFile: Bool,
        verify: (ScreenshotWorkflowController.FinalAction) -> Void
    ) throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: TestSupport.solidImage(),
            settingsStore: settingsStore,
            escapeKeyDeletesFile: escapeKeyDeletesFile
        )
        var receivedAction: ScreenshotWorkflowController.FinalAction?
        controller.onComplete = { _, action, _ in
            receivedAction = action
        }

        controller.window?.close()

        guard let receivedAction else {
            return XCTFail("Expected closing the editor window to complete the workflow")
        }
        verify(receivedAction)
    }

    private func color(in image: NSImage, at point: NSPoint) throws -> NSColor {
        let rep = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        return try XCTUnwrap(rep.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.deviceRGB))
    }
}

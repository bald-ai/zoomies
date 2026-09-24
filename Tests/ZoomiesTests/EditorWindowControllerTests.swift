import AppKit
import Carbon
import XCTest
@testable import Zoomies

final class EditorWindowControllerTests: XCTestCase {
    func testScrollIsLockedWhenCanvasFitsAndZoomedViewportCanPan() throws {
        _ = NSApplication.shared
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let controller = EditorWindowController(image: TestSupport.solidImage(width: 100, height: 80),
            settingsStore: SettingsStore(fileURL: root.appendingPathComponent("settings.json")))
        defer { controller.dismissWithoutCompletion() }
        let canvas = try XCTUnwrap(findCanvas(in: controller.window?.contentView))
        let scroll = try XCTUnwrap(canvas.enclosingScrollView)
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0))
        let event = try XCTUnwrap(NSEvent(cgEvent: cg))
        let initial = scroll.contentView.bounds.origin
        scroll.scrollWheel(with: event)
        XCTAssertEqual(scroll.contentView.bounds.origin, initial)
        let initialMagnification = scroll.magnification
        for _ in 0..<10 { canvas.onKeyCommand?(.zoomIn) }
        XCTAssertGreaterThan(scroll.magnification, initialMagnification)
        let zoomed = scroll.contentView.bounds.origin
        scroll.scrollWheel(with: event)
        XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.origin.y, zoomed.y)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testEditorFinalActionsDeliverImageAndEditableStateOnlyForSavingActions() throws {
        for action: ScreenshotFinalAction in [.saveOnly, .copyAndSave, .copyAndDelete, .deleteOnly, .closeOnly] {
            let root = try TestSupport.makeTemporaryDirectory()
            defer { TestSupport.removeIfExists(root) }
            let store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            store.update { $0.confirmBeforeClosing = true }
            let controller = EditorWindowController(image: TestSupport.solidImage(width: 100, height: 80), settingsStore: store)
            let canvas = try XCTUnwrap(findCanvas(in: controller.window?.contentView))
            drawStroke(on: canvas, from: NSPoint(x: 10, y: 20), to: NSPoint(x: 70, y: 20))
            var confirmed = false
            controller.onConfirmDelete = { confirmed }
            controller.onConfirmClose = { confirmed }
            var delivered: [ScreenshotFinalAction] = []
            controller.onComplete = { image, result, state in
                delivered.append(result)
                if result == .deleteOnly || result == .closeOnly {
                    XCTAssertNil(image)
                    XCTAssertNil(state)
                } else {
                    XCTAssertNotNil(image)
                    XCTAssertEqual(state?.items.count, 1)
                }
            }
            if action == .deleteOnly || action == .closeOnly {
                canvas.onKeyCommand?(.finalAction(action))
                XCTAssertTrue(delivered.isEmpty)
                XCTAssertEqual(controller.currentEditableState()?.items.count, 1)
            }
            confirmed = true
            canvas.onKeyCommand?(.finalAction(action))
            XCTAssertEqual(delivered, [action])
            XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
        }
    }

    func testMonitorUndoRedoOnlyConsumesEditorCommandKeysInItsOwnWindow() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let controller = EditorWindowController(image: TestSupport.solidImage(width: 100, height: 80),
            settingsStore: SettingsStore(fileURL: root.appendingPathComponent("settings.json")))
        defer { controller.dismissWithoutCompletion() }
        let canvas = try XCTUnwrap(findCanvas(in: controller.window?.contentView))
        drawStroke(on: canvas, from: NSPoint(x: 10, y: 20), to: NSPoint(x: 70, y: 20))
        let undo = try keyEvent(keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [.command], characters: "z")
        XCTAssertTrue(controller.handleMonitoredEvent(undo, isKeyWindow: false, isEditingText: false) === undo)
        XCTAssertTrue(controller.handleMonitoredEvent(undo, isKeyWindow: true, isEditingText: true) === undo)
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)
        XCTAssertNil(controller.handleMonitoredEvent(undo, isKeyWindow: true, isEditingText: false))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 0)
        let redo = try keyEvent(keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [.command, .shift], characters: "Z")
        XCTAssertNil(controller.handleMonitoredEvent(redo, isKeyWindow: true, isEditingText: false))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)
        for event in [try keyEvent(keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [], characters: "z"),
                      try keyEvent(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.command], characters: "a")] {
            XCTAssertTrue(controller.handleMonitoredEvent(event, isKeyWindow: true, isEditingText: false) === event)
        }
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)
        XCTAssertFalse(try XCTUnwrap(controller.window).isVisible)
    }

    func testWindowCommandUndoRedoAndNewStrokeInvalidatesRedo() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: TestSupport.solidImage(width: 100, height: 80),
            settingsStore: settingsStore
        )
        defer { controller.dismissWithoutCompletion() }

        let window = try XCTUnwrap(controller.window)
        let canvas = try XCTUnwrap(findCanvas(in: window.contentView))
        XCTAssertTrue(window.makeFirstResponder(canvas))

        drawStroke(on: canvas,
                   from: NSPoint(x: 10, y: 20),
                   to: NSPoint(x: 70, y: 20))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)

        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(
            keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [.command], characters: "z"
        )))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 0)

        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(
            keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [.command, .shift], characters: "Z"
        )))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)

        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(
            keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [.command], characters: "z"
        )))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 0)

        drawStroke(on: canvas,
                   from: NSPoint(x: 10, y: 50),
                   to: NSPoint(x: 70, y: 50))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)

        XCTAssertTrue(window.performKeyEquivalent(with: try keyEvent(
            keyCode: UInt16(kVK_ANSI_Z), modifierFlags: [.command, .shift], characters: "Z"
        )))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)
    }

    func testApplicationKeyDispatchRoutesUndoToVisibleEditor() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: TestSupport.solidImage(width: 100, height: 80),
            settingsStore: settingsStore
        )
        defer { controller.dismissWithoutCompletion() }
        controller.show()

        let window = try XCTUnwrap(controller.window)
        let canvas = try XCTUnwrap(findCanvas(in: window.contentView))
        drawStroke(on: canvas,
                   from: NSPoint(x: 10, y: 20),
                   to: NSPoint(x: 70, y: 20))
        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)

        NSApp.sendEvent(try keyEvent(
            keyCode: UInt16(kVK_ANSI_Z),
            modifierFlags: [.command],
            characters: "z",
            windowNumber: window.windowNumber
        ))

        XCTAssertEqual(controller.currentEditableState()?.items.count, 0)
    }

    func testToolbarRedoButtonRestoresUndoneStroke() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: TestSupport.solidImage(width: 100, height: 80),
            settingsStore: settingsStore
        )
        defer { controller.dismissWithoutCompletion() }

        let window = try XCTUnwrap(controller.window)
        let canvas = try XCTUnwrap(findCanvas(in: window.contentView))
        drawStroke(on: canvas,
                   from: NSPoint(x: 10, y: 20),
                   to: NSPoint(x: 70, y: 20))
        canvas.undo()
        XCTAssertEqual(controller.currentEditableState()?.items.count, 0)

        let redoButton = try XCTUnwrap(findButton(
            in: window.contentView,
            toolTip: "Redo (Cmd+Shift+Z)"
        ))
        redoButton.performClick(nil)

        XCTAssertEqual(controller.currentEditableState()?.items.count, 1)
    }

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

    func testRedCloseCancelledByConfirmationKeepsWindowOpen() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: TestSupport.solidImage(),
            settingsStore: settingsStore,
            escapeKeyDeletesFile: true
        )
        var completed = false
        var prompts = 0
        controller.onComplete = { _, _, _ in completed = true }
        controller.onConfirmDelete = { prompts += 1; return false }

        // performClose simulates a real red-X click (programmatic close()
        // skips the should-close query).
        controller.window?.performClose(nil)

        XCTAssertEqual(prompts, 1, "Cancelling must ask exactly once.")
        XCTAssertFalse(completed, "Cancelling must not complete the workflow, so the editor stays open.")
    }

    func testRedCloseConfirmedAsksOnceAndDeletes() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: TestSupport.solidImage(),
            settingsStore: settingsStore,
            escapeKeyDeletesFile: true
        )
        var receivedAction: ScreenshotFinalAction?
        var prompts = 0
        controller.onComplete = { _, action, _ in receivedAction = action }
        controller.onConfirmDelete = { prompts += 1; return true }

        controller.window?.performClose(nil)

        XCTAssertEqual(prompts, 1, "One red-close must ask exactly once.")
        guard let receivedAction else {
            return XCTFail("Expected closing the editor window to complete the workflow")
        }
        guard case .deleteOnly = receivedAction else {
            return XCTFail("Expected a confirmed red close to delete")
        }
    }

    private func assertRedCloseAction(
        escapeKeyDeletesFile: Bool,
        verify: (ScreenshotFinalAction) -> Void
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
        var receivedAction: ScreenshotFinalAction?
        controller.onComplete = { _, action, _ in
            receivedAction = action
        }

        controller.window?.close()

        guard let receivedAction else {
            return XCTFail("Expected closing the editor window to complete the workflow")
        }
        verify(receivedAction)
    }

    func testRedCloseDoesNotCompositeDiscardedEdits() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: TestSupport.solidImage(),
            settingsStore: settingsStore,
            escapeKeyDeletesFile: true
        )
        var receivedImage: NSImage?
        var receivedState: EditorCanvasState?
        var receivedAction: ScreenshotFinalAction?
        controller.onComplete = { image, action, state in
            receivedImage = image
            receivedState = state
            receivedAction = action
        }

        controller.window?.close()

        XCTAssertEqual(receivedAction, .deleteOnly)
        XCTAssertNil(receivedImage)
        XCTAssertNil(receivedState)
    }

    func testUnsafeInitialEditorStateUsesFlattenedImage() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }

        let flattenedPNG = try TestSupport.solidImagePNGData(width: 80, height: 40, color: .systemGreen)
        let flattened = try XCTUnwrap(NSImage(data: flattenedPNG))
        let basePNG = try TestSupport.solidImagePNGData(width: 80, height: 40, color: .systemBlue)
        let unsafe = EditorCanvasState(
            baseImagePNG: basePNG,
            items: [.arrow(start: .init(NSPoint(x: CGFloat.nan, y: 1)),
                           end: .init(NSPoint(x: 10, y: 10)),
                           color: .init(.systemRed),
                           lineWidth: 4)]
        )
        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: directory.appendingPathComponent("settings.json")
        )
        let controller = EditorWindowController(
            image: flattened,
            settingsStore: settingsStore,
            initialState: unsafe
        )
        defer { controller.dismissWithoutCompletion() }

        XCTAssertEqual(controller.currentEditableState()?.items.count, 0)
        XCTAssertEqual(controller.currentCompositeImage().size.width, 80, accuracy: 1.0)
        XCTAssertEqual(controller.currentCompositeImage().size.height, 40, accuracy: 1.0)
    }

    // MARK: - Annotation creation scale

    /// Annotation size follows the source image width, independently of fit.
    func testSmallImageUsesSmallAnnotations() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let controller = EditorWindowController(
            image: TestSupport.solidImage(width: 100, height: 80),
            settingsStore: SettingsStore(fileManager: .default,
                                         fileURL: directory.appendingPathComponent("settings.json"))
        )
        defer { controller.dismissWithoutCompletion() }

        let window = try XCTUnwrap(controller.window)
        let canvas = try XCTUnwrap(findCanvas(in: window.contentView))
        let magnification = try XCTUnwrap(canvas.enclosingScrollView?.magnification)

        let fontSize = try newTextEditorFontSize(on: canvas)
        XCTAssertEqual(fontSize, 16, accuracy: 0.01)
        XCTAssertLessThan(fontSize * magnification, 38.4)

        let diameter = try placeMarkerAndGetDiameter(on: canvas, at: NSPoint(x: 60, y: 40))
        XCTAssertEqual(diameter, fontSize, accuracy: 0.01,
                       "marker diameter shares the text font-size calculation")
        XCTAssertEqual(diameter / canvas.baseImage.size.width, fontSize / canvas.baseImage.size.width, accuracy: 0.001)
    }

    func testLargeImageUsesProportionalAnnotations() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        // 4000×2000 px forces a downscale fit (baseScale << 1) in any window.
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: 4000,
                                                 pixelsHigh: 2000,
                                                 bitsPerSample: 8,
                                                 samplesPerPixel: 4,
                                                 hasAlpha: true,
                                                 isPlanar: false,
                                                 colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0,
                                                 bitsPerPixel: 0))
        let image = NSImage(size: NSSize(width: 4000, height: 2000))
        image.addRepresentation(rep)
        let controller = EditorWindowController(
            image: image,
            settingsStore: SettingsStore(fileManager: .default,
                                         fileURL: directory.appendingPathComponent("settings.json"))
        )
        defer { controller.dismissWithoutCompletion() }

        let window = try XCTUnwrap(controller.window)
        let canvas = try XCTUnwrap(findCanvas(in: window.contentView))
        let magnification = try XCTUnwrap(canvas.enclosingScrollView?.magnification)
        XCTAssertLessThan(magnification, 0.95, "large capture must be downscaled to fit")

        let fontSize = try newTextEditorFontSize(on: canvas)
        XCTAssertGreaterThan(fontSize, 38.4,
                             "downscaled captures need a larger canvas-space size")
        XCTAssertEqual(fontSize, 40 * pow(4, 0.65), accuracy: 0.01)
        XCTAssertLessThanOrEqual(fontSize, ImageSafetyLimits.runtime.maxFontSize)

        let diameter = try placeMarkerAndGetDiameter(on: canvas, at: NSPoint(x: 200, y: 160))
        XCTAssertEqual(diameter, fontSize, accuracy: 0.01)
        XCTAssertEqual(diameter / canvas.baseImage.size.width, fontSize / canvas.baseImage.size.width, accuracy: 0.001)
    }

    func testManualZoomDoesNotChangeAnnotationCreationSize() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let controller = EditorWindowController(
            image: TestSupport.solidImage(width: 100, height: 80),
            settingsStore: SettingsStore(fileManager: .default,
                                         fileURL: directory.appendingPathComponent("settings.json"))
        )
        defer { controller.dismissWithoutCompletion() }

        let window = try XCTUnwrap(controller.window)
        let canvas = try XCTUnwrap(findCanvas(in: window.contentView))
        let magnificationBefore = try XCTUnwrap(canvas.enclosingScrollView?.magnification)
        let fontSizeBefore = try newTextEditorFontSize(on: canvas)

        // Cmd+= zooms in through the canvas key-command path.
        canvas.keyDown(with: try keyEvent(keyCode: 24, modifierFlags: [.command], characters: "="))
        let magnificationAfter = try XCTUnwrap(canvas.enclosingScrollView?.magnification)
        XCTAssertNotEqual(magnificationBefore, magnificationAfter, accuracy: 0.001,
                          "zoom command should change live magnification")

        let fontSizeAfter = try newTextEditorFontSize(on: canvas)
        XCTAssertEqual(fontSizeBefore, fontSizeAfter, accuracy: 0.01,
                       "manual zoom must not resize subsequently created annotations")
        let diameterAfter = try placeMarkerAndGetDiameter(on: canvas, at: NSPoint(x: 150, y: 40))
        XCTAssertEqual(diameterAfter, fontSizeAfter, accuracy: 0.01)
    }

    private func newTextEditorFontSize(on canvas: EditorCanvasView) throws -> CGFloat {
        canvas.setTool(.text)
        canvas.mouseDown(with: mouseEvent(type: .leftMouseDown, canvas: canvas, location: NSPoint(x: 60, y: 40)))
        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        let size = try XCTUnwrap(editor.font?.pointSize)
        // Escape cancels the fresh (empty) text edit and removes the item.
        editor.keyDown(with: try keyEvent(keyCode: 53, modifierFlags: [], characters: ""))
        return size
    }

    private func placeMarkerAndGetDiameter(on canvas: EditorCanvasView, at point: NSPoint) throws -> CGFloat {
        canvas.setTool(.marker)
        canvas.mouseDown(with: mouseEvent(type: .leftMouseDown, canvas: canvas, location: point))
        canvas.mouseUp(with: mouseEvent(type: .leftMouseUp, canvas: canvas, location: point))
        guard case .marker(let marker) = canvas.editableState()?.items.last else {
            throw NSError(domain: "EditorWindowControllerTests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "expected a placed marker"])
        }
        return marker.diameter
    }

    private func color(in image: NSImage, at point: NSPoint) throws -> NSColor {
        let rep = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        return try XCTUnwrap(rep.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.deviceRGB))
    }

    private func findCanvas(in view: NSView?) -> EditorCanvasView? {
        guard let view else { return nil }
        if let canvas = view as? EditorCanvasView { return canvas }
        for subview in view.subviews {
            if let canvas = findCanvas(in: subview) { return canvas }
        }
        return nil
    }

    private func findButton(in view: NSView?, toolTip: String) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.toolTip == toolTip { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview, toolTip: toolTip) { return button }
        }
        return nil
    }

    private func drawStroke(on canvas: EditorCanvasView, from start: NSPoint, to end: NSPoint) {
        canvas.setTool(.pen)
        canvas.mouseDown(with: mouseEvent(type: .leftMouseDown, canvas: canvas, location: start))
        canvas.mouseDragged(with: mouseEvent(type: .leftMouseDragged, canvas: canvas, location: end))
        canvas.mouseUp(with: mouseEvent(type: .leftMouseUp, canvas: canvas, location: end))
    }

    private func mouseEvent(type: NSEvent.EventType,
                            canvas: EditorCanvasView,
                            location: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type,
                           location: canvas.convert(location, to: nil),
                           modifierFlags: [],
                           timestamp: 0,
                           windowNumber: 0,
                           context: nil,
                           eventNumber: 0,
                           clickCount: 1,
                           pressure: 0)!
    }

    private func keyEvent(keyCode: UInt16,
                          modifierFlags: NSEvent.ModifierFlags,
                          characters: String,
                          windowNumber: Int = 0) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown,
                                       location: .zero,
                                       modifierFlags: modifierFlags,
                                       timestamp: 0,
                                       windowNumber: windowNumber,
                                       context: nil,
                                       characters: characters,
                                       charactersIgnoringModifiers: characters.lowercased(),
                                       isARepeat: false,
                                       keyCode: keyCode))
    }
}

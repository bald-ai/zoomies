import AppKit
import XCTest
@testable import Zoomies

final class CanvasGestureContractTests: XCTestCase {
    func testSelectionCutPasteAndUndoPreserveOriginalPixels() throws {
        let base = try XCTUnwrap(NSImage(data: TestSupport.noiseImagePNGData(width: 100, height: 80)))
        let canvas = EditorCanvasView(image: base)
        XCTAssertFalse(canvas.pasteCopiedSelection())
        canvas.setTool(.selection)
        let origin = try XCTUnwrap(canvas.editableState()?.baseImageOrigin).nsPoint
        let start = NSPoint(x: origin.x + 10, y: origin.y + 10)
        let end = NSPoint(x: origin.x + 30, y: origin.y + 30)
        drag(canvas, from: start, to: end)
        let payload = try XCTUnwrap(canvas.selectedRegionPayload())
        XCTAssertEqual(payload.rect.size, NSSize(width: 20, height: 20))
        XCTAssertEqual(payload.image.size, payload.rect.size)
        XCTAssertTrue(canvas.cutSelectedRegion())
        let cut = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(canvas.compositeImage().tiffRepresentation)))
        XCTAssertEqual(try XCTUnwrap(cut.colorAt(x: 15, y: 15)).alphaComponent, 0, accuracy: 0.01)
        XCTAssertTrue(canvas.pasteCopiedSelection())
        let items = try XCTUnwrap(canvas.editableState()).items
        XCTAssertEqual(items.count, 2)
        guard case .image(let pastedPNG, let rect) = items[1] else { return XCTFail("Expected pasted image") }
        XCTAssertEqual(rect.nsRect.size, payload.rect.size)
        XCTAssertEqual(try XCTUnwrap(PNGMetadata.pixelDimensions(ofPNG: pastedPNG)).width, 20)
        canvas.undo()
        XCTAssertEqual(canvas.editableState()?.items.count, 1)
        canvas.undo()
        XCTAssertEqual(canvas.editableState()?.items.count, 0)
        let restored = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(canvas.compositeImage().tiffRepresentation)))
        let original = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(base.tiffRepresentation)))
        let actual = try XCTUnwrap(restored.colorAt(x: 15, y: 15)?.usingColorSpace(.deviceRGB))
        let expected = try XCTUnwrap(original.colorAt(x: 15, y: 15)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 1.0 / 255)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 1.0 / 255)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 1.0 / 255)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 1.0 / 255)
        canvas.redo()
        XCTAssertEqual(canvas.editableState()?.items.count, 1)
    }

    func testEllipseBorderSelectionMovesShapeOnceAndUndoRestoresGeometry() throws {
        let png = try TestSupport.noiseImagePNGData(width: 100, height: 80)
        let original = EditorCanvasState.Item.ellipse(rect: .init(NSRect(x: 20, y: 20, width: 40, height: 30)),
                                                     color: .init(.red), lineWidth: 2)
        let canvas = EditorCanvasView(image: try XCTUnwrap(NSImage(data: png)),
                                      initialState: EditorCanvasState(baseImagePNG: png, items: [original]))
        canvas.setTool(.selection)
        XCTAssertFalse(canvas.selectEditableItem(at: NSPoint(x: 90, y: 75)))
        drag(canvas, from: NSPoint(x: 20, y: 35), to: NSPoint(x: 25, y: 42))
        let moved = try XCTUnwrap(canvas.editableState()).items
        XCTAssertEqual(moved.count, 1)
        guard case .ellipse(let rect, _, let width) = moved[0] else { return XCTFail("Expected ellipse") }
        XCTAssertEqual(rect.nsRect, NSRect(x: 25, y: 27, width: 40, height: 30))
        XCTAssertEqual(width, 2)
        canvas.undo()
        XCTAssertEqual(canvas.editableState()?.items, [original])
        canvas.redo()
        XCTAssertEqual(canvas.editableState()?.items, moved)
    }

    private func event(_ type: NSEvent.EventType, canvas: EditorCanvasView, point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    private func drag(_ canvas: EditorCanvasView, from: NSPoint, to: NSPoint) {
        canvas.mouseDown(with: event(.leftMouseDown, canvas: canvas, point: from))
        canvas.mouseDragged(with: event(.leftMouseDragged, canvas: canvas, point: to))
        canvas.mouseUp(with: event(.leftMouseUp, canvas: canvas, point: to))
    }
    func testLineAndArrowMinimumLengthAndUndoContract() {
        for tool: EditorTool in [.line, .arrow] {
            let canvas = EditorCanvasView(image: TestSupport.solidImage())
            canvas.setTool(tool)
            drag(canvas, from: NSPoint(x: 20, y: 20), to: NSPoint(x: 21, y: 20))
            XCTAssertEqual(canvas.editableState()?.items.count, 0)
            drag(canvas, from: NSPoint(x: 20, y: 20), to: NSPoint(x: 22, y: 20))
            XCTAssertEqual(canvas.editableState()?.items.count, 1)
            canvas.undo()
            XCTAssertEqual(canvas.editableState()?.items.count, 0)
            canvas.redo()
            XCTAssertEqual(canvas.editableState()?.items.count, 1)
        }
    }
    func testRectangleAndEllipseRequireBothDimensionsAndCommitOnce() {
        for tool: EditorTool in [.rectangle, .ellipse] {
            let canvas = EditorCanvasView(image: TestSupport.solidImage())
            canvas.setTool(tool)
            for end in [NSPoint(x: 21, y: 25), NSPoint(x: 25, y: 21)] {
                drag(canvas, from: NSPoint(x: 20, y: 20), to: end)
                XCTAssertEqual(canvas.editableState()?.items.count, 0)
            }
            drag(canvas, from: NSPoint(x: 20, y: 20), to: NSPoint(x: 22, y: 22))
            XCTAssertEqual(canvas.editableState()?.items.count, 1)
            canvas.undo()
            XCTAssertEqual(canvas.editableState()?.items.count, 0)
            canvas.redo()
            XCTAssertEqual(canvas.editableState()?.items.count, 1)
        }
    }
}

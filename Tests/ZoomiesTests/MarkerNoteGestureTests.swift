import AppKit
import XCTest
@testable import Zoomies

final class MarkerNoteGestureTests: XCTestCase {
    func testDoubleClickOnMarkerRequestsNote() throws {
        let png = try TestSupport.noiseImagePNGData(width: 200, height: 120)
        let canvas = EditorCanvasView(image: try XCTUnwrap(NSImage(data: png)))
        canvas.setTool(.marker)
        let p = NSPoint(x: 60, y: 60)
        send(canvas, .leftMouseDown, p, 1); send(canvas, .leftMouseUp, p, 1)
        var got: Int?
        canvas.onMarkerNoteRequest = { n, _ in got = n }
        send(canvas, .leftMouseDown, p, 1); send(canvas, .leftMouseUp, p, 1)
        send(canvas, .leftMouseDown, p, 2); send(canvas, .leftMouseUp, p, 2)
        XCTAssertEqual(got, 1)
    }
    func testDeletingMarkerReportsRemainingNumbers() throws {
        let png = try TestSupport.noiseImagePNGData(width: 200, height: 120)
        let canvas = EditorCanvasView(image: try XCTUnwrap(NSImage(data: png)))
        canvas.setTool(.marker)
        var reported: [Set<Int>] = []
        canvas.onMarkerNumbersChanged = { reported.append($0) }
        send(canvas, .leftMouseDown, NSPoint(x: 40, y: 40), 1); send(canvas, .leftMouseUp, NSPoint(x: 40, y: 40), 1)
        send(canvas, .leftMouseDown, NSPoint(x: 120, y: 80), 1); send(canvas, .leftMouseUp, NSPoint(x: 120, y: 80), 1)
        canvas.undo()
        XCTAssertEqual(reported, [[1], [1, 2], [1]])
    }

    private func send(_ canvas: EditorCanvasView, _ type: NSEvent.EventType, _ point: NSPoint, _ clicks: Int) {
        let e = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                   windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 0)!
        if type == .leftMouseDown { canvas.mouseDown(with: e) } else { canvas.mouseUp(with: e) }
    }
}

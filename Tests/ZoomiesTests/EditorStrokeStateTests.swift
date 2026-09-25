import AppKit
import XCTest
@testable import Zoomies

/// Pins how the four vector strokes (pen, arrow, rectangle, ellipse) are
/// saved, restored, moved and drawn.
final class EditorStrokeStateTests: XCTestCase {
    private let blue = EditorCanvasState.Color(NSColor(deviceRed: 0.25, green: 0.5, blue: 0.75, alpha: 1))

    func testStrokesDecodeFromSavedJSON() throws {
        let color = #""color":{"red":0.25,"green":0.5,"blue":0.75,"alpha":1}"#
        let json = """
        [
          {"type":"pen","points":[{"x":1,"y":2},{"x":3,"y":4}],\(color),"lineWidth":2},
          {"type":"arrow","start":{"x":5,"y":6},"end":{"x":7,"y":8},\(color),"lineWidth":3},
          {"type":"rect","rect":{"x":1,"y":2,"width":10,"height":20},\(color),"lineWidth":4},
          {"type":"ellipse","rect":{"x":3,"y":4,"width":30,"height":40},\(color),"lineWidth":5}
        ]
        """
        let items = try JSONDecoder().decode([EditorCanvasState.Item].self, from: Data(json.utf8))
        XCTAssertEqual(items, [
            .pen(points: [.init(NSPoint(x: 1, y: 2)), .init(NSPoint(x: 3, y: 4))], color: blue, lineWidth: 2),
            .arrow(start: .init(NSPoint(x: 5, y: 6)), end: .init(NSPoint(x: 7, y: 8)), color: blue, lineWidth: 3),
            .rect(rect: .init(NSRect(x: 1, y: 2, width: 10, height: 20)), color: blue, lineWidth: 4),
            .ellipse(rect: .init(NSRect(x: 3, y: 4, width: 30, height: 40)), color: blue, lineWidth: 5)
        ])
    }

    func testStrokesEncodeTheirTypeAndOnlyTheirOwnFields() throws {
        let colorObject: [String: Double] = ["red": 0.25, "green": 0.5, "blue": 0.75, "alpha": 1]
        let cases: [(EditorCanvasState.Item, [String: Any])] = [
            (.pen(points: [.init(NSPoint(x: 1, y: 2))], color: blue, lineWidth: 2),
             ["type": "pen", "points": [["x": 1.0, "y": 2.0]], "color": colorObject, "lineWidth": 2.0]),
            (.arrow(start: .init(NSPoint(x: 5, y: 6)), end: .init(NSPoint(x: 7, y: 8)), color: blue, lineWidth: 3),
             ["type": "arrow", "start": ["x": 5.0, "y": 6.0], "end": ["x": 7.0, "y": 8.0],
              "color": colorObject, "lineWidth": 3.0]),
            (.rect(rect: .init(NSRect(x: 1, y: 2, width: 10, height: 20)), color: blue, lineWidth: 4),
             ["type": "rect", "rect": ["x": 1.0, "y": 2.0, "width": 10.0, "height": 20.0],
              "color": colorObject, "lineWidth": 4.0]),
            (.ellipse(rect: .init(NSRect(x: 3, y: 4, width: 30, height: 40)), color: blue, lineWidth: 5),
             ["type": "ellipse", "rect": ["x": 3.0, "y": 4.0, "width": 30.0, "height": 40.0],
              "color": colorObject, "lineWidth": 5.0])
        ]
        for (item, expected) in cases {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item))
            let encoded = try XCTUnwrap(object as? NSDictionary)
            XCTAssertEqual(encoded, expected as NSDictionary)
        }
    }

    func testRestoringMovesStrokesByTheChangeInImageOriginAndSavesThemBack() throws {
        let png = try TestSupport.noiseImagePNGData(width: 16, height: 12)
        let state = EditorCanvasState(baseImagePNG: png,
                                      baseImageOrigin: .init(NSPoint(x: 10, y: 10)),
                                      items: [
            .pen(points: [.init(NSPoint(x: 1, y: 2)), .init(NSPoint(x: 3, y: 4))], color: blue, lineWidth: 2),
            .arrow(start: .init(NSPoint(x: 5, y: 6)), end: .init(NSPoint(x: 7, y: 8)), color: blue, lineWidth: 3),
            .rect(rect: .init(NSRect(x: 1, y: 2, width: 10, height: 20)), color: blue, lineWidth: 4),
            .ellipse(rect: .init(NSRect(x: 3, y: 4, width: 30, height: 40)), color: blue, lineWidth: 5)
        ])
        // The image moves from (10, 10) to (30, 40), so every point moves by (+20, +30).
        let drawing = EditorDrawing(restoring: state,
                                    baseImageOrigin: NSPoint(x: 30, y: 40),
                                    fallbackBaseImage: NSImage(size: NSSize(width: 1, height: 1)))
        XCTAssertEqual(drawing.items.compactMap(\.stateItem), [
            .pen(points: [.init(NSPoint(x: 21, y: 32)), .init(NSPoint(x: 23, y: 34))], color: blue, lineWidth: 2),
            .arrow(start: .init(NSPoint(x: 25, y: 36)), end: .init(NSPoint(x: 27, y: 38)), color: blue, lineWidth: 3),
            .rect(rect: .init(NSRect(x: 21, y: 32, width: 10, height: 20)), color: blue, lineWidth: 4),
            .ellipse(rect: .init(NSRect(x: 23, y: 34, width: 30, height: 40)), color: blue, lineWidth: 5)
        ])
    }

    func testEachStrokeDrawsItsOwnShape() throws {
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        let box = NSRect(x: 20, y: 20, width: 60, height: 60)
        // Rectangle and ellipse share the left edge; only the rectangle reaches the corner.
        let rect = try render(.rect(rect: box, color: red, lineWidth: 4))
        XCTAssertTrue(isRed(rect, 20, 50))
        XCTAssertTrue(isRed(rect, 20, 20))
        XCTAssertTrue(isEmpty(rect, 50, 50))
        let ellipse = try render(.ellipse(rect: box, color: red, lineWidth: 4))
        XCTAssertTrue(isRed(ellipse, 20, 50))
        XCTAssertTrue(isEmpty(ellipse, 22, 22))
        // Pen and arrow share the shaft; only the arrow has a head near the end.
        let start = NSPoint(x: 10, y: 50), end = NSPoint(x: 90, y: 50)
        let pen = try render(.pen(points: [start, end], color: red, lineWidth: 4))
        XCTAssertTrue(isRed(pen, 50, 50))
        XCTAssertTrue(isEmpty(pen, 82, 45))
        let arrow = try render(.arrow(start: start, end: end, color: red, lineWidth: 4))
        XCTAssertTrue(isRed(arrow, 50, 50))
        XCTAssertTrue(isRed(arrow, 82, 45))
    }

    private func render(_ item: EditorDrawing.Item) throws -> NSBitmapImageRep {
        let size = NSSize(width: 100, height: 100)
        let base = NSImage(size: size)
        base.addRepresentation(try XCTUnwrap(ImageSafety.makeBitmapRep(pixelsWide: 100, pixelsHigh: 100)))
        let drawing = EditorDrawing(baseImage: base, baseImageOrigin: .zero, items: [item])
        let output = EditorImageRenderer.compositeImage(of: drawing, croppingTo: NSRect(origin: .zero, size: size))
        return try XCTUnwrap(output.representations.compactMap { $0 as? NSBitmapImageRep }.first)
    }

    private func isRed(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
        return color.alphaComponent > 0.9 && color.redComponent > 0.9 && color.greenComponent < 0.1
    }

    private func isEmpty(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        (rep.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.05
    }
}

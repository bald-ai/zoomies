import AppKit
import XCTest
@testable import Zoomies

final class AnnotationSafetyTests: XCTestCase {
    private let point = EditorCanvasState.Point(NSPoint(x: 4, y: 5))
    private let color = EditorCanvasState.Color(.systemBlue)
    private let rect = EditorCanvasState.Rect(NSRect(x: 1, y: 2, width: 5, height: 6))

    private func assertSafety(_ items: [EditorCanvasState.Item], safe: Bool,
                              limits: ImageSafetyLimits = .runtime, file: StaticString = #filePath, line: UInt = #line) throws {
        let png = try TestSupport.noiseImagePNGData(width: 16, height: 12)
        let state = EditorCanvasState(baseImagePNG: png, items: items)
        XCTAssertEqual(state.isSafeToRestore(limits: limits), safe, file: file, line: line)
    }

    func testAllAnnotationKindsRoundTripAndRestoreTogether() throws {
        let png = try TestSupport.noiseImagePNGData(width: 16, height: 12)
        let items: [EditorCanvasState.Item] = [
            .pen(points: [point, .init(NSPoint(x: 8, y: 9))], color: color, lineWidth: 2),
            .arrow(start: point, end: .init(NSPoint(x: 9, y: 10)), color: color, lineWidth: 2),
            .rect(rect: rect, color: color, lineWidth: 2), .ellipse(rect: rect, color: color, lineWidth: 2),
            .text(.init(text: "saved note", origin: point, color: color, fontSize: 12)),
            .marker(.init(number: 2, center: point, color: color, diameter: 12)),
            .image(pngData: png, rect: rect), .erase(rect: rect)
        ]
        let state = EditorCanvasState(baseImagePNG: png, items: items)
        let decoded = try JSONDecoder().decode(EditorCanvasState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.items, items)
        XCTAssertEqual(decoded.baseImagePNG, png)
        XCTAssertTrue(decoded.isSafeToRestore())
    }

    func testStrokeWidthsRejectInvalidValuesForEveryStrokeKind() throws {
        for width in [CGFloat.zero, -1, .nan, .infinity, ImageSafetyLimits.runtime.maxLineWidth + 1] {
            for item: EditorCanvasState.Item in [
                .pen(points: [point], color: color, lineWidth: width),
                .arrow(start: point, end: point, color: color, lineWidth: width),
                .rect(rect: rect, color: color, lineWidth: width),
                .ellipse(rect: rect, color: color, lineWidth: width)
            ] { try assertSafety([item], safe: false) }
        }
        try assertSafety([.pen(points: [point], color: color, lineWidth: ImageSafetyLimits.runtime.maxLineWidth)], safe: true)
    }

    func testCoordinatesAndColorsRejectNonFiniteValues() throws {
        for value in [CGFloat.nan, .infinity, -.infinity, ImageSafetyLimits.runtime.maxAbsoluteCoordinate + 1] {
            let bad = EditorCanvasState.Point(NSPoint(x: value, y: 0))
            try assertSafety([.pen(points: [bad], color: color, lineWidth: 1)], safe: false)
            try assertSafety([.arrow(start: point, end: bad, color: color, lineWidth: 1)], safe: false)
            try assertSafety([.arrow(start: bad, end: point, color: color, lineWidth: 1)], safe: false)
        }
        for key in [\EditorCanvasState.Color.red, \.green, \.blue, \.alpha] {
            var badColor = color
            badColor[keyPath: key] = .nan
            try assertSafety([.pen(points: [point], color: badColor, lineWidth: 1)], safe: false)
            try assertSafety([.text(.init(text: "x", origin: point, color: badColor, fontSize: 12))], safe: false)
            try assertSafety([.marker(.init(number: 1, center: point, color: badColor, diameter: 12))], safe: false)
        }
    }

    func testRectanglesRejectZeroNegativeNonFiniteAndOversizedDimensions() throws {
        for key in [\EditorCanvasState.Rect.width, \.height] {
            for value in [CGFloat.zero, -1, .nan, .infinity, CGFloat(ImageSafetyLimits.runtime.maxDimension + 1)] {
                var bad = rect
                bad[keyPath: key] = value
                try assertSafety([.rect(rect: bad, color: color, lineWidth: 1)], safe: false)
                try assertSafety([.ellipse(rect: bad, color: color, lineWidth: 1)], safe: false)
                try assertSafety([.erase(rect: bad)], safe: false)
            }
        }
    }

    func testTextAndMarkerLimitsRejectMalformedMetadata() throws {
        var limits = ImageSafetyLimits.runtime
        limits.maxTextLength = 3
        limits.maxFontSize = 20
        try assertSafety([.text(.init(text: "abc", origin: point, color: color, fontSize: 20))], safe: true, limits: limits)
        try assertSafety([.text(.init(text: "abcd", origin: point, color: color, fontSize: 20))], safe: false, limits: limits)
        for size in [CGFloat.zero, -1, .nan, .infinity, 21] {
            try assertSafety([.text(.init(text: "x", origin: point, color: color, fontSize: size))], safe: false, limits: limits)
            try assertSafety([.marker(.init(number: 1, center: point, color: color, diameter: size))], safe: false, limits: limits)
        }
        for number in [0, -1, EditorDrawing.MarkerItem.maxNumber + 1] {
            try assertSafety([.marker(.init(number: number, center: point, color: color, diameter: 12))], safe: false)
        }
    }

    func testEmbeddedImageAndCountLimitsAreAppliedBeforeRestoration() throws {
        var limits = ImageSafetyLimits.runtime
        limits.maxPenPointCount = 1
        try assertSafety([.pen(points: [point, point], color: color, lineWidth: 1)], safe: false, limits: limits)
        try assertSafety([.pen(points: [], color: color, lineWidth: 1)], safe: false)
        limits.maxItemCount = 1
        try assertSafety([.erase(rect: rect), .erase(rect: rect)], safe: false, limits: limits)
        try assertSafety([.image(pngData: Data("not PNG".utf8), rect: rect)], safe: false)
        let png = try TestSupport.noiseImagePNGData(width: 16, height: 12)
        var state = EditorCanvasState(baseImagePNG: png, items: [])
        state.baseImageOrigin = .init(NSPoint(x: CGFloat.infinity, y: 0))
        XCTAssertFalse(state.isSafeToRestore())
        state.baseImageOrigin = nil
        limits.maxEmbeddedImageBytes = png.count - 1
        XCTAssertFalse(state.isSafeToRestore(limits: limits))
    }
}

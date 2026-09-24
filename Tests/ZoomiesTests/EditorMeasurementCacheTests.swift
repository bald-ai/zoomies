import XCTest
import AppKit
@testable import Zoomies

final class EditorMeasurementCacheTests: XCTestCase {
    private func uncachedTextBounds(_ item: EditorDrawing.TextItem) -> NSRect {
        let size = EditorImageRenderer.textContentSize(for: item.text,
                                                       font: NSFont.systemFont(ofSize: item.fontSize, weight: .regular))
        return NSRect(x: item.origin.x, y: item.origin.y,
                      width: max(size.width + EditorImageRenderer.textPadding.width * 2, 60),
                      height: max(size.height + EditorImageRenderer.textPadding.height * 2, 28))
    }

    func testCachedTextBoundsMatchFreshMeasurementAcrossMovesAndEdits() {
        var item = EditorDrawing.TextItem(text: "Hello\nworld 🚀", origin: NSPoint(x: 10, y: 20),
                                          color: .systemRed, fontSize: 24)
        for step in 0..<3 {
            XCTAssertEqual(EditorImageRenderer.textBounds(for: item), uncachedTextBounds(item), "step \(step)")
            item.origin.x += 13.5 // moving must not change the measured size
        }
        item.text += "!!!"
        XCTAssertEqual(EditorImageRenderer.textBounds(for: item), uncachedTextBounds(item))
        item.fontSize = 31
        XCTAssertEqual(EditorImageRenderer.textBounds(for: item), uncachedTextBounds(item))
    }

    func testRegularTextAndBoldMarkerMeasurementsDoNotCollide() {
        // Same size and string in both caches: text uses the regular font,
        // markers the bold one, so the widths must differ and each match
        // its own fresh measurement.
        let fontSize: CGFloat = 40
        let text = EditorDrawing.TextItem(text: "888888", origin: .zero, color: .black, fontSize: fontSize)
        let marker = EditorDrawing.MarkerItem(number: 888_888, center: .zero, color: .black, diameter: fontSize * 2)

        let textWidth = EditorImageRenderer.textBounds(for: text).width - EditorImageRenderer.textPadding.width * 2
        let boldWidth = ("888888" as NSString)
            .size(withAttributes: [.font: EditorImageRenderer.markerFont(forDiameter: marker.diameter)]).width
        let markerWidth = EditorImageRenderer.markerRect(for: marker).width

        XCTAssertEqual(textWidth, uncachedTextBounds(text).width - EditorImageRenderer.textPadding.width * 2)
        XCTAssertEqual(markerWidth, max(marker.diameter, ceil(boldWidth) + marker.diameter * 0.4))
        XCTAssertNotEqual(textWidth, boldWidth, accuracy: 0.5, "Regular and bold measurements must stay separate")
    }

    func testMarkerCursorIsReusedUntilItsInputsChange() {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 200, height: 120))
        canvas.setTool(.marker)

        let first = canvas.markerPreviewCursor()
        XCTAssertTrue(canvas.markerPreviewCursor() === first, "Unchanged inputs reuse the rendered cursor")

        canvas.setColor(.systemBlue)
        let recolored = canvas.markerPreviewCursor()
        XCTAssertFalse(recolored === first, "A color change re-renders the cursor")
        XCTAssertTrue(canvas.markerPreviewCursor() === recolored)
    }
}

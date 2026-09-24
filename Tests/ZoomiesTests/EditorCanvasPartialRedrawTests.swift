import XCTest
import AppKit
import Carbon
@testable import Zoomies

/// Verifies that partial (gesture-only) invalidation is equivalent to a full
/// redraw, after every drag update, at several zoom levels and with fractional
/// coordinates. Two exact checks split the property in two:
///
/// - **Coverage** (antialiased, as on screen): every pixel that changes between
///   consecutive full renders lies inside the reported dirty rects.
/// - **Repaint** (antialiasing off): redrawing only the dirty rects into a
///   running bitmap reproduces the full render byte-for-byte, so `draw(_:)`
///   never skips something that reaches into a dirty rect.
///
/// Repaint runs without antialiasing because CoreGraphics antialiases a path
/// that crosses the clip edge slightly differently from an unclipped draw, so
/// even an unchanged region redrawn under a clip can move edge pixels by a few
/// levels. That is a property of clipped drawing, not of the invalidation.
final class EditorCanvasPartialRedrawTests: XCTestCase {
    private static let scales: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3]

    // MARK: - Harness

    /// Hosts the canvas in a magnified scroll view so the canvas's zoom-aware
    /// margins see the same scale the harness renders at.
    private final class Harness {
        let canvas: EditorCanvasView
        let scale: CGFloat
        private let scrollView: NSScrollView
        private(set) var incremental: NSBitmapImageRep?
        private(set) var lastFull: NSBitmapImageRep?
        private var pendingDirtyRects: [NSRect] = []

        init(canvas: EditorCanvasView, scale: CGFloat) {
            self.canvas = canvas
            self.scale = scale
            scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            scrollView.allowsMagnification = true
            scrollView.minMagnification = 0.01
            scrollView.maxMagnification = 10
            scrollView.documentView = canvas
            scrollView.magnification = scale
            canvas.onPartialInvalidation = { [unowned self] rect in pendingDirtyRects.append(rect) }
        }

        var magnification: CGFloat { scrollView.magnification }

        func makeBitmap() -> NSBitmapImageRep {
            NSBitmapImageRep(bitmapDataPlanes: nil,
                             pixelsWide: max(1, Int(ceil(canvas.bounds.width * scale))),
                             pixelsHigh: max(1, Int(ceil(canvas.bounds.height * scale))),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        }

        /// AppKit rounds a dirty rect out to whole device pixels.
        func pixelRect(for dirty: NSRect, in bitmap: NSBitmapImageRep) -> CGRect {
            let minX = floor(dirty.minX * scale), minY = floor(dirty.minY * scale)
            let maxX = ceil(dirty.maxX * scale), maxY = ceil(dirty.maxY * scale)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .intersection(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        }

        /// Draws the canvas into `bitmap`. With `dirty`, mirrors AppKit: the
        /// rect is rounded out to whole pixels, cleared, clipped, and redrawn.
        func draw(into bitmap: NSBitmapImageRep, dirty: NSRect?, antialias: Bool) {
            let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap)!
            let context = NSGraphicsContext(cgContext: bitmapContext.cgContext, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            let cg = context.cgContext
            cg.setShouldAntialias(antialias)
            cg.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
            cg.scaleBy(x: 1, y: -1)

            var region = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            if let dirty {
                region = pixelRect(for: dirty, in: bitmap)
                guard !region.isNull, !region.isEmpty else { return }
            }
            cg.clip(to: region)
            cg.clear(region)
            cg.scaleBy(x: scale, y: scale)
            canvas.draw(NSRect(x: region.minX / scale, y: region.minY / scale,
                               width: region.width / scale, height: region.height / scale))
        }

        func fullRender(antialias: Bool) -> NSBitmapImageRep {
            let bitmap = makeBitmap()
            draw(into: bitmap, dirty: nil, antialias: antialias)
            return bitmap
        }

        /// Full invalidation (mouse down/up): restart both reference bitmaps.
        func reset() {
            pendingDirtyRects.removeAll()
            incremental = fullRender(antialias: false)
            lastFull = fullRender(antialias: true)
        }

        /// Takes the partial invalidations reported since the last call and
        /// redraws them into the running (non-antialiased) bitmap.
        func takePendingDirtyRects() -> [NSRect] {
            let rects = pendingDirtyRects
            pendingDirtyRects.removeAll()
            if let incremental {
                rects.forEach { draw(into: incremental, dirty: $0, antialias: false) }
            }
            return rects
        }

        /// Replaces the antialiased reference and returns the previous one.
        func advanceFull() -> (previous: NSBitmapImageRep, current: NSBitmapImageRep) {
            let current = fullRender(antialias: true)
            defer { lastFull = current }
            return (lastFull!, current)
        }
    }

    private struct Difference: CustomStringConvertible {
        let count: Int
        let maxDelta: Int
        let pixelBounds: CGRect
        var description: String { "\(count) bytes differ (max Δ \(maxDelta)) within pixels \(pixelBounds)" }
    }

    /// Byte comparison, exact unless `tolerance` > 0.
    private func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, tolerance: Int = 0) -> Difference? {
        precondition(a.bytesPerRow == b.bytesPerRow && a.pixelsHigh == b.pixelsHigh)
        let length = a.bytesPerRow * a.pixelsHigh
        guard let pa = a.bitmapData, let pb = b.bitmapData else { return nil }
        if memcmp(pa, pb, length) == 0 { return nil }
        var count = 0, maxDelta = 0
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for index in 0..<length where abs(Int(pa[index]) - Int(pb[index])) > tolerance {
            let x = (index % a.bytesPerRow) / 4, y = index / a.bytesPerRow
            count += 1
            maxDelta = max(maxDelta, abs(Int(pa[index]) - Int(pb[index])))
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        guard count > 0 else { return nil }
        return Difference(count: count, maxDelta: maxDelta,
                          pixelBounds: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// Runs both exact checks for the invalidations produced by one event.
    private func assertPartialRedrawIsEquivalent(_ harness: Harness, _ label: String,
                                                 coverageTolerance: Int,
                                                 file: StaticString, line: UInt) -> Bool {
        let rects = harness.takePendingDirtyRects()
        guard !rects.isEmpty else {
            XCTFail("\(label): expected a partial invalidation", file: file, line: line)
            return false
        }
        let (previous, current) = harness.advanceFull()
        // Paste the previous frame into the dirty rects; any remaining change
        // must then lie outside them.
        let outsideDirty = current.copy() as! NSBitmapImageRep
        for rect in rects.map({ harness.pixelRect(for: $0, in: current) }) where !rect.isEmpty {
            let rowBytes = Int(rect.width) * 4, xOffset = Int(rect.minX) * 4
            for row in Int(rect.minY)..<Int(rect.maxY) {
                let offset = row * current.bytesPerRow + xOffset
                memcpy(outsideDirty.bitmapData! + offset, previous.bitmapData! + offset, rowBytes)
            }
        }
        if let diff = difference(previous, outsideDirty, tolerance: coverageTolerance) {
            XCTFail("\(label) coverage: pixels changed outside the dirty rects: \(diff); dirty \(rects)",
                    file: file, line: line)
            return false
        }
        if let diff = difference(harness.incremental!, harness.fullRender(antialias: false)) {
            XCTFail("\(label) repaint: incremental differs from full render: \(diff); dirty \(rects)",
                    file: file, line: line)
            return false
        }
        return true
    }

    // MARK: - Fixtures

    /// Solid-color images: resampling a textured image at fractional offsets
    /// under a clip is not pixel-stable in CoreGraphics, which would mask real
    /// redraw gaps with filter noise.
    private static func solidPNG(width: Int, height: Int, color: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private let basePNG = solidPNG(width: 160, height: 110, color: NSColor(deviceWhite: 0.85, alpha: 1))
    private let pastedPNG = solidPNG(width: 30, height: 20, color: .systemPurple)

    private func makeCanvas(tool: EditorTool) -> EditorCanvasView {
        let image = NSImage(data: basePNG)!
        let origin = EditorCanvasState.Point(NSPoint(x: EditorDrawing.canvasEdgeInset, y: EditorDrawing.canvasEdgeInset))
        let state = EditorCanvasState(
            baseImagePNG: basePNG,
            baseImageOrigin: origin,
            items: [
                .rect(rect: .init(NSRect(x: 60, y: 50, width: 40, height: 30)), color: .init(.systemRed), lineWidth: 4),
                .image(pngData: pastedPNG, rect: .init(NSRect(x: 110, y: 70, width: 30, height: 20))),
                .text(.init(text: "Hi\nthere", origin: .init(NSPoint(x: 40, y: 92)), color: .init(.systemYellow), fontSize: 16)),
                .marker(.init(number: 3, center: .init(NSPoint(x: 160, y: 40)), color: .init(.systemGreen), diameter: 22)),
                .pen(points: [NSPoint(x: 30, y: 30), NSPoint(x: 90, y: 110), NSPoint(x: 150, y: 60)].map { .init($0) },
                     color: .init(.systemBlue), lineWidth: 4)
            ])
        let canvas = EditorCanvasView(image: image, initialState: state)
        canvas.setTool(tool)
        return canvas
    }

    private func mouseEvent(_ type: NSEvent.EventType, _ canvas: EditorCanvasView, _ point: NSPoint,
                            shift: Bool) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                                        modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0,
                                        context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }

    private func flagsChangedEvent(shift: Bool) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: shift ? [.shift] : [],
                                      timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(kVK_Shift)))
    }

    /// Fractional waypoints between `start` and `end`, with a slight wobble
    /// so pen strokes curve.
    private func path(from start: NSPoint, to end: NSPoint, steps: Int = 7) -> [NSPoint] {
        (0...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            return NSPoint(x: start.x + (end.x - start.x) * t + sin(t * 9) * 6.37,
                           y: start.y + (end.y - start.y) * t + cos(t * 7) * 4.61)
        }
    }

    // MARK: - Driver

    /// Presses at `points[0]`, drags through the rest, and after every drag
    /// update (and optional mid-drag Shift toggle) checks that the running
    /// incremental bitmap equals a full render.
    private func assertIncrementalMatchesFull(_ name: String,
                                              tool: EditorTool,
                                              points: [NSPoint],
                                              shift: Bool = false,
                                              toggleShiftAfterStep: Int? = nil,
                                              coverageTolerance: Int = 0,
                                              file: StaticString = #filePath,
                                              line: UInt = #line) throws {
        for scale in Self.scales {
            let harness = Harness(canvas: makeCanvas(tool: tool), scale: scale)
            let canvas = harness.canvas
            XCTAssertEqual(harness.magnification, scale, accuracy: 0.0001, file: file, line: line)
            var shiftHeld = shift

            canvas.mouseDown(with: try mouseEvent(.leftMouseDown, canvas, points[0], shift: shiftHeld))
            harness.reset()

            for (step, point) in points.dropFirst().enumerated() {
                canvas.mouseDragged(with: try mouseEvent(.leftMouseDragged, canvas, point, shift: shiftHeld))
                guard assertPartialRedrawIsEquivalent(harness, "\(name) @\(scale)x drag step \(step)",
                                                      coverageTolerance: coverageTolerance,
                                                      file: file, line: line) else { break }

                if step == toggleShiftAfterStep {
                    shiftHeld.toggle()
                    canvas.flagsChanged(with: try flagsChangedEvent(shift: shiftHeld))
                    guard assertPartialRedrawIsEquivalent(harness, "\(name) @\(scale)x Shift toggle",
                                                          coverageTolerance: coverageTolerance,
                                                          file: file, line: line) else { break }
                }
            }
            canvas.mouseUp(with: try mouseEvent(.leftMouseUp, canvas, points.last!, shift: shiftHeld))
        }
    }

    // MARK: - Drawing tools

    /// The pen preview is one path; appending a point makes CoreGraphics
    /// re-rasterize all of it, which can nudge antialiased pixels on earlier,
    /// geometrically unchanged segments by one level (of 255). Those stay
    /// untouched until mouse-up repaints the committed stroke; allow exactly
    /// that. Repaint is still checked exactly.
    func testPenStrokeAcrossBaseImageEdges() throws {
        try assertIncrementalMatchesFull("pen", tool: .pen,
                                         points: path(from: NSPoint(x: 30.25, y: 120.4), to: NSPoint(x: 200.7, y: 150.3), steps: 10),
                                         coverageTolerance: 1)
    }

    func testLinePreview() throws {
        try assertIncrementalMatchesFull("line", tool: .line,
                                         points: path(from: NSPoint(x: 20.5, y: 20.3), to: NSPoint(x: 190.37, y: 140.61)))
    }

    func testArrowPreview() throws {
        try assertIncrementalMatchesFull("arrow", tool: .arrow,
                                         points: path(from: NSPoint(x: 190.5, y: 150.3), to: NSPoint(x: 12.37, y: 14.61)))
    }

    func testRectanglePreviewWithAndWithoutShift() throws {
        let points = path(from: NSPoint(x: 70.3, y: 100.2), to: NSPoint(x: 195.7, y: 150.1))
        try assertIncrementalMatchesFull("rect", tool: .rectangle, points: points)
        try assertIncrementalMatchesFull("rect+shift", tool: .rectangle, points: points, shift: true)
        try assertIncrementalMatchesFull("rect shift toggled", tool: .rectangle, points: points, toggleShiftAfterStep: 3)
    }

    func testEllipsePreviewWithAndWithoutShift() throws {
        let points = path(from: NSPoint(x: 150.3, y: 20.2), to: NSPoint(x: 15.7, y: 140.1))
        try assertIncrementalMatchesFull("ellipse", tool: .ellipse, points: points)
        try assertIncrementalMatchesFull("ellipse+shift", tool: .ellipse, points: points, shift: true)
        try assertIncrementalMatchesFull("ellipse shift toggled", tool: .ellipse, points: points, toggleShiftAfterStep: 2)
    }

    // MARK: - Selection and dragging

    func testSelectionRectangleDrag() throws {
        try assertIncrementalMatchesFull("selection", tool: .selection,
                                         points: path(from: NSPoint(x: 30.3, y: 140.2), to: NSPoint(x: 180.37, y: 12.61)))
    }

    func testDraggingItemWithSelectionOutlineAcrossShadowEdge() throws {
        try assertIncrementalMatchesFull("item drag", tool: .selection,
                                         points: path(from: NSPoint(x: 60.5, y: 62.3), to: NSPoint(x: 12.37, y: 140.61)))
    }

    func testDraggingPastedImageWithSelectionOutline() throws {
        try assertIncrementalMatchesFull("image drag", tool: .selection,
                                         points: path(from: NSPoint(x: 125.2, y: 80.1), to: NSPoint(x: 185.37, y: 138.61)))
    }

    func testDraggingTextWithSelectionOutline() throws {
        try assertIncrementalMatchesFull("text drag", tool: .text,
                                         points: path(from: NSPoint(x: 50.2, y: 100.1), to: NSPoint(x: 150.37, y: 20.61)))
    }

    func testDraggingMarkerWithSelectionOutline() throws {
        try assertIncrementalMatchesFull("marker drag", tool: .marker,
                                         points: path(from: NSPoint(x: 160.2, y: 40.1), to: NSPoint(x: 20.37, y: 145.61)))
    }

    // MARK: - Modifier state

    /// Shift on synthetic events must drive the preview (not the global
    /// modifier state), otherwise the Shift cases above would be identical.
    func testShiftFromEventsControlsPreviewAndCommit() throws {
        let start = NSPoint(x: 70.3, y: 60.2), end = NSPoint(x: 150.7, y: 150.1)
        var renders: [Bool: NSBitmapImageRep] = [:]
        for shift in [false, true] {
            let harness = Harness(canvas: makeCanvas(tool: .rectangle), scale: 1)
            let canvas = harness.canvas
            canvas.mouseDown(with: try mouseEvent(.leftMouseDown, canvas, start, shift: shift))
            canvas.mouseDragged(with: try mouseEvent(.leftMouseDragged, canvas, end, shift: shift))
            renders[shift] = harness.fullRender(antialias: true)
            canvas.mouseUp(with: try mouseEvent(.leftMouseUp, canvas, end, shift: shift))

            guard case let .rect(rect, _, _)? = canvas.editableState()?.items.last else {
                return XCTFail("Expected a committed rectangle")
            }
            if shift {
                XCTAssertEqual(rect.width, rect.height, accuracy: 0.001, "Shift commits a square")
            } else {
                XCTAssertNotEqual(rect.width, rect.height, accuracy: 0.5)
            }
        }
        XCTAssertNotNil(difference(renders[false]!, renders[true]!), "Shift must change the preview")
    }
}

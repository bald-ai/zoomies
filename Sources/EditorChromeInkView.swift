import AppKit

/// Transparent layer behind the editor toolbar that shows annotations where
/// they extend past the canvas viewport into the window chrome. The canvas
/// still owns and draws everything inside the viewport; this layer skips the
/// viewport and the note bar so nothing is painted twice or over the note.
final class EditorChromeInkView: NSView {
    weak var canvas: EditorCanvasView?
    /// Areas the layer must not paint, in window coordinates.
    var excludedWindowRects: (() -> [NSRect])?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, canvas.window === window,
              let context = NSGraphicsContext.current else { return }

        let paintable = NSBezierPath(rect: bounds)
        for rect in excludedWindowRects?() ?? [] {
            paintable.append(NSBezierPath(rect: convert(rect, from: nil)))
        }
        paintable.windingRule = .evenOdd

        // Both views are flipped, so canvas space maps here by a translate
        // and the scroll view's magnification.
        let origin = convert(NSPoint.zero, from: canvas)
        let unit = convert(NSPoint(x: 1, y: 1), from: canvas)
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scaleX(by: unit.x - origin.x, yBy: unit.y - origin.y)

        context.saveGraphicsState()
        paintable.addClip()
        transform.concat()
        canvas.drawAnnotationsForChromeInk()
        context.restoreGraphicsState()
    }
}

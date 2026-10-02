import AppKit

/// Draws a note: the same code paints the editor canvas and the saved PNG, so
/// the picture an agent gets is exactly what was on screen. The saved image is
/// the drawing, cropped with a margin, with the Note box burned in below it
/// like a screenshot note.
enum InkNoteRenderer {
    static let background = NSColor(srgbRed: 0.094, green: 0.098, blue: 0.118, alpha: 1)
    static let markerDiameter: CGFloat = 28
    /// Space kept around the drawing in the saved picture.
    static let margin: CGFloat = 32
    static let minimumWidth: CGFloat = 640
    static let scale: CGFloat = 2

    static func markerItem(_ marker: InkNoteDocument.Marker) -> EditorDrawing.MarkerItem {
        EditorDrawing.MarkerItem(number: marker.number, center: NSPoint(x: marker.x, y: marker.y),
                                 color: NSColor(hex: marker.color), diameter: markerDiameter)
    }

    static func markerBounds(_ marker: InkNoteDocument.Marker) -> CGRect {
        EditorImageRenderer.markerBounds(for: markerItem(marker))
    }

    static func itemBounds(_ item: InkNoteDocument.Item) -> CGRect {
        let pad = item.stroke.width
        return item.stroke.bounds.offsetBy(dx: item.x, dy: item.y).insetBy(dx: -pad, dy: -pad)
    }

    /// Everything drawn on the canvas, or `.null` for a text-only note.
    static func drawingBounds(_ document: InkNoteDocument) -> CGRect {
        document.items.map(itemBounds).reduce(CGRect.null) { $0.union($1) }
            .union(document.markers.map(markerBounds).reduce(CGRect.null) { $0.union($1) })
    }

    /// Paints the drawing into the current (flipped) graphics context.
    /// `paths` caches stroke outlines by item index between redraws.
    static func draw(_ document: InkNoteDocument, current: InkStroke? = nil, paths: [CGPath] = []) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for (index, item) in document.items.enumerated() {
            let path = paths.indices.contains(index) ? paths[index] : InkGeometry.path(for: item.stroke)
            draw(item.stroke, path: path, at: CGPoint(x: item.x, y: item.y), in: context)
        }
        for marker in document.markers { EditorImageRenderer.drawMarker(markerItem(marker)) }
        if let current { draw(current, path: InkGeometry.path(for: current), at: .zero, in: context) }
    }

    static func draw(_ stroke: InkStroke, path: CGPath, at origin: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.addPath(path)
        let color = NSColor(hex: stroke.color).cgColor
        switch stroke.tool {
        case .highlighter, .shape:
            context.setStrokeColor(stroke.tool == .highlighter ? color.copy(alpha: 0.36) ?? color : color)
            context.setLineWidth(stroke.width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        case .pen:
            context.setFillColor(color)
            context.fillPath()
        }
        context.restoreGState()
    }

    /// The part of the canvas that is saved: the drawing plus a margin, at
    /// least `minimumWidth` wide. `nil` for a text-only note.
    static func canvasRect(for document: InkNoteDocument) -> CGRect? {
        let bounds = drawingBounds(document)
        guard !bounds.isNull else { return nil }
        var rect = bounds.insetBy(dx: -margin, dy: -margin)
        if rect.width < minimumWidth {
            rect = rect.insetBy(dx: -(minimumWidth - rect.width) / 2, dy: 0)
        }
        return rect.integral
    }

    /// The picture that is saved and copied, or `nil` for an empty note.
    static func image(for document: InkNoteDocument) -> NSImage? {
        guard !document.isEmpty else { return nil }
        let base: NSImage
        if let rect = canvasRect(for: document) {
            guard let drawing = renderCanvas(document, rect: rect) else { return nil }
            base = drawing
        } else {
            // A text-only note is just the Note box; a hairline in its own
            // color gives the burn something to sit under.
            guard let strip = solidImage(width: minimumWidth * scale, height: 1,
                                         color: WorkflowNoteRenderer.noteBackgroundColor) else { return nil }
            base = strip
        }
        let note = document.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return base }
        // Notes keep their lines: paragraphs and the "1: …" marker lines.
        return WorkflowNoteRenderer.burn(note: note, into: base, keepingLineBreaks: true)
    }

    /// PNG bytes with the editable note embedded, so ⌥⇧2 reopens it.
    static func pngData(for document: InkNoteDocument) -> Data? {
        guard let image = image(for: document),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return nil }
        return PNGMetadata.embed(intoPNG: png, inkNote: document)
    }

    private static func renderCanvas(_ document: InkNoteDocument, rect: CGRect) -> NSImage? {
        guard let width = ImageSafety.pixelLength(rect.width * scale), let height = ImageSafety.pixelLength(rect.height * scale),
              let rep = ImageSafety.makeBitmapRep(pixelsWide: width, pixelsHigh: height),
              let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = bitmap.cgContext
        // Flip to the canvas's top-left origin so markers' numerals draw upright.
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: scale, y: -scale)
        cg.translateBy(x: -rect.minX, y: -rect.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        background.setFill()
        rect.fill()
        draw(document)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private static func solidImage(width: CGFloat, height: CGFloat, color: NSColor) -> NSImage? {
        guard let pixelsWide = ImageSafety.pixelLength(width), let pixelsHigh = ImageSafety.pixelLength(height),
              let rep = ImageSafety.makeBitmapRep(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
        image.addRepresentation(rep)
        return image
    }
}

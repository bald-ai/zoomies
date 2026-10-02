import AppKit

/// Draws a note: the same code paints the editor page and the saved PNG, so
/// the picture an agent gets is exactly what was on screen. The page is the
/// note's text in a fixed column with the drawing over it; the marker lines
/// ("1: …") are burned in below it, like a screenshot note.
///
/// Page coordinates put the text column's top-left corner at the origin.
enum InkNoteRenderer {
    static let background = NSColor(srgbRed: 0.094, green: 0.098, blue: 0.118, alpha: 1)
    static let markerDiameter: CGFloat = 28
    /// The text column; fixed, so lines never rewrap under the drawing.
    static let columnWidth: CGFloat = 640
    /// Space kept around the page's content, on screen and in the saved picture.
    static let margin: CGFloat = 40
    static let scale: CGFloat = 2

    static let textAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        return [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor(white: 0.92, alpha: 1), .paragraphStyle: paragraph]
    }()

    /// The note's typed text, which fills the page.
    static func pageText(_ document: InkNoteDocument) -> String {
        MarkerNoteLogic.split(document.note).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The marker lines, which go in the Note box.
    static func markerLines(_ document: InkNoteDocument) -> String {
        MarkerNoteLogic.split(document.note).markerLines
    }

    static func textRect(for text: String) -> CGRect {
        guard !text.isEmpty else { return .null }
        let size = (text as NSString).boundingRect(with: NSSize(width: columnWidth, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textAttributes)
        return CGRect(x: 0, y: 0, width: columnWidth, height: ceil(size.height))
    }

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

    /// Everything on the page, or `.null` for an empty one.
    static func contentBounds(_ document: InkNoteDocument) -> CGRect {
        document.items.map(itemBounds).reduce(textRect(for: pageText(document))) { $0.union($1) }
            .union(document.markers.map(markerBounds).reduce(CGRect.null) { $0.union($1) })
    }

    /// Paints the page into the current (flipped) graphics context: text,
    /// then ink, then markers. `paths` caches stroke outlines by item index.
    static func draw(_ document: InkNoteDocument, current: InkStroke? = nil, paths: [CGPath] = []) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let text = pageText(document)
        if !text.isEmpty {
            (text as NSString).draw(with: textRect(for: text), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: textAttributes)
        }
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

    /// The part of the page that is saved: its content plus a margin, at
    /// least as wide as the text column. `nil` for an empty page.
    static func canvasRect(for document: InkNoteDocument) -> CGRect? {
        let bounds = contentBounds(document)
        guard !bounds.isNull else { return nil }
        var rect = bounds.insetBy(dx: -margin, dy: -margin)
        let minimumWidth = columnWidth + margin * 2
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
            guard let page = renderCanvas(document, rect: rect) else { return nil }
            base = page
        } else {
            // Only marker lines, with nothing on the page: a hairline in the
            // Note box's color gives the burn something to sit under.
            guard let strip = solidImage(width: (columnWidth + margin * 2) * scale, height: 1,
                                         color: WorkflowNoteRenderer.noteBackgroundColor) else { return nil }
            base = strip
        }
        let lines = markerLines(document)
        guard !lines.isEmpty else { return base }
        return WorkflowNoteRenderer.burn(note: lines, into: base, keepingLineBreaks: true)
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
        // Flip to the page's top-left origin so text and numerals draw upright.
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

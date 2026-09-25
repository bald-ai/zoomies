import AppKit

/// A base image plus its committed annotations in canvas coordinates.
///
/// This is the value the editor canvas mutates and `EditorImageRenderer`
/// composites. The save workflow rebuilds one directly from persisted state so
/// an annotated image can be re-rendered without constructing an editor view.
struct EditorDrawing {
    /// Committed annotation kinds, in draw order.
    enum Item {
        case pen(points: [NSPoint], color: NSColor, lineWidth: CGFloat)
        case arrow(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat)
        case rect(rect: NSRect, color: NSColor, lineWidth: CGFloat)
        case ellipse(rect: NSRect, color: NSColor, lineWidth: CGFloat)
        case text(TextItem)
        case marker(MarkerItem)
        case image(image: NSImage, rect: NSRect)
        case erase(rect: NSRect)
    }

    struct TextItem {
        var text: String
        var origin: NSPoint // top-left in view coordinates
        var color: NSColor
        var fontSize: CGFloat
    }

    struct MarkerItem {
        /// Largest supported marker number. Bounds serialized state, inline
        /// editing, and next-number calculation so numbering can neither wrap
        /// nor overflow Int.
        static let maxNumber = 999_999

        var number: Int
        var center: NSPoint
        var color: NSColor
        /// Capsule height in canvas points; created with the same calculation
        /// as text font size so markers scale identically under zoom/export.
        var diameter: CGFloat
    }

    /// Initial gap between the canvas edge and the base image, in points.
    static let canvasEdgeInset: CGFloat = 24.0

    var baseImage: NSImage
    /// Canvas-space origin of the base image's top-left corner.
    var baseImageOrigin: NSPoint
    var items: [Item]

    /// The base image's rect in canvas coordinates.
    var baseImageBounds: NSRect {
        NSRect(x: baseImageOrigin.x, y: baseImageOrigin.y, width: baseImage.size.width, height: baseImage.size.height)
    }
}

extension EditorDrawing {
    /// Restores a validated persisted state into a runtime drawing.
    ///
    /// The base is the state's own decoded image when available, otherwise
    /// `fallbackBaseImage` (e.g. a pending composite or the flattened file
    /// image). Items are decoded once and rebased onto `baseImageOrigin` using
    /// the state's saved base origin; legacy states without one keep their
    /// stored coordinates. Callers decide validity with
    /// `EditorCanvasState.isSafeToRestore()` before restoring.
    init(restoring state: EditorCanvasState,
         baseImageOrigin: NSPoint = NSPoint(x: EditorDrawing.canvasEdgeInset, y: EditorDrawing.canvasEdgeInset),
         fallbackBaseImage: NSImage) {
        self.baseImage = NSImage(data: state.baseImagePNG) ?? fallbackBaseImage
        self.baseImageOrigin = baseImageOrigin
        var restored = state.items.compactMap(Item.init(stateItem:))
        if let savedBaseImageOrigin = state.baseImageOrigin?.nsPoint {
            restored = EditorImageRenderer.shiftedItems(restored,
                                                      byX: baseImageOrigin.x - savedBaseImageOrigin.x,
                                                      byY: baseImageOrigin.y - savedBaseImageOrigin.y)
        }
        self.items = restored
    }
}

/// Committed-annotation drawing primitives, visual bounds, and offscreen
/// compositing shared by the editor canvas and the save workflow.
///
/// Item drawing writes into the current `NSGraphicsContext`; compositing uses
/// its own bitmap context. There is no view, window, event handling, or
/// session state here.
enum EditorImageRenderer {
    static let textPadding = NSSize(width: 6, height: 4)
    static let arrowHeadLength: CGFloat = 14.0
    static let arrowHeadAngle: CGFloat = .pi / 6 // 30°

    // MARK: - Compositing

    /// Renders the base image and committed items into a new bitmap-backed
    /// image, cropped to `cropRect` in canvas coordinates.
    static func compositeImage(of drawing: EditorDrawing, croppingTo cropRect: NSRect) -> NSImage {
        let normalizedCrop = normalizedRect(cropRect)

        // Render at the base image's native pixel resolution rather than the
        // screen's backing scale. `NSImage.lockFocus` rasterizes at the current
        // screen scale (2x on Retina), which silently doubled every image that
        // passed through the editor. Drawing into an explicit bitmap keeps the
        // edited image at the same resolution it came in with.
        let pixelScale = baseImagePixelScale(of: drawing.baseImage)
        let rawWidth = ImageSafety.pixelLength(normalizedCrop.width * pixelScale) ?? 0
        let rawHeight = ImageSafety.pixelLength(normalizedCrop.height * pixelScale) ?? 0
        let pixelWidth = max(1, rawWidth)
        let pixelHeight = max(1, rawHeight)

        guard let rep = ImageSafety.makeBitmapRep(pixelsWide: pixelWidth, pixelsHigh: pixelHeight),
              let bitmapContext = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        // Map the point-sized canvas coordinates onto the pixel-sized backing.
        rep.size = normalizedCrop.size

        // Reproduce the canvas view's flipped (top-left origin) coordinate space
        // so the base image and annotations render exactly as they do on screen.
        let context = NSGraphicsContext(cgContext: bitmapContext.cgContext, flipped: true)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: normalizedCrop.height)
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: normalizedCrop.size).fill()

        let translation = NSAffineTransform()
        translation.translateX(by: -normalizedCrop.minX, yBy: -normalizedCrop.minY)
        translation.concat()

        drawing.baseImage.draw(in: drawing.baseImageBounds,
                               from: .zero,
                               operation: .sourceOver,
                               fraction: 1.0,
                               respectFlipped: true,
                               hints: nil)

        for item in drawing.items {
            draw(item: item)
        }

        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: normalizedCrop.size)
        result.addRepresentation(rep)
        return result
    }

    /// Union of the base image and every item's visual bounds, normalized to
    /// whole canvas points. This is the full-export crop.
    static func exportBounds(of drawing: EditorDrawing) -> NSRect {
        var unionRect = drawing.baseImageBounds
        for item in drawing.items {
            guard let itemBounds = bounds(for: item) else { continue }
            unionRect = unionRect.union(itemBounds)
        }
        return normalizedRect(unionRect)
    }

    /// Points-to-pixels ratio of the base image, so edited output keeps the
    /// screenshot's native resolution instead of the screen's backing scale.
    private static func baseImagePixelScale(of image: NSImage) -> CGFloat {
        let pointWidth = image.size.width
        guard pointWidth > 0 else { return 1 }
        let scale = baseImagePixelSize(of: image).width / pointWidth
        return scale > 0 ? scale : 1
    }

    private static func baseImagePixelSize(of image: NSImage) -> NSSize {
        let largest = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max(by: { lhs, rhs in
                (ImageSafety.pixelCount(width: lhs.pixelsWide, height: lhs.pixelsHigh) ?? 0)
                    < (ImageSafety.pixelCount(width: rhs.pixelsWide, height: rhs.pixelsHigh) ?? 0)
            })
        if let largest {
            return NSSize(width: CGFloat(largest.pixelsWide), height: CGFloat(largest.pixelsHigh))
        }
        return image.size
    }

    // MARK: - Committed item drawing

    /// Draws one committed item into the current graphics context.
    static func draw(item: EditorDrawing.Item) {
        switch item {
        case .pen(let points, let color, let lineWidth):
            drawPen(points: points, color: color, lineWidth: lineWidth, isPreview: false)
        case .arrow(let start, let end, let color, let lineWidth):
            drawArrow(from: start, to: end, color: color, lineWidth: lineWidth, isPreview: false)
        case .rect(let rect, let color, let lineWidth):
            drawRect(rect, color: color, lineWidth: lineWidth, isPreview: false)
        case .ellipse(let rect, let color, let lineWidth):
            drawEllipse(rect, color: color, lineWidth: lineWidth, isPreview: false)
        case .text(let item):
            drawText(item)
        case .marker(let item):
            drawMarker(item, isPreview: false)
        case .image(let image, let rect):
            drawImage(image, in: rect)
        case .erase(let rect):
            drawErase(rect)
        }
    }

    static func drawImage(_ image: NSImage, in rect: NSRect) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    }

    static func drawErase(_ rect: NSRect) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        // destinationOut uses source alpha; use an opaque source to actually clear.
        NSColor.black.setFill()
        rect.fill(using: .destinationOut)
    }

    static func drawPen(points: [NSPoint], color: NSColor, lineWidth: CGFloat, isPreview: Bool) {
        guard points.count > 1 else { return }

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // Simple smoothing by drawing through midpoints.
        path.move(to: points[0])
        if points.count == 2 {
            path.line(to: points[1])
        } else {
            for i in 1..<points.count {
                let mid = NSPoint(x: (points[i - 1].x + points[i].x) / 2,
                                   y: (points[i - 1].y + points[i].y) / 2)
                path.curve(to: mid, controlPoint1: points[i - 1], controlPoint2: points[i])
            }
            if let last = points.last {
                path.line(to: last)
            }
        }

        (isPreview ? color.withAlphaComponent(0.7) : color).setStroke()
        path.stroke()
    }

    static func drawRect(_ rect: NSRect, color: NSColor, lineWidth: CGFloat, isPreview: Bool) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        (isPreview ? color.withAlphaComponent(0.7) : color).setStroke()
        path.stroke()
    }

    static func drawEllipse(_ rect: NSRect, color: NSColor, lineWidth: CGFloat, isPreview: Bool) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = lineWidth
        (isPreview ? color.withAlphaComponent(0.7) : color).setStroke()
        path.stroke()
    }

    static func drawArrow(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat, isPreview: Bool) {
        guard distance(from: start, to: end) >= 2 else { return }

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.move(to: start)
        path.line(to: end)

        let (point1, point2) = arrowHeadPoints(from: start, to: end)

        path.move(to: end)
        path.line(to: point1)
        path.move(to: end)
        path.line(to: point2)

        (isPreview ? color.withAlphaComponent(0.7) : color).setStroke()
        path.stroke()
    }

    static func drawText(_ item: EditorDrawing.TextItem) {
        let attributes = textAttributes(for: item)
        let rect = textBounds(for: item).insetBy(dx: textPadding.width, dy: textPadding.height)
        (item.text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }

    static func textAttributes(for item: EditorDrawing.TextItem) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: item.fontSize, weight: .regular),
            .foregroundColor: item.color
        ]
    }

    static func textBounds(for item: EditorDrawing.TextItem) -> NSRect {
        let size = annotationTextSize(for: item.text, fontSize: item.fontSize)
        let width = max(size.width + textPadding.width * 2, 60)
        let height = max(size.height + textPadding.height * 2, 28)
        return NSRect(x: item.origin.x, y: item.origin.y, width: width, height: height)
    }

    // MARK: - Measurement caches

    /// Bounds, dirty-rect checks, and hit tests re-measure the same strings on
    /// every event, so measurements are memoized. Each cache is tied to one
    /// fixed font family so its key only needs the size and the string; the
    /// regular and bold caches can never collide. `NSCache` is thread-safe and
    /// `countLimit` keeps editing many distinct strings from growing it unbounded.
    private static func measurementCache() -> NSCache<NSString, NSValue> {
        let cache = NSCache<NSString, NSValue>()
        cache.countLimit = 512
        return cache
    }

    /// Text item sizes, always measured with `systemFont(ofSize:weight: .regular)`.
    private static let annotationTextSizeCache = measurementCache()
    /// Marker label sizes, always measured with `markerFont(forDiameter:)` (bold).
    private static let markerLabelSizeCache = measurementCache()

    private static func measurementKey(_ size: CGFloat, _ text: String) -> NSString {
        "\(size)\u{0}\(text)" as NSString
    }

    private static func annotationTextSize(for text: String, fontSize: CGFloat) -> NSSize {
        let key = measurementKey(fontSize, text)
        if let cached = annotationTextSizeCache.object(forKey: key) {
            return cached.sizeValue
        }
        let size = textContentSize(for: text, font: NSFont.systemFont(ofSize: fontSize, weight: .regular))
        annotationTextSizeCache.setObject(NSValue(size: size), forKey: key)
        return size
    }

    private static func markerLabelSize(number: Int, diameter: CGFloat) -> NSSize {
        let key = measurementKey(diameter, String(number))
        if let cached = markerLabelSizeCache.object(forKey: key) {
            return cached.sizeValue
        }
        let size = (String(number) as NSString).size(withAttributes: [.font: markerFont(forDiameter: diameter)])
        markerLabelSizeCache.setObject(NSValue(size: size), forKey: key)
        return size
    }

    static func textContentSize(for text: String, font: NSFont) -> NSSize {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var maxWidth: CGFloat = 0
        for line in lines {
            let lineSize = (String(line) as NSString).size(withAttributes: [.font: font])
            maxWidth = max(maxWidth, lineSize.width)
        }
        let lineHeight = font.boundingRectForFont.size.height
        let height = max(1, lines.count)
        return NSSize(width: maxWidth, height: lineHeight * CGFloat(height))
    }

    // MARK: - Numbered markers

    static func markerFont(forDiameter diameter: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: max(1, diameter * 0.5), weight: .bold)
    }

    static func markerOutlineWidth(forDiameter diameter: CGFloat) -> CGFloat {
        max(2, diameter * 0.06)
    }

    /// The filled capsule a marker occupies, centered on `item.center`.
    /// Single digits produce a circle; the width grows with the numeral so
    /// multi-digit numbers never clip.
    static func markerRect(for item: EditorDrawing.MarkerItem) -> NSRect {
        let diameter = item.diameter
        guard diameter > 0, item.number > 0 else {
            return NSRect(x: item.center.x, y: item.center.y, width: 0, height: 0)
        }
        let textSize = markerLabelSize(number: item.number, diameter: diameter)
        let width = max(diameter, ceil(textSize.width) + diameter * 0.4)
        return NSRect(x: item.center.x - width / 2,
                      y: item.center.y - diameter / 2,
                      width: width,
                      height: diameter)
    }

    /// Marker bounds including the contrast outline, for dirty-rect and
    /// export-crop calculations.
    static func markerBounds(for item: EditorDrawing.MarkerItem) -> NSRect {
        let padding = markerOutlineWidth(forDiameter: item.diameter) / 2 + 1
        return markerRect(for: item).insetBy(dx: -padding, dy: -padding)
    }

    static func markerPath(for item: EditorDrawing.MarkerItem) -> NSBezierPath {
        let rect = markerRect(for: item)
        let radius = rect.height / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    static func drawMarker(_ item: EditorDrawing.MarkerItem, isPreview: Bool = false) {
        let rect = markerRect(for: item)
        guard rect.width >= 1, rect.height >= 1, item.number > 0 else { return }

        // Hollow marker: transparent interior, annotation-colored outline and
        // numeral.
        let content = isPreview ? item.color.withAlphaComponent(0.7) : item.color

        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        path.lineWidth = markerOutlineWidth(forDiameter: item.diameter)
        content.setStroke()
        path.stroke()

        let font = markerFont(forDiameter: item.diameter)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: content
        ]
        let label = String(item.number) as NSString
        let textSize = markerLabelSize(number: item.number, diameter: item.diameter)
        let textRect = NSRect(x: rect.midX - textSize.width / 2,
                              y: rect.midY - textSize.height / 2,
                              width: textSize.width,
                              height: textSize.height)
        label.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
    }

    // MARK: - Visual bounds

    /// The canvas-space bounds an item's drawing can touch, matching the
    /// geometry used to render it. `nil` for items that draw nothing.
    static func bounds(for item: EditorDrawing.Item) -> NSRect? {
        switch item {
        case .pen(let points, _, let lineWidth):
            return boundsForPoints(points, padding: lineWidth / 2)
        case .arrow(let start, let end, _, let lineWidth):
            guard distance(from: start, to: end) >= 2 else { return nil }
            return boundsForArrow(start: start, end: end, lineWidth: lineWidth)
        case .rect(let rect, _, let lineWidth), .ellipse(let rect, _, let lineWidth):
            return rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .text(let textItem):
            return textBounds(for: textItem)
        case .marker(let markerItem):
            return markerBounds(for: markerItem)
        case .image(_, let rect), .erase(let rect):
            return rect
        }
    }

    static func boundsForPoints(_ points: [NSPoint], padding: CGFloat) -> NSRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return NSRect(x: minX - padding,
                      y: minY - padding,
                      width: (maxX - minX) + (padding * 2),
                      height: (maxY - minY) + (padding * 2))
    }

    static func boundsForArrow(start: NSPoint, end: NSPoint, lineWidth: CGFloat) -> NSRect {
        let (wing1, wing2) = arrowHeadPoints(from: start, to: end)
        let minX = min(start.x, end.x, wing1.x, wing2.x)
        let minY = min(start.y, end.y, wing1.y, wing2.y)
        let maxX = max(start.x, end.x, wing1.x, wing2.x)
        let maxY = max(start.y, end.y, wing1.y, wing2.y)
        let padding = lineWidth / 2
        return NSRect(x: minX - padding,
                      y: minY - padding,
                      width: (maxX - minX) + (padding * 2),
                      height: (maxY - minY) + (padding * 2))
    }

    /// The two arrowhead wing tips for a stroke from `start` to `end`. Shared
    /// by arrow drawing, bounds, and hit-testing so they never disagree.
    static func arrowHeadPoints(from start: NSPoint, to end: NSPoint) -> (NSPoint, NSPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)
        let point1 = NSPoint(x: end.x - arrowHeadLength * cos(angle - arrowHeadAngle),
                             y: end.y - arrowHeadLength * sin(angle - arrowHeadAngle))
        let point2 = NSPoint(x: end.x - arrowHeadLength * cos(angle + arrowHeadAngle),
                             y: end.y - arrowHeadLength * sin(angle + arrowHeadAngle))
        return (point1, point2)
    }

    // MARK: - Geometry helpers

    static func normalizedRect(_ rect: NSRect) -> NSRect {
        let minX = floor(rect.minX)
        let minY = floor(rect.minY)
        let maxX = ceil(rect.maxX)
        let maxY = ceil(rect.maxY)
        return NSRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    static func shiftedPoint(_ point: NSPoint, byX dx: CGFloat, byY dy: CGFloat) -> NSPoint {
        NSPoint(x: point.x + dx, y: point.y + dy)
    }

    static func shiftedRect(_ rect: NSRect, byX dx: CGFloat, byY dy: CGFloat) -> NSRect {
        NSRect(x: rect.origin.x + dx, y: rect.origin.y + dy, width: rect.width, height: rect.height)
    }

    static func shiftedItems(_ source: [EditorDrawing.Item], byX dx: CGFloat, byY dy: CGFloat) -> [EditorDrawing.Item] {
        source.map { shiftedItem($0, byX: dx, byY: dy) }
    }

    static func shiftedItem(_ item: EditorDrawing.Item, byX dx: CGFloat, byY dy: CGFloat) -> EditorDrawing.Item {
        switch item {
        case .pen(let points, let color, let lineWidth):
            return .pen(points: points.map { shiftedPoint($0, byX: dx, byY: dy) }, color: color, lineWidth: lineWidth)
        case .arrow(let start, let end, let color, let lineWidth):
            return .arrow(start: shiftedPoint(start, byX: dx, byY: dy),
                          end: shiftedPoint(end, byX: dx, byY: dy),
                          color: color,
                          lineWidth: lineWidth)
        case .rect(let rect, let color, let lineWidth):
            return .rect(rect: shiftedRect(rect, byX: dx, byY: dy), color: color, lineWidth: lineWidth)
        case .ellipse(let rect, let color, let lineWidth):
            return .ellipse(rect: shiftedRect(rect, byX: dx, byY: dy), color: color, lineWidth: lineWidth)
        case .text(var textItem):
            textItem.origin = shiftedPoint(textItem.origin, byX: dx, byY: dy)
            return .text(textItem)
        case .marker(var markerItem):
            markerItem.center = shiftedPoint(markerItem.center, byX: dx, byY: dy)
            return .marker(markerItem)
        case .image(let image, let rect):
            return .image(image: image, rect: shiftedRect(rect, byX: dx, byY: dy))
        case .erase(let rect):
            return .erase(rect: shiftedRect(rect, byX: dx, byY: dy))
        }
    }

    static func distance(from p1: NSPoint, to p2: NSPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
}

extension EditorDrawing.Item {
    init?(stateItem: EditorCanvasState.Item) {
        switch stateItem {
        case .pen(let points, let color, let lineWidth):
            self = .pen(points: points.map(\.nsPoint), color: color.nsColor, lineWidth: lineWidth)
        case .arrow(let start, let end, let color, let lineWidth):
            self = .arrow(start: start.nsPoint, end: end.nsPoint, color: color.nsColor, lineWidth: lineWidth)
        case .rect(let rect, let color, let lineWidth):
            self = .rect(rect: rect.nsRect, color: color.nsColor, lineWidth: lineWidth)
        case .ellipse(let rect, let color, let lineWidth):
            self = .ellipse(rect: rect.nsRect, color: color.nsColor, lineWidth: lineWidth)
        case .text(let text):
            let item = EditorDrawing.TextItem(text: text.text,
                                              origin: text.origin.nsPoint,
                                              color: text.color.nsColor,
                                              fontSize: text.fontSize)
            self = .text(item)
        case .marker(let marker):
            self = .marker(EditorDrawing.MarkerItem(number: marker.number,
                                                    center: marker.center.nsPoint,
                                                    color: marker.color.nsColor,
                                                    diameter: marker.diameter))
        case .image(let pngData, let rect):
            guard let image = NSImage(data: pngData) else { return nil }
            self = .image(image: image, rect: rect.nsRect)
        case .erase(let rect):
            self = .erase(rect: rect.nsRect)
        }
    }

    var stateItem: EditorCanvasState.Item? {
        switch self {
        case .pen(let points, let color, let lineWidth):
            return .pen(points: points.map(EditorCanvasState.Point.init),
                        color: EditorCanvasState.Color(color),
                        lineWidth: lineWidth)
        case .arrow(let start, let end, let color, let lineWidth):
            return .arrow(start: EditorCanvasState.Point(start),
                          end: EditorCanvasState.Point(end),
                          color: EditorCanvasState.Color(color),
                          lineWidth: lineWidth)
        case .rect(let rect, let color, let lineWidth):
            return .rect(rect: EditorCanvasState.Rect(rect),
                         color: EditorCanvasState.Color(color),
                         lineWidth: lineWidth)
        case .ellipse(let rect, let color, let lineWidth):
            return .ellipse(rect: EditorCanvasState.Rect(rect),
                            color: EditorCanvasState.Color(color),
                            lineWidth: lineWidth)
        case .text(let text):
            return .text(EditorCanvasState.Text(text: text.text,
                                                origin: EditorCanvasState.Point(text.origin),
                                                color: EditorCanvasState.Color(text.color),
                                                fontSize: text.fontSize))
        case .marker(let marker):
            return .marker(EditorCanvasState.Marker(number: marker.number,
                                                    center: EditorCanvasState.Point(marker.center),
                                                    color: EditorCanvasState.Color(marker.color),
                                                    diameter: marker.diameter))
        case .image(let image, let rect):
            guard let pngData = ImageEncoding.pngData(from: image) else { return nil }
            return .image(pngData: pngData, rect: EditorCanvasState.Rect(rect))
        case .erase(let rect):
            return .erase(rect: EditorCanvasState.Rect(rect))
        }
    }

}

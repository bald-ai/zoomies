import AppKit
import Foundation

struct EditorCanvasState: Codable {
    struct Point: Codable, Equatable {
        var x: CGFloat
        var y: CGFloat

        init(_ point: NSPoint) {
            self.x = point.x
            self.y = point.y
        }

        var nsPoint: NSPoint {
            NSPoint(x: x, y: y)
        }
    }

    struct Rect: Codable, Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        init(_ rect: NSRect) {
            self.x = rect.origin.x
            self.y = rect.origin.y
            self.width = rect.width
            self.height = rect.height
        }

        var nsRect: NSRect {
            NSRect(x: x, y: y, width: width, height: height)
        }
    }

    struct Color: Codable, Equatable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat

        init(_ color: NSColor) {
            let rgb = color.usingColorSpace(.deviceRGB) ?? color
            self.red = rgb.redComponent
            self.green = rgb.greenComponent
            self.blue = rgb.blueComponent
            self.alpha = rgb.alphaComponent
        }

        var nsColor: NSColor {
            NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
        }
    }

    struct Text: Codable, Equatable {
        var text: String
        var origin: Point
        var color: Color
        var fontSize: CGFloat
    }

    enum Item: Codable, Equatable {
        case pen(points: [Point], color: Color, lineWidth: CGFloat)
        case arrow(start: Point, end: Point, color: Color, lineWidth: CGFloat)
        case rect(rect: Rect, color: Color, lineWidth: CGFloat)
        case ellipse(rect: Rect, color: Color, lineWidth: CGFloat)
        case text(Text)
        case image(pngData: Data, rect: Rect)
        case erase(rect: Rect)

        private enum CodingKeys: String, CodingKey {
            case type
            case points
            case start
            case end
            case color
            case lineWidth
            case rect
            case text
            case pngData
        }

        private enum Kind: String, Codable {
            case pen
            case arrow
            case rect
            case ellipse
            case text
            case image
            case erase
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(Kind.self, forKey: .type)
            switch type {
            case .pen:
                self = .pen(points: try container.decode([Point].self, forKey: .points),
                            color: try container.decode(Color.self, forKey: .color),
                            lineWidth: try container.decode(CGFloat.self, forKey: .lineWidth))
            case .arrow:
                self = .arrow(start: try container.decode(Point.self, forKey: .start),
                              end: try container.decode(Point.self, forKey: .end),
                              color: try container.decode(Color.self, forKey: .color),
                              lineWidth: try container.decode(CGFloat.self, forKey: .lineWidth))
            case .rect:
                self = .rect(rect: try container.decode(Rect.self, forKey: .rect),
                             color: try container.decode(Color.self, forKey: .color),
                             lineWidth: try container.decode(CGFloat.self, forKey: .lineWidth))
            case .ellipse:
                self = .ellipse(rect: try container.decode(Rect.self, forKey: .rect),
                                color: try container.decode(Color.self, forKey: .color),
                                lineWidth: try container.decode(CGFloat.self, forKey: .lineWidth))
            case .text:
                self = .text(try container.decode(Text.self, forKey: .text))
            case .image:
                self = .image(pngData: try container.decode(Data.self, forKey: .pngData),
                              rect: try container.decode(Rect.self, forKey: .rect))
            case .erase:
                self = .erase(rect: try container.decode(Rect.self, forKey: .rect))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .pen(let points, let color, let lineWidth):
                try container.encode(Kind.pen, forKey: .type)
                try container.encode(points, forKey: .points)
                try container.encode(color, forKey: .color)
                try container.encode(lineWidth, forKey: .lineWidth)
            case .arrow(let start, let end, let color, let lineWidth):
                try container.encode(Kind.arrow, forKey: .type)
                try container.encode(start, forKey: .start)
                try container.encode(end, forKey: .end)
                try container.encode(color, forKey: .color)
                try container.encode(lineWidth, forKey: .lineWidth)
            case .rect(let rect, let color, let lineWidth):
                try container.encode(Kind.rect, forKey: .type)
                try container.encode(rect, forKey: .rect)
                try container.encode(color, forKey: .color)
                try container.encode(lineWidth, forKey: .lineWidth)
            case .ellipse(let rect, let color, let lineWidth):
                try container.encode(Kind.ellipse, forKey: .type)
                try container.encode(rect, forKey: .rect)
                try container.encode(color, forKey: .color)
                try container.encode(lineWidth, forKey: .lineWidth)
            case .text(let text):
                try container.encode(Kind.text, forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let pngData, let rect):
                try container.encode(Kind.image, forKey: .type)
                try container.encode(pngData, forKey: .pngData)
                try container.encode(rect, forKey: .rect)
            case .erase(let rect):
                try container.encode(Kind.erase, forKey: .type)
                try container.encode(rect, forKey: .rect)
            }
        }
    }

    var version: Int = 2
    var baseImagePNG: Data
    /// Canvas position of the base image when the items were serialized.
    ///
    /// Annotation coordinates are measured in the canvas, not in the image.
    /// The editor may recenter the canvas when it is reopened, so restoring this
    /// origin lets it preserve each item's position relative to the image.
    /// `nil` keeps states written by version 1 compatible.
    var baseImageOrigin: Point? = nil
    var items: [Item]
}

extension EditorCanvasState {
    typealias SafetyLimits = ImageSafetyLimits

    /// True when this state is safe to restore into the editor.
    func isSafeToRestore(limits: SafetyLimits = .runtime) -> Bool {
        guard ImageSafety.isSafePNG(baseImagePNG, limits: limits),
              baseImagePNG.count <= limits.maxEmbeddedImageBytes else {
            return false
        }
        if let origin = baseImageOrigin, !origin.isSafe(limits: limits) {
            return false
        }
        guard items.count <= limits.maxItemCount,
              items.allSatisfy({ $0.isSafeToRestore(limits: limits) }) else {
            return false
        }
        return hasSafeEstimatedExportArea(limits: limits)
    }

    private func hasSafeEstimatedExportArea(limits: SafetyLimits) -> Bool {
        guard let dimensions = PNGMetadata.pixelDimensions(ofPNG: baseImagePNG) else {
            return false
        }
        let origin = baseImageOrigin?.nsPoint ?? .zero
        var union = NSRect(x: origin.x,
                           y: origin.y,
                           width: CGFloat(dimensions.width),
                           height: CGFloat(dimensions.height))
        for item in items {
            guard let bounds = item.estimatedCanvasBounds(limits: limits) else {
                return false
            }
            union = union.union(bounds)
        }
        guard union.width.isFinite, union.height.isFinite,
              let width = ImageSafety.pixelLength(union.width),
              let height = ImageSafety.pixelLength(union.height) else {
            return false
        }
        return ImageSafety.isSafePixelSize(width: width,
                                           height: height,
                                           limits: limits,
                                           maxPixels: limits.maxExportPixelArea)
    }
}

private extension EditorCanvasState.Point {
    func isSafe(limits: EditorCanvasState.SafetyLimits) -> Bool {
        x.isFinite && y.isFinite
            && abs(x) <= limits.maxAbsoluteCoordinate
            && abs(y) <= limits.maxAbsoluteCoordinate
    }
}

private extension EditorCanvasState.Rect {
    func isSafe(limits: EditorCanvasState.SafetyLimits) -> Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && abs(x) <= limits.maxAbsoluteCoordinate
            && abs(y) <= limits.maxAbsoluteCoordinate
            && width > 0 && height > 0
            && width <= CGFloat(limits.maxDimension)
            && height <= CGFloat(limits.maxDimension)
    }
}

private extension EditorCanvasState.Color {
    var isSafe: Bool {
        red.isFinite && green.isFinite && blue.isFinite && alpha.isFinite
    }
}

private extension EditorCanvasState.Item {
    func isSafeToRestore(limits: EditorCanvasState.SafetyLimits) -> Bool {
        switch self {
        case .pen(let points, let color, let lineWidth):
            return points.count <= limits.maxPenPointCount
                && points.allSatisfy { $0.isSafe(limits: limits) }
                && color.isSafe
                && isSafeLineWidth(lineWidth, limits: limits)
        case .arrow(let start, let end, let color, let lineWidth):
            return start.isSafe(limits: limits)
                && end.isSafe(limits: limits)
                && color.isSafe
                && isSafeLineWidth(lineWidth, limits: limits)
        case .rect(let rect, let color, let lineWidth),
             .ellipse(let rect, let color, let lineWidth):
            return rect.isSafe(limits: limits)
                && color.isSafe
                && isSafeLineWidth(lineWidth, limits: limits)
        case .text(let text):
            return text.text.count <= limits.maxTextLength
                && text.origin.isSafe(limits: limits)
                && text.color.isSafe
                && text.fontSize.isFinite
                && text.fontSize > 0
                && text.fontSize <= limits.maxFontSize
        case .image(let pngData, let rect):
            return pngData.count <= limits.maxEmbeddedImageBytes
                && ImageSafety.isSafePNG(pngData, limits: limits)
                && rect.isSafe(limits: limits)
        case .erase(let rect):
            return rect.isSafe(limits: limits)
        }
    }

    func isSafeLineWidth(_ lineWidth: CGFloat, limits: EditorCanvasState.SafetyLimits) -> Bool {
        lineWidth.isFinite && lineWidth > 0 && lineWidth <= limits.maxLineWidth
    }

    func estimatedCanvasBounds(limits _: EditorCanvasState.SafetyLimits) -> NSRect? {
        switch self {
        case .pen(let points, _, let lineWidth):
            guard let first = points.first else { return nil }
            var union = NSRect(x: first.x, y: first.y, width: 0, height: 0)
            for point in points {
                union = union.union(NSRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            return union.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .arrow(let start, let end, _, let lineWidth):
            let union = NSRect(x: start.x, y: start.y, width: 0, height: 0)
                .union(NSRect(x: end.x, y: end.y, width: 0, height: 0))
            return union.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .rect(let rect, _, let lineWidth),
             .ellipse(let rect, _, let lineWidth):
            return rect.nsRect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .text(let text):
            let width = CGFloat(text.text.count) * text.fontSize
            let height = text.fontSize * 1.5
            guard width.isFinite, height.isFinite else { return nil }
            return NSRect(x: text.origin.x, y: text.origin.y, width: max(width, 1), height: max(height, 1))
        case .image(_, let rect), .erase(let rect):
            return rect.nsRect
        }
    }
}

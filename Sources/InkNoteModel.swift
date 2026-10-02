import CoreGraphics
import Foundation

/// One hand-drawn stroke. Points are relative to the stroke's own origin. A
/// negative pressure means the device reported none, so width follows speed.
/// A shape is straight segments of even width between its points.
struct InkStroke: Equatable {
    enum Tool: String, Codable { case pen, highlighter, shape }

    var tool: Tool
    var color: String
    var width: CGFloat
    var points: [InkPoint]

    var bounds: CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(x: first.x, y: first.y, width: 0, height: 0)
        for point in points.dropFirst() { rect = rect.union(CGRect(x: point.x, y: point.y, width: 0, height: 0)) }
        return rect
    }

    /// Moves the points so the stroke starts at its own top-left corner;
    /// returns where that corner was.
    mutating func localize() -> CGPoint {
        let origin = bounds.origin
        points = points.map { InkPoint(x: $0.x - origin.x, y: $0.y - origin.y, pressure: $0.pressure) }
        return origin
    }

    /// Snaps points to the 0.1 precision they are saved with, so a note in
    /// memory equals the note read back from disk.
    mutating func roundToSavedPrecision() {
        let round = { (value: CGFloat) in (value * 10).rounded() / 10 }
        points = points.map { InkPoint(x: round($0.x), y: round($0.y), pressure: round($0.pressure)) }
    }

    /// Measures to the segments, not just the points: a rectangle's sides
    /// are long and have points only at the corners.
    func hits(_ point: CGPoint, padding: CGFloat = 6) -> Bool {
        let radius = width / 2 + padding
        guard points.count > 1 else {
            return points.first.map { hypot($0.x - point.x, $0.y - point.y) < radius } ?? false
        }
        return zip(points, points.dropFirst()).contains { a, b in
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared)) : 0
            return hypot(a.x + t * dx - point.x, a.y + t * dy - point.y) < radius
        }
    }
}

/// The screenshot editor's shapes, drawn into a note as straight segments.
enum InkShape: CaseIterable {
    case line, arrow, rectangle, ellipse

    /// The points from a drag. `constrained` (Shift) makes a square or a
    /// circle, as in the screenshot editor.
    func points(from start: CGPoint, to end: CGPoint, constrained: Bool) -> [CGPoint] {
        switch self {
        case .line:
            return [start, end]
        case .arrow:
            // Ends on the tip, so the arrow pins to the text like a drawn one.
            let (wing1, wing2) = EditorImageRenderer.arrowHeadPoints(from: start, to: end)
            return [start, end, wing1, end, wing2, end]
        case .rectangle:
            let rect = Self.rect(from: start, to: end, constrained: constrained)
            return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.minY)]
        case .ellipse:
            let rect = Self.rect(from: start, to: end, constrained: constrained)
            return (0...72).map { step in
                let angle = CGFloat(step) / 72 * 2 * .pi
                return CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2)
            }
        }
    }

    private static func rect(from start: CGPoint, to end: CGPoint, constrained: Bool) -> CGRect {
        var dx = end.x - start.x, dy = end.y - start.y
        if constrained {
            let side = max(abs(dx), abs(dy))
            dx = dx >= 0 ? side : -side
            dy = dy >= 0 ? side : -side
        }
        return CGRect(x: start.x, y: start.y, width: dx, height: dy).standardized
    }
}

struct InkPoint: Equatable {
    var x: CGFloat
    var y: CGFloat
    var pressure: CGFloat
}

extension InkStroke: Codable {
    private enum CodingKeys: String, CodingKey { case tool, color, width, points }

    // Points flatten to [x, y, pressure, ...] rounded to 0.1 so notes stay small.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(Tool.self, forKey: .tool)
        color = try container.decode(String.self, forKey: .color)
        width = try container.decode(CGFloat.self, forKey: .width)
        let flat = try container.decode([CGFloat].self, forKey: .points)
        guard flat.count % 3 == 0 else {
            throw DecodingError.dataCorruptedError(forKey: .points, in: container, debugDescription: "Points must be x, y, pressure triples")
        }
        points = stride(from: 0, to: flat.count, by: 3).map { InkPoint(x: flat[$0], y: flat[$0 + 1], pressure: flat[$0 + 2]) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tool, forKey: .tool)
        try container.encode(color, forKey: .color)
        try container.encode(width, forKey: .width)
        let round = { (value: CGFloat) in (value * 10).rounded() / 10 }
        try container.encode(points.flatMap { [round($0.x), round($0.y), round($0.pressure)] }, forKey: .points)
    }
}

/// Everything needed to reopen a note: its text and its ink. Markers and ink
/// anchors are UTF-16 offsets into `text`; markers sit on U+FFFC characters.
struct InkNoteDocument: Codable, Equatable {
    struct Marker: Codable, Equatable {
        var index: Int
        var number: Int
    }

    struct Anchor: Codable, Equatable {
        var index: Int
        var id: String
    }

    /// `x`/`y` offset the stroke from its anchor character's top-left, or from
    /// the text column's top-left when the note had no text to pin to.
    struct Item: Codable, Equatable {
        var stroke: InkStroke
        var anchor: String?
        var x: CGFloat
        var y: CGFloat
    }

    static let maximumTextLength = 200_000
    static let maximumItems = 5_000
    static let maximumPoints = 400_000
    static let attachmentCharacter: Character = "\u{FFFC}"

    var version = 1
    var text: String
    var markers: [Marker] = []
    var anchors: [Anchor] = []
    var items: [Item] = []

    var isSafeToRestore: Bool {
        let units = Array(text.utf16)
        guard version == 1, units.count <= Self.maximumTextLength, items.count <= Self.maximumItems,
              items.reduce(0, { $0 + $1.stroke.points.count }) <= Self.maximumPoints else { return false }
        let range = 0..<units.count
        guard markers.allSatisfy({ range.contains($0.index) && units[$0.index] == 0xFFFC && $0.number > 0 }),
              anchors.allSatisfy({ range.contains($0.index) && !$0.id.isEmpty }) else { return false }
        return items.allSatisfy { item in
            item.x.isFinite && item.y.isFinite && item.stroke.width.isFinite && item.stroke.width > 0 && item.stroke.width <= 200
                && item.stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.pressure.isFinite }
        }
    }

    /// Starts a note from Markdown. Footnote anchors become marker circles and
    /// their definitions become circle lines at the end, so nothing is lost.
    static func fromMarkdown(_ markdown: String) -> InkNoteDocument {
        let source = MarkdownMarkerLogic.read(markdown)
        let main = source.mainText as NSString
        var text = ""
        var markers: [Marker] = []
        var cursor = 0
        func appendMarker(_ number: Int) {
            markers.append(Marker(index: text.utf16.count, number: number))
            text.append(attachmentCharacter)
        }
        for anchor in MarkdownMarkerLogic.anchors(in: source.mainText) {
            text += main.substring(with: NSRange(location: cursor, length: anchor.range.location - cursor))
            appendMarker(anchor.number)
            cursor = NSMaxRange(anchor.range)
        }
        text += main.substring(from: cursor)
        if !source.notes.isEmpty {
            while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
            if !text.isEmpty { text += "\n\n" }
            for (offset, number) in source.notes.keys.sorted().enumerated() {
                if offset > 0 { text += "\n" }
                appendMarker(number)
                text += " " + (source.notes[number] ?? "")
            }
        }
        return InkNoteDocument(text: text, markers: markers)
    }
}

/// Where a new stroke pins itself to the text.
enum InkAnchorLogic {
    /// Loops pin at their middle, flat lines at their left end, and anything
    /// else (an arrow, a tick) at the point where the pen lifted.
    static func anchorPoint(for points: [CGPoint]) -> CGPoint {
        guard let first = points.first, let last = points.last else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
        let closed = hypot(last.x - first.x, last.y - first.y) < max(rect.width, rect.height) * 0.35
        if closed { return CGPoint(x: rect.midX, y: rect.midY) }
        if rect.height < rect.width * 0.3 { return first.x < last.x ? first : last }
        return last
    }

    /// Moves back to the first character of the word containing `index`.
    static func wordStart(in text: NSString, at index: Int) -> Int {
        var position = min(max(index, 0), text.length)
        let whitespace = CharacterSet.whitespacesAndNewlines
        while position > 0, let scalar = UnicodeScalar(text.character(at: position - 1)), !whitespace.contains(scalar) {
            position -= 1
        }
        return position
    }

    /// A stroke drawn right after and right next to the previous one (an arrow
    /// head, a second underline) shares its anchor, so the two move as one.
    static func joinsPrevious(previous: CGRect, next: CGRect, elapsed: TimeInterval) -> Bool {
        guard elapsed < 1.5 else { return false }
        let dx = max(0, previous.minX - next.maxX, next.minX - previous.maxX)
        let dy = max(0, previous.minY - next.maxY, next.minY - previous.maxY)
        return hypot(dx, dy) < 16
    }
}

/// Turns stroke points into smooth shapes: pens become a filled outline whose
/// width follows pressure (or speed), highlighters a plain centerline.
enum InkGeometry {
    static func path(for stroke: InkStroke) -> CGPath {
        switch stroke.tool {
        case .pen: return outline(stroke.points, width: stroke.width)
        case .highlighter: return centerline(stroke.points)
        case .shape: return polyline(stroke.points)
        }
    }

    /// Straight segments with no smoothing, so corners stay sharp.
    static func polyline(_ points: [InkPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        return path
    }

    static func streamlined(_ raw: [InkPoint]) -> [InkPoint] {
        guard let first = raw.first, let last = raw.last else { return [] }
        var x = first.x, y = first.y
        var eased: [InkPoint] = raw.map { point in
            x += (point.x - x) * 0.6
            y += (point.y - y) * 0.6
            return InkPoint(x: x, y: y, pressure: point.pressure)
        }
        eased.append(last)
        var result = [eased[0]]
        for point in eased.dropFirst() {
            let previous = result[result.count - 1]
            if hypot(point.x - previous.x, point.y - previous.y) >= 0.7 { result.append(point) }
        }
        return result
    }

    static func outline(_ raw: [InkPoint], width size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = streamlined(raw)
        guard let first = points.first else { return path }
        guard points.count > 1 else {
            let radius = size * 0.55
            path.addEllipse(in: CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2))
            return path
        }
        var lengths: [CGFloat] = [0]
        for index in 1..<points.count {
            lengths.append(lengths[index - 1] + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y))
        }
        let total = lengths[lengths.count - 1]
        let tapers = total > size * 5
        let ease = { (t: CGFloat) in 1 - (1 - t) * (1 - t) }
        var simulated: CGFloat = 0.75
        let radii: [CGFloat] = points.indices.map { index in
            var pressure: CGFloat
            if points[index].pressure >= 0 {
                pressure = points[index].pressure
            } else {
                let step = index > 0 ? lengths[index] - lengths[index - 1] : 0
                let target = 1 - min(1, step / (size * 6)) * 0.6
                simulated += (target - simulated) * 0.2
                pressure = simulated
            }
            var radius = size / 2 * (0.4 + 0.6 * pressure)
            if tapers {
                let start = ease(min(1, lengths[index] / (size * 2.4)))
                let end = ease(min(1, (total - lengths[index]) / (size * 3)))
                radius *= max(0.18, min(start, end))
            }
            return radius
        }
        var left: [CGPoint] = [], right: [CGPoint] = []
        var directions: [CGPoint] = []
        for index in points.indices {
            let a = points[max(0, index - 1)], b = points[min(points.count - 1, index + 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(hypot(dx, dy), 0.0001)
            let normal = CGPoint(x: -dy / length, y: dx / length)
            directions.append(CGPoint(x: dx / length, y: dy / length))
            left.append(CGPoint(x: points[index].x + normal.x * radii[index], y: points[index].y + normal.y * radii[index]))
            right.append(CGPoint(x: points[index].x - normal.x * radii[index], y: points[index].y - normal.y * radii[index]))
        }
        func smoothRun(_ run: [CGPoint]) {
            for index in 1..<max(1, run.count - 1) {
                let mid = CGPoint(x: (run[index].x + run[index + 1].x) / 2, y: (run[index].y + run[index + 1].y) / 2)
                path.addQuadCurve(to: mid, control: run[index])
            }
            path.addLine(to: run[run.count - 1])
        }
        // Round caps: bend around the point just past each end of the stroke.
        func cap(from: CGPoint, to: CGPoint, center: InkPoint, direction: CGPoint, radius: CGFloat) {
            let tip = CGPoint(x: center.x + direction.x * radius, y: center.y + direction.y * radius)
            path.addQuadCurve(to: tip, control: CGPoint(x: from.x + direction.x * radius, y: from.y + direction.y * radius))
            path.addQuadCurve(to: to, control: CGPoint(x: to.x + direction.x * radius, y: to.y + direction.y * radius))
        }
        let last = points.count - 1
        path.move(to: left[0])
        smoothRun(left)
        cap(from: left[last], to: right[last], center: points[last], direction: directions[last], radius: radii[last])
        smoothRun(right.reversed())
        let back = CGPoint(x: -directions[0].x, y: -directions[0].y)
        cap(from: right[0], to: left[0], center: points[0], direction: back, radius: radii[0])
        path.closeSubpath()
        return path
    }

    static func centerline(_ raw: [InkPoint]) -> CGPath {
        let path = CGMutablePath()
        let points = streamlined(raw)
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        guard points.count > 1 else {
            path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            return path
        }
        for index in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[index].x + points[index + 1].x) / 2, y: (points[index].y + points[index + 1].y) / 2)
            path.addQuadCurve(to: mid, control: CGPoint(x: points[index].x, y: points[index].y))
        }
        let end = points[points.count - 1]
        path.addLine(to: CGPoint(x: end.x, y: end.y))
        return path
    }
}

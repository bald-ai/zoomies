import AppKit

/// A numbered marker circle that sits in note text on a U+FFFC character.
final class MarkdownMarkerAttachment: NSTextAttachment {
    let number: Int
    let token: String

    init(number: Int, token: String? = nil) {
        self.number = number
        self.token = token ?? "[^\(number)]"
        super.init(data: nil, ofType: nil)
        attachmentCell = MarkdownMarkerCell(number: number)
    }

    required init?(coder: NSCoder) { nil }

    /// Plain text for the clipboard, with marker circles written as Markdown anchors.
    static func plainText(_ text: NSAttributedString) -> String {
        let result = NSMutableAttributedString(attributedString: text)
        var markers: [(NSRange, String)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let marker = value as? MarkdownMarkerAttachment { markers.append((range, marker.token)) }
        }
        for (range, token) in markers.reversed() { result.replaceCharacters(in: range, with: token) }
        return result.string
    }
}

private final class MarkdownMarkerCell: NSTextAttachmentCell {
    let number: Int
    private let diameter: CGFloat = 21
    init(number: Int) {
        self.number = number
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("Not archived") }

    private var marker: EditorDrawing.MarkerItem {
        .init(number: number, center: .zero, color: EditorPalette.available[0].color, diameter: diameter)
    }
    override func cellSize() -> NSSize {
        let bounds = EditorImageRenderer.markerBounds(for: marker)
        return NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -7) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        var item = marker
        item.center = NSPoint(x: cellFrame.midX, y: cellFrame.midY)
        EditorImageRenderer.drawMarker(item)
    }
}

import AppKit

extension NSAttributedString.Key {
    /// Pins drawings to the character they were drawn on. It moves with the
    /// text through edits, and text undo brings it back with a deleted word.
    static let inkAnchor = NSAttributedString.Key("ZoomiesInkAnchor")
}

/// Text view that also hosts the ink: strokes draw over the text, and mouse
/// input becomes ink while drawing.
final class InkNoteTextView: NSTextView {
    weak var ink: InkNoteWindowController?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ink?.drawInk()
    }
    override func mouseDown(with event: NSEvent) {
        if ink?.inkMouseDown(event) == true { return }
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        if ink?.inkMouseDragged(event) == true { return }
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if ink?.inkMouseUp(event) == true { return }
        super.mouseUp(with: event)
    }
    override func mouseMoved(with event: NSEvent) {
        if let cursor = ink?.activeCursor { cursor.set(); return }
        super.mouseMoved(with: event)
    }
    override func cursorUpdate(with event: NSEvent) {
        if let cursor = ink?.activeCursor { cursor.set(); return }
        super.cursorUpdate(with: event)
    }
    override func resetCursorRects() {
        if let cursor = ink?.activeCursor { addCursorRect(visibleRect, cursor: cursor) } else { super.resetCursorRects() }
    }
    override func flagsChanged(with event: NSEvent) {
        ink?.modifiersChanged(event)
        super.flagsChanged(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if ink?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }
    // Copies plain text, with marker circles written as Markdown anchors.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, selectedRange().length > 0 else { return false }
        pboard.clearContents()
        return pboard.setString(MarkdownMarkerAttachment.plainText(attributedString().attributedSubstring(from: selectedRange())), forType: .string)
    }
}

/// Note editor with a clear ink layer over the text. Each stroke pins to the
/// word under it, so it rides along when the text above changes. Notes save as
/// PNGs: the picture is what agents see, and the editable text + ink travel
/// inside it.
@MainActor
final class InkNoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, @preconcurrency NSLayoutManagerDelegate {
    enum Mode { case type, draw }
    enum Tool { case pen, highlighter, eraser }

    struct Opened {
        let noteURL: URL
        let sourceURL: URL
        let document: InkNoteDocument
    }

    struct LiveItem {
        var item: InkNoteDocument.Item
        var created: Date
        var id = UUID()
    }

    static let columnWidth: CGFloat = 640
    static let palette: [EditorPaletteColor] = ["red", "blue", "green", "yellow", "white"].compactMap { id in
        EditorPalette.available.first { $0.id == id }
    }
    private static let background = NSColor(srgbRed: 0.094, green: 0.098, blue: 0.118, alpha: 1)
    private static let penCursor = ringCursor(diameter: 8)
    private static let eraserCursor = ringCursor(diameter: 22)

    /// What a Finder selection opens: a note PNG itself, or the note saved next
    /// to a Markdown file, started from that Markdown when there is none yet.
    static func resolve(_ url: URL, fileManager: FileManager = .default) throws -> Opened {
        if url.pathExtension.lowercased() == "png" {
            guard let document = PNGMetadata.extractInkNote(fromPNG: try Data(contentsOf: url)) else {
                throw NSError(domain: "InkNote", code: 1, userInfo: [NSLocalizedDescriptionKey: "This PNG has no Zoomies note inside."])
            }
            return Opened(noteURL: url, sourceURL: url, document: document)
        }
        let sibling = url.deletingPathExtension().appendingPathExtension("png")
        let siblingExists = fileManager.fileExists(atPath: sibling.path)
        if siblingExists, let data = try? Data(contentsOf: sibling), let document = PNGMetadata.extractInkNote(fromPNG: data) {
            return Opened(noteURL: sibling, sourceURL: url, document: document)
        }
        let data = try Data(contentsOf: url)
        guard data.count <= MarkdownMarkerLogic.maximumFileSize, let markdown = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "InkNote", code: 2, userInfo: [NSLocalizedDescriptionKey: "Markdown must be valid UTF-8 and no larger than 1 MB."])
        }
        // Never overwrite an unrelated picture that happens to share the name.
        let noteURL = siblingExists
            ? UniqueFileURLLogic.uniqueURL(forProposedName: sibling.lastPathComponent, in: url.deletingLastPathComponent(),
                                           fileExists: { fileManager.fileExists(atPath: $0) })
            : sibling
        return Opened(noteURL: noteURL, sourceURL: url, document: .fromMarkdown(markdown))
    }

    let noteURL: URL
    let sourceURL: URL
    let textView = InkNoteTextView(frame: .zero)
    let history = UndoManager()
    var onClose: (() -> Void)?
    /// Puts the saved note file on the clipboard.
    var copyFile: ((URL) -> Void)?

    private(set) var items: [LiveItem] = []
    private(set) var mode: Mode = .type
    private(set) var tool: Tool = .pen
    private(set) var colorHex: String = palette.first?.hex ?? "#ff3b30"
    private var holdingOption = false
    private var current: InkStroke?
    private var eraseStart: [LiveItem]?
    private var paths: [UUID: CGPath] = [:]
    private var savedDocument: InkNoteDocument
    private let scrollView = NSScrollView()
    private let modeControl = NSSegmentedControl()
    private let toolControl = NSSegmentedControl()
    private var swatches: [InkSwatchButton] = []

    var isDrawing: Bool { mode == .draw || holdingOption }
    var activeCursor: NSCursor? { isDrawing ? (tool == .eraser ? Self.eraserCursor : Self.penCursor) : nil }
    var hasUnsavedChanges: Bool { currentDocument() != savedDocument }

    init(opened: Opened) {
        noteURL = opened.noteURL
        sourceURL = opened.sourceURL
        savedDocument = opened.document
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        AppTheme.apply(to: window)
        window.minSize = NSSize(width: Self.columnWidth + 80, height: 360)
        window.backgroundColor = Self.background
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        if sourceURL != noteURL { window.subtitle = "from \(sourceURL.lastPathComponent)" }
        window.center()
        buildUI()
        load(opened.document)
        savedDocument = currentDocument()
        window.keyEquivalentInterceptor = { [weak self] event in self?.handleKey(event) ?? false }
        syncControls()
        refresh()
    }
    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
        updateLayoutMetrics()
    }

    // MARK: - Building

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        return [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor(white: 0.92, alpha: 1), .paragraphStyle: paragraph]
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        modeControl.segmentCount = 2
        modeControl.setLabel("Type", forSegment: 0)
        modeControl.setLabel("Draw", forSegment: 1)
        modeControl.setToolTip("Type (T or Esc)", forSegment: 0)
        modeControl.setToolTip("Draw (⌘D, or hold ⌥ to draw for a moment)", forSegment: 1)
        modeControl.trackingMode = .selectOne
        modeControl.target = self
        modeControl.action = #selector(modeClicked)
        toolControl.segmentCount = 3
        for (index, (symbol, tip)) in [("pencil.tip", "Pen (P)"), ("highlighter", "Highlighter (H)"), ("eraser", "Eraser (E)")].enumerated() {
            toolControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: tip), forSegment: index)
            toolControl.setToolTip(tip, forSegment: index)
        }
        toolControl.trackingMode = .selectOne
        toolControl.target = self
        toolControl.action = #selector(toolClicked)
        for control in [modeControl, toolControl] { control.refusesFirstResponder = true }
        swatches = Self.palette.enumerated().map { index, color in
            let button = InkSwatchButton(hex: color.hex)
            button.toolTip = "\(color.name) (\(index + 1))"
            button.target = self
            button.action = #selector(swatchClicked(_:))
            return button
        }
        let swatchRow = NSStackView(views: swatches)
        swatchRow.spacing = 6
        let hint = NSTextField(labelWithString: "⌘D draw · hold ⌥ to sketch · ⌘F marker · ⌘S save · ⌘⇧C copy image")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [modeControl, toolControl, swatchRow, hint])
        bar.spacing = 16
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false

        textView.ink = self
        textView.delegate = self
        textView.layoutManager?.delegate = self
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        // A fixed column: resizing the window never rewraps lines under the ink.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: Self.columnWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 40, height: 40)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = Self.background
        textView.insertionPointColor = .white
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.typingAttributes = baseAttributes

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = Self.background
        scrollView.documentView = textView
        content.addSubview(bar)
        content.addSubview(line)
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.topAnchor.constraint(equalTo: bar.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: line.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        content.layoutSubtreeIfNeeded()
        updateLayoutMetrics()
    }

    /// Centers the column and keeps the text view at least as tall as the
    /// window, so there is room to draw below the last line.
    private func updateLayoutMetrics() {
        let size = scrollView.contentSize
        let side = max(32, floor((size.width - Self.columnWidth) / 2))
        if textView.textContainerInset.width != side {
            textView.textContainerInset = NSSize(width: side, height: 40)
        }
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.frame.size.width = size.width
        textView.sizeToFit()
        textView.needsDisplay = true
    }

    func windowDidResize(_ notification: Notification) { updateLayoutMetrics() }

    // MARK: - Document

    private func load(_ document: InkNoteDocument) {
        let text = NSMutableAttributedString(string: document.text, attributes: baseAttributes)
        for marker in document.markers {
            text.addAttribute(.attachment, value: MarkdownMarkerAttachment(number: marker.number), range: NSRange(location: marker.index, length: 1))
        }
        for anchor in document.anchors {
            text.addAttribute(.inkAnchor, value: anchor.id, range: NSRange(location: anchor.index, length: 1))
        }
        textView.textStorage?.setAttributedString(text)
        textView.typingAttributes = baseAttributes
        textView.setSelectedRange(NSRange(location: text.length, length: 0))
        items = document.items.map { LiveItem(item: $0, created: .distantPast) }
        paths = [:]
        history.removeAllActions()
    }

    func currentDocument() -> InkNoteDocument {
        guard let storage = textView.textStorage else { return savedDocument }
        let full = NSRange(location: 0, length: storage.length)
        var markers: [InkNoteDocument.Marker] = []
        storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            if let marker = value as? MarkdownMarkerAttachment { markers.append(.init(index: range.location, number: marker.number)) }
        }
        let positions = anchorIndices()
        // Ink whose word was deleted stays in memory for undo but is not saved.
        let visible = items.filter { $0.item.anchor.map { positions[$0] != nil } ?? true }
        let used = Set(visible.compactMap { $0.item.anchor })
        let anchors = positions.filter { used.contains($0.key) }
            .map { InkNoteDocument.Anchor(index: $0.value, id: $0.key) }
            .sorted { ($0.index, $0.id) < ($1.index, $1.id) }
        return InkNoteDocument(text: storage.string, markers: markers, anchors: anchors, items: visible.map(\.item))
    }

    private func refresh() {
        let dirty = hasUnsavedChanges
        window?.title = noteURL.lastPathComponent + (dirty ? " •" : "")
        window?.isDocumentEdited = dirty
    }

    // MARK: - Text

    func textDidChange(_ notification: Notification) {
        textView.needsDisplay = true
        refresh()
    }

    func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
                  toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
        var attributes = newTypingAttributes
        attributes[.inkAnchor] = nil
        attributes[.attachment] = nil
        return attributes
    }

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        // Ink below an edit moves with the text, so the whole layer redraws.
        textView.needsDisplay = true
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { history }

    /// Drops a numbered circle at the cursor and starts its note line at the end.
    func insertMarker() {
        guard let storage = textView.textStorage else { return }
        var highest = 0
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let marker = value as? MarkdownMarkerAttachment { highest = max(highest, marker.number) }
        }
        let number = highest + 1
        history.beginUndoGrouping()
        replace(NSRange(location: NSMaxRange(textView.selectedRange()), length: 0), with: markerText(number))
        let text = storage.string as NSString
        let lastLine = text.substring(from: text.lineRange(for: NSRange(location: text.length, length: 0)).location)
        let separator = lastLine.hasPrefix("\u{FFFC} ") ? "\n" : storage.string.hasSuffix("\n\n") ? "" : storage.string.hasSuffix("\n") ? "\n" : "\n\n"
        let line = NSMutableAttributedString(string: separator, attributes: baseAttributes)
        line.append(markerText(number))
        line.append(NSAttributedString(string: " ", attributes: baseAttributes))
        replace(NSRange(location: storage.length, length: 0), with: line)
        history.endUndoGrouping()
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        setMode(.type)
    }

    private func markerText(_ number: Int) -> NSAttributedString {
        let text = NSMutableAttributedString(attachment: MarkdownMarkerAttachment(number: number))
        text.addAttributes(baseAttributes, range: NSRange(location: 0, length: text.length))
        return text
    }

    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard textView.shouldChangeText(in: range, replacementString: text.string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
    }

    // MARK: - Ink placement

    private func anchorIndices() -> [String: Int] {
        guard let storage = textView.textStorage else { return [:] }
        var result: [String: Int] = [:]
        storage.enumerateAttribute(.inkAnchor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let id = value as? String, result[id] == nil { result[id] = range.location }
        }
        return result
    }

    private func glyphRect(_ index: Int) -> CGRect {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return .zero }
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let origin = textView.textContainerOrigin
        return manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
    }

    private func origin(of item: InkNoteDocument.Item, positions: [String: Int]) -> CGPoint? {
        if let anchor = item.anchor {
            guard let index = positions[anchor] else { return nil }
            let rect = glyphRect(index)
            return CGPoint(x: rect.minX + item.x, y: rect.minY + item.y)
        }
        let column = textView.textContainerOrigin
        return CGPoint(x: column.x + item.x, y: column.y + item.y)
    }

    /// Ties a point to the start of the word nearest it. Returns nil when the
    /// note has no text yet.
    private func pin(at point: CGPoint) -> (id: String, rect: CGRect)? {
        guard let storage = textView.textStorage, storage.length > 0,
              let manager = textView.layoutManager, let container = textView.textContainer else { return nil }
        let origin = textView.textContainerOrigin
        var fraction: CGFloat = 0
        let hit = manager.characterIndex(for: CGPoint(x: point.x - origin.x, y: point.y - origin.y), in: container,
                                         fractionOfDistanceBetweenInsertionPoints: &fraction)
        let index = min(InkAnchorLogic.wordStart(in: storage.string as NSString, at: min(hit, storage.length - 1)), storage.length - 1)
        let id = storage.attribute(.inkAnchor, at: index, effectiveRange: nil) as? String ?? UUID().uuidString
        storage.addAttribute(.inkAnchor, value: id, range: NSRange(location: index, length: 1))
        return (id, glyphRect(index))
    }

    /// Adds a finished stroke (in text view coordinates) to the note.
    func commit(_ absolute: InkStroke, at time: Date = Date()) {
        var stroke = absolute
        let origin = stroke.localize()
        stroke.roundToSavedPrecision()
        let bounds = CGRect(origin: origin, size: stroke.bounds.size)
        let positions = anchorIndices()
        var item = InkNoteDocument.Item(stroke: stroke, anchor: nil, x: 0, y: 0)
        if let previous = items.last, let anchor = previous.item.anchor, let index = positions[anchor],
           case let rect = glyphRect(index),
           InkAnchorLogic.joinsPrevious(previous: previous.item.stroke.bounds.offsetBy(dx: rect.minX + previous.item.x, dy: rect.minY + previous.item.y),
                                        next: bounds, elapsed: time.timeIntervalSince(previous.created)) {
            item.anchor = anchor
            item.x = origin.x - rect.minX
            item.y = origin.y - rect.minY
        } else if let pinned = pin(at: InkAnchorLogic.anchorPoint(for: absolute.points.map { CGPoint(x: $0.x, y: $0.y) })) {
            item.anchor = pinned.id
            item.x = origin.x - pinned.rect.minX
            item.y = origin.y - pinned.rect.minY
        } else {
            let column = textView.textContainerOrigin
            item.x = origin.x - column.x
            item.y = origin.y - column.y
        }
        setItems(items + [LiveItem(item: item, created: time)])
    }

    /// Every ink change goes through here, so ⌘Z steps through ink and text
    /// in the order they happened.
    private func setItems(_ new: [LiveItem]) {
        let old = items
        textView.breakUndoCoalescing()
        history.registerUndo(withTarget: self) { $0.setItems(old) }
        items = new
        let live = Set(new.map(\.id)).union(old.map(\.id))
        paths = paths.filter { live.contains($0.key) }
        textView.needsDisplay = true
        refresh()
    }

    /// Where each visible stroke sits right now, in text view coordinates.
    var visibleInkOrigins: [CGPoint] {
        let positions = anchorIndices()
        return items.compactMap { origin(of: $0.item, positions: positions) }
    }

    func erase(at point: CGPoint) {
        let positions = anchorIndices()
        let before = items.count
        items.removeAll { live in
            guard let origin = origin(of: live.item, positions: positions) else { return false }
            return live.item.stroke.hits(CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        }
        if items.count != before { textView.needsDisplay = true }
    }

    // MARK: - Drawing

    func drawInk() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let positions = anchorIndices()
        for live in items {
            guard let origin = origin(of: live.item, positions: positions) else { continue }
            let path = paths[live.id] ?? InkGeometry.path(for: live.item.stroke)
            paths[live.id] = path
            draw(live.item.stroke, path: path, at: origin, in: context)
        }
        if let current { draw(current, path: InkGeometry.path(for: current), at: .zero, in: context) }
    }

    private func draw(_ stroke: InkStroke, path: CGPath, at origin: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.addPath(path)
        let color = NSColor(hex: stroke.color).cgColor
        if stroke.tool == .highlighter {
            context.setStrokeColor(color.copy(alpha: 0.36) ?? color)
            context.setLineWidth(stroke.width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        } else {
            context.setFillColor(color)
            context.fillPath()
        }
        context.restoreGState()
    }

    private func drawsInk(_ event: NSEvent) -> Bool {
        mode == .draw || event.modifierFlags.contains(.option) || event.subtype == .tabletPoint
    }

    private func inkPoint(_ event: NSEvent) -> InkPoint {
        let point = textView.convert(event.locationInWindow, from: nil)
        return InkPoint(x: point.x, y: point.y, pressure: event.subtype == .tabletPoint ? CGFloat(event.pressure) : -1)
    }

    func inkMouseDown(_ event: NSEvent) -> Bool {
        guard drawsInk(event) else { return false }
        window?.makeFirstResponder(textView)
        let point = inkPoint(event)
        if tool == .eraser {
            eraseStart = items
            erase(at: CGPoint(x: point.x, y: point.y))
            return true
        }
        current = InkStroke(tool: tool == .highlighter ? .highlighter : .pen, color: colorHex,
                            width: tool == .highlighter ? 17 : 3.2, points: [point])
        textView.needsDisplay = true
        return true
    }

    func inkMouseDragged(_ event: NSEvent) -> Bool {
        let point = inkPoint(event)
        if eraseStart != nil {
            erase(at: CGPoint(x: point.x, y: point.y))
            return true
        }
        guard current != nil else { return false }
        current?.points.append(point)
        // Only the growing end of a stroke changes shape.
        if let stroke = current {
            let tail = InkStroke(tool: stroke.tool, color: stroke.color, width: stroke.width, points: Array(stroke.points.suffix(14)))
            textView.setNeedsDisplay(tail.bounds.insetBy(dx: -stroke.width - 8, dy: -stroke.width - 8))
        }
        textView.autoscroll(with: event)
        return true
    }

    func inkMouseUp(_ event: NSEvent) -> Bool {
        if let start = eraseStart {
            eraseStart = nil
            if start.count != items.count {
                let after = items
                items = start
                setItems(after)
            }
            return true
        }
        guard let stroke = current else { return false }
        current = nil
        commit(stroke)
        return true
    }

    // MARK: - Modes and keys

    func setMode(_ new: Mode) {
        mode = new
        syncControls()
    }

    func setTool(_ new: Tool) {
        tool = new
        if mode != .draw && !holdingOption { mode = .draw }
        syncControls()
    }

    func setColor(_ index: Int) {
        guard Self.palette.indices.contains(index) else { return }
        colorHex = Self.palette[index].hex
        if tool == .eraser { tool = .pen }
        if mode != .draw && !holdingOption { mode = .draw }
        syncControls()
    }

    func modifiersChanged(_ event: NSEvent) {
        let holding = event.modifierFlags.contains(.option)
        guard holding != holdingOption else { return }
        holdingOption = holding
        syncControls()
    }

    private func syncControls() {
        modeControl.selectedSegment = isDrawing ? 1 : 0
        toolControl.selectedSegment = [.pen: 0, .highlighter: 1, .eraser: 2][tool] ?? 0
        swatches.forEach { $0.isChosen = $0.hex == colorHex }
        window?.invalidateCursorRects(for: textView)
        if let window, textView.visibleRect.contains(textView.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            (activeCursor ?? .iBeam).set()
        }
    }

    @objc private func modeClicked() {
        setMode(modeControl.selectedSegment == 1 ? .draw : .type)
        window?.makeFirstResponder(textView)
    }

    @objc private func toolClicked() {
        setTool([.pen, .highlighter, .eraser][max(0, toolControl.selectedSegment)])
        window?.makeFirstResponder(textView)
    }

    @objc private func swatchClicked(_ sender: InkSwatchButton) {
        if let index = swatches.firstIndex(where: { $0 === sender }) { setColor(index) }
        window?.makeFirstResponder(textView)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command] {
            switch key {
            case "a": textView.selectAll(nil)
            case "c": textView.copy(nil)
            case "x": textView.cut(nil)
            case "v": textView.paste(nil)
            case "z": undo()
            case "s": save()
            case "w": window?.performClose(nil)
            case "d": setMode(mode == .draw ? .type : .draw)
            case "f": insertMarker()
            default: return false
            }
            return true
        }
        if flags == [.command, .shift] {
            switch key {
            case "z": redo()
            case "c": copyImage()
            default: return false
            }
            return true
        }
        if event.keyCode == 53, flags.isEmpty {
            if mode == .draw { setMode(.type) } else { window?.performClose(nil) }
            return true
        }
        guard mode == .draw, flags.isEmpty else { return false }
        switch key {
        case "p": setTool(.pen)
        case "h": setTool(.highlighter)
        case "e": setTool(.eraser)
        case "t": setMode(.type)
        case "1", "2", "3", "4", "5": setColor((Int(key) ?? 1) - 1)
        default:
            // Typing anything else goes straight back to writing.
            setMode(.type)
            return false
        }
        return true
    }

    func undo() {
        textView.breakUndoCoalescing()
        if history.canUndo { history.undo() }
        textView.needsDisplay = true
        refresh()
    }

    func redo() {
        if history.canRedo { history.redo() }
        textView.needsDisplay = true
        refresh()
    }

    // MARK: - Saving

    /// The note as agents see it: the text column plus any ink around it.
    func renderPNG() -> Data? {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return nil }
        manager.ensureLayout(for: container)
        let selection = textView.selectedRanges
        let responder = window?.firstResponder
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        window?.makeFirstResponder(nil)
        defer {
            textView.selectedRanges = selection
            window?.makeFirstResponder(responder)
        }
        let column = textView.textContainerOrigin
        var rect = CGRect(x: column.x - 36, y: 0, width: Self.columnWidth + 72,
                          height: manager.usedRect(for: container).maxY + column.y + 40)
        let positions = anchorIndices()
        for live in items {
            guard let origin = origin(of: live.item, positions: positions) else { continue }
            rect = rect.union(live.item.stroke.bounds.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -24, dy: -24))
        }
        rect = rect.intersection(textView.bounds).integral
        guard !rect.isEmpty, let rep = textView.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        textView.cacheDisplay(in: rect, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @discardableResult
    func save() -> Bool {
        let document = currentDocument()
        do {
            guard let png = renderPNG(), let data = PNGMetadata.embed(intoPNG: png, inkNote: document) else {
                throw NSError(domain: "InkNote", code: 3, userInfo: [NSLocalizedDescriptionKey: "The note could not be drawn into an image."])
            }
            try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: noteURL, options: .atomic)
            savedDocument = document
            refresh()
            return true
        } catch {
            AlertPresenter.presentWarning(title: "Cannot Save Note", message: error.localizedDescription)
            return false
        }
    }

    /// Saves, then puts the note image on the clipboard for pasting to an agent.
    func copyImage() {
        guard save() else { return }
        copyFile?(noteURL)
        let subtitle = window?.subtitle ?? ""
        window?.subtitle = "Copied \(noteURL.lastPathComponent)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.window?.subtitle = subtitle }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(noteURL.lastPathComponent)?"
        for button in ["Save", "Discard", "Cancel"] { alert.addButton(withTitle: button) }
        switch AlertPresenter.runModal(alert) {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    private static func ringCursor(diameter: CGFloat) -> NSCursor {
        let size = diameter + 6
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            NSColor.black.withAlphaComponent(0.55).setStroke()
            ring.lineWidth = 3
            ring.stroke()
            NSColor.white.setStroke()
            ring.lineWidth = 1.4
            ring.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}

final class InkSwatchButton: NSButton {
    let hex: String
    var isChosen = false { didSet { needsDisplay = true } }

    init(hex: String) {
        self.hex = hex
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        title = ""
        refusesFirstResponder = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(hex: hex)
        if isChosen {
            color.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 4.5, dy: 4.5)).fill()
    }
}

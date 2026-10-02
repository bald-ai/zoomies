import AppKit
import Carbon

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
        // Text drawing leaves the context clipped to the text column, which
        // would cut off ink in the margins around it.
        NSGraphicsContext.saveGraphicsState()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
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
    enum Tool {
        case pen, line, arrow, rectangle, ellipse, highlighter, eraser

        var shape: InkShape? {
            switch self {
            case .line: return .line
            case .arrow: return .arrow
            case .rectangle: return .rectangle
            case .ellipse: return .ellipse
            case .pen, .highlighter, .eraser: return nil
            }
        }
    }

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
    /// About as heavy as an average pen stroke, which thins and thickens.
    static let shapeWidth: CGFloat = 2.5
    /// The Settings colors, minus any too dark to see on the note background
    /// (black is in the default palette).
    static func noteColors(forPaletteIDs ids: [String]) -> [EditorPaletteColor] {
        let visible = EditorPalette.colors(for: ids).filter { isVisibleOnBackground($0.color) }
        return visible.isEmpty ? EditorPalette.available.filter { $0.id == "white" } : visible
    }

    static func isVisibleOnBackground(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent > 0.12
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
    /// Returns whether the saved note file was published to the clipboard.
    var copyFile: ((URL) -> Bool)?

    private(set) var items: [LiveItem] = []
    private(set) var mode: Mode = .type
    private(set) var tool: Tool = .pen
    private(set) var palette: [EditorPaletteColor]
    private(set) var colorHex: String
    private let settingsStore: SettingsStore?
    private var paletteObserver: NSObjectProtocol?
    private var holdingOption = false
    private var current: InkStroke?
    private var shapeDrag: (start: CGPoint, end: CGPoint)?
    private var eraseStart: [LiveItem]?
    private var paths: [UUID: CGPath] = [:]
    private var savedDocument: InkNoteDocument
    private let scrollView = NSScrollView()
    private var modeButtons: [Mode: NSButton] = [:]
    private var toolButtons: [Tool: NSButton] = [:]
    private var swatches: [InkSwatchButton] = []
    private var swatchRow = NSStackView()
    private var keyMonitor: Any?
    private var layoutObservation: KeyboardLayoutObservation?
    private(set) var shortcutOverlay: EditorShortcutOverlayController?
    private(set) var shortcutHints: [EditorShortcutHint] = []
    private var fixedHints: [EditorShortcutHint] = []
    private var markerButton = NSButton()

    var isDrawing: Bool { mode == .draw || holdingOption }
    var activeCursor: NSCursor? { isDrawing ? (tool == .eraser ? Self.eraserCursor : Self.penCursor) : nil }
    var hasUnsavedChanges: Bool { currentDocument() != savedDocument }

    init(opened: Opened, settingsStore: SettingsStore? = nil) {
        noteURL = opened.noteURL
        sourceURL = opened.sourceURL
        savedDocument = opened.document
        self.settingsStore = settingsStore
        palette = Self.noteColors(forPaletteIDs: settingsStore?.settings.editorColorIDs ?? EditorPalette.defaultIDs)
        colorHex = palette.first?.hex ?? "#ff3b30"
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
        shortcutOverlay = EditorShortcutOverlayController(window: window, helpPlacement: .belowBadges) { [weak self] in
            self?.shortcutHints ?? []
        }
        refreshShortcutLabels()
        layoutObservation = KeyboardLayoutObservation { [weak self] in self?.refreshShortcutLabels() }
        if let settingsStore {
            paletteObserver = NotificationCenter.default.addObserver(forName: SettingsStore.didChangeNotification, object: settingsStore,
                                                                     queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadPalette() }
            }
        }
        syncControls()
        refresh()
    }
    required init?(coder: NSCoder) { nil }

    deinit {
        if let paletteObserver { NotificationCenter.default.removeObserver(paletteObserver) }
    }

    func present() {
        installKeyMonitor()
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
        let bar = makeToolbar()
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

    /// The same grouped icon toolbar as the screenshot editor: mode, ink,
    /// marker, history, then close / copy / save on the right.
    private func makeToolbar() -> NSStackView {
        func button(_ symbol: String, _ toolTip: String, _ action: Selector) -> NSButton {
            let button = EditorToolbarStyle.iconButton(symbol: symbol, toolTip: toolTip)
            button.target = self
            button.action = action
            return button
        }
        let type = button("character.cursor.ibeam", "", #selector(typePressed))
        let draw = button("scribble.variable", "", #selector(drawPressed))
        // The screenshot editor's tool icons, in its order.
        let pen = button("pencil.tip", "", #selector(toolPressed(_:)))
        let line = button("line.diagonal", "", #selector(toolPressed(_:)))
        let arrow = button("arrow.right", "", #selector(toolPressed(_:)))
        let rectangle = button("square", "", #selector(toolPressed(_:)))
        let ellipse = button("circle", "", #selector(toolPressed(_:)))
        let highlighter = button("highlighter", "", #selector(toolPressed(_:)))
        let eraser = button("eraser", "", #selector(toolPressed(_:)))
        modeButtons = [.type: type, .draw: draw]
        toolButtons = [.pen: pen, .line: line, .arrow: arrow, .rectangle: rectangle, .ellipse: ellipse,
                       .highlighter: highlighter, .eraser: eraser]
        swatchRow.spacing = 2
        rebuildSwatches()
        markerButton = button("1.circle", "", #selector(markerPressed))
        let undo = button("arrow.uturn.left", "Undo (Cmd+Z)", #selector(undoPressed))
        let redo = button("arrow.uturn.right", "Redo (Cmd+Shift+Z)", #selector(redoPressed))
        let clear = button("trash", "Clear all ink (Option+Backspace while drawing)", #selector(clearPressed))
        let close = button("xmark", "Close (Esc or Cmd+W)", #selector(closePressed))
        let copy = button("doc.on.doc", "Copy + save and close (Cmd+Enter)", #selector(copyPressed))
        let save = button("tray.and.arrow.down", "Save (Cmd+S)", #selector(savePressed))
        fixedHints = [
            .init(view: markerButton, key: "⌘F", label: "Numbered marker"),
            .init(view: undo, key: "⌘Z", label: "Undo"),
            .init(view: redo, key: "⌘⇧Z", label: "Redo"),
            .init(view: clear, key: "⌥⌫", label: "Clear all ink, while drawing"),
            .init(view: close, key: "Esc", label: "Close (⌘W also closes)"),
            .init(view: copy, key: "⌘↩", label: "Copy + save and close"),
            .init(view: save, key: "⌘S", label: "Save")
        ]

        let groups: [[NSView]] = [[type, draw], [pen, line, arrow, rectangle, ellipse], [highlighter, eraser, swatchRow],
                                  [markerButton], [undo, redo, clear]]
        let bar = NSStackView()
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        bar.setViews(groups.map { EditorToolbarStyle.group($0) }, in: .leading)
        bar.setViews([EditorToolbarStyle.group([close, copy, save])], in: .trailing)
        return bar
    }

    private func rebuildSwatches() {
        swatchRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        swatches = palette.map { color in
            let button = InkSwatchButton(hex: color.hex, name: color.name)
            button.target = self
            button.action = #selector(swatchClicked(_:))
            swatchRow.addArrangedSubview(button)
            return button
        }
    }

    /// Settings → Colors changes apply to open notes, as in the screenshot editor.
    private func reloadPalette() {
        let updated = Self.noteColors(forPaletteIDs: settingsStore?.settings.editorColorIDs ?? EditorPalette.defaultIDs)
        guard updated.map(\.id) != palette.map(\.id) else { return }
        palette = updated
        if !palette.contains(where: { $0.hex == colorHex }) { colorHex = palette.first?.hex ?? colorHex }
        rebuildSwatches()
        refreshShortcutLabels()
        syncControls()
    }

    /// Tool letters are physical keys, so their names follow the keyboard layout.
    func refreshShortcutLabels() {
        func key(_ code: Int) -> String { HotKeyService.describeShortcut(keyCode: UInt32(code), carbonFlags: 0) }
        let color = key(kVK_ANSI_Q), marker = key(kVK_ANSI_F)
        var hints: [EditorShortcutHint] = []
        if let button = modeButtons[.type] {
            button.toolTip = "Type (Cmd+T, or Esc while drawing)"
            hints.append(.init(view: button, key: "⌘T", label: "Type (Esc also leaves drawing)"))
        }
        if let button = modeButtons[.draw] {
            button.toolTip = "Draw (Cmd+D, or hold Option to draw for a moment)"
            hints.append(.init(view: button, key: "⌘D", label: "Draw (hold ⌥ to draw for a moment)"))
        }
        let tools: [(Tool, String, Int)] = [(.pen, "Pen", kVK_ANSI_W), (.line, "Line", kVK_ANSI_D), (.arrow, "Arrow", kVK_ANSI_A),
                                            (.rectangle, "Rectangle, hold ⇧ for a square", kVK_ANSI_R),
                                            (.ellipse, "Ellipse, hold ⇧ for a circle", kVK_ANSI_E),
                                            (.highlighter, "Highlighter", kVK_ANSI_H), (.eraser, "Eraser", kVK_ANSI_X)]
        for (tool, title, code) in tools {
            guard let button = toolButtons[tool] else { continue }
            button.toolTip = "\(title) (\(key(code)) while drawing)"
            hints.append(.init(view: button, key: key(code), label: "\(title), while drawing"))
        }
        for swatch in swatches { swatch.toolTip = "\(swatch.colorName) (\(color) while drawing picks the next color)" }
        hints.append(.init(view: swatchRow, key: color, label: "Next color, while drawing"))
        markerButton.toolTip = "Numbered marker (Cmd+F, or \(marker) while drawing)"
        shortcutHints = hints + fixedHints
        shortcutOverlay?.refreshLabels()
    }

    /// Feeds the Command-hold hints, like the screenshot editor's monitor.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.shortcutOverlay?.handle(event)
            return event
        }
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
        if tool.shape != nil {
            let start = CGPoint(x: point.x, y: point.y)
            shapeDrag = (start, start)
            current = InkStroke(tool: .shape, color: colorHex, width: Self.shapeWidth, points: [])
            return true
        }
        current = InkStroke(tool: tool == .highlighter ? .highlighter : .pen, color: colorHex,
                            width: tool == .highlighter ? 17 : 3.2, points: [point])
        textView.needsDisplay = true
        return true
    }

    /// Redraws the shape being dragged; Shift makes a square or a circle.
    private func updateShape(constrained: Bool) {
        guard let drag = shapeDrag, let shape = tool.shape, var stroke = current else { return }
        let old = stroke.bounds
        stroke.points = shape.points(from: drag.start, to: drag.end, constrained: constrained)
            .map { InkPoint(x: $0.x, y: $0.y, pressure: -1) }
        current = stroke
        let changed = old.isNull ? stroke.bounds : old.union(stroke.bounds)
        textView.setNeedsDisplay(changed.insetBy(dx: -stroke.width - 4, dy: -stroke.width - 4))
    }

    func inkMouseDragged(_ event: NSEvent) -> Bool {
        let point = inkPoint(event)
        if eraseStart != nil {
            erase(at: CGPoint(x: point.x, y: point.y))
            return true
        }
        if shapeDrag != nil {
            shapeDrag?.end = CGPoint(x: point.x, y: point.y)
            updateShape(constrained: event.modifierFlags.contains(.shift))
            textView.autoscroll(with: event)
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
        if shapeDrag != nil {
            shapeDrag = nil
            // A click with a shape tool draws nothing, as in the screenshot editor.
            guard stroke.bounds.width >= 2 || stroke.bounds.height >= 2 else {
                textView.needsDisplay = true
                return true
            }
        }
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
        guard palette.indices.contains(index) else { return }
        colorHex = palette[index].hex
        if tool == .eraser { tool = .pen }
        if mode != .draw && !holdingOption { mode = .draw }
        syncControls()
    }

    /// Q steps through the palette like the screenshot editor's color key.
    func nextColor() {
        let current = palette.firstIndex { $0.hex == colorHex } ?? -1
        setColor((current + 1) % max(1, palette.count))
    }

    /// Option+Backspace while drawing, like Clear in the screenshot editor; undoable.
    func clearInk() {
        guard !items.isEmpty else { return }
        setItems([])
    }

    func modifiersChanged(_ event: NSEvent) {
        if shapeDrag != nil { updateShape(constrained: event.modifierFlags.contains(.shift)) }
        let holding = event.modifierFlags.contains(.option)
        guard holding != holdingOption else { return }
        holdingOption = holding
        syncControls()
    }

    private func syncControls() {
        modeButtons.forEach { EditorToolbarStyle.setActive($0.value, ($0.key == .draw) == isDrawing) }
        toolButtons.forEach { EditorToolbarStyle.setActive($0.value, $0.key == tool) }
        swatches.forEach { $0.isChosen = $0.hex == colorHex }
        window?.invalidateCursorRects(for: textView)
        if let window, textView.visibleRect.contains(textView.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            (activeCursor ?? .iBeam).set()
        }
    }

    // Toolbar clicks run the same commands as their keys, then hand focus back to the text.
    @objc private func typePressed() { perform(.type) }
    @objc private func drawPressed() { perform(.draw) }
    @objc private func markerPressed() { perform(.marker) }
    @objc private func undoPressed() { perform(.undo) }
    @objc private func redoPressed() { perform(.redo) }
    @objc private func clearPressed() { perform(.clearInk) }
    @objc private func closePressed() { perform(.close) }
    @objc private func copyPressed() { perform(.copyAndSave) }
    @objc private func savePressed() { perform(.save) }

    @objc private func toolPressed(_ sender: NSButton) {
        if let tool = toolButtons.first(where: { $0.value === sender })?.key { perform(.tool(tool)) }
    }

    @objc private func swatchClicked(_ sender: InkSwatchButton) {
        if let index = swatches.firstIndex(where: { $0 === sender }) { setColor(index) }
        window?.makeFirstResponder(textView)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard let command = InkNoteKeymap.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                                                  flags: event.modifierFlags, isDrawing: mode == .draw) else {
            // Typing anything else while drawing goes straight back to writing.
            if mode == .draw, event.modifierFlags.intersection([.command, .control]).isEmpty { setMode(.type) }
            return false
        }
        perform(command)
        return true
    }

    func perform(_ command: InkNoteKeymap.Command) {
        switch command {
        case .selectAll: textView.selectAll(nil)
        case .copy: textView.copy(nil)
        case .cut: textView.cut(nil)
        case .paste: textView.paste(nil)
        case .undo: undo()
        case .redo: redo()
        case .save: save()
        case .copyAndSave: copyAndSave()
        case .close: window?.performClose(nil)
        case .draw: setMode(.draw)
        case .type: setMode(.type)
        case .escape: if mode == .draw { setMode(.type) } else { window?.performClose(nil) }
        case .marker: insertMarker()
        case .nextColor: nextColor()
        case .clearInk: clearInk()
        case .tool(let tool): setTool(tool)
        }
        if let window, window.isVisible, window.firstResponder !== textView { window.makeFirstResponder(textView) }
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

    /// Saves, puts the note image on the clipboard for pasting to an agent,
    /// and closes, like Command+Return in the screenshot flow.
    func copyAndSave() {
        guard save() else { return }
        guard copyFile?(noteURL) == true else {
            AlertPresenter.presentWarning(title: "Cannot Copy Note", message: "The note was saved, but could not be copied to the clipboard. Try Copy + Save again.")
            return
        }
        close()
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

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        shortcutOverlay?.cancel()
        onClose?()
    }

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
    let colorName: String
    var isChosen = false { didSet { needsDisplay = true } }

    init(hex: String, name: String) {
        self.hex = hex
        colorName = name
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

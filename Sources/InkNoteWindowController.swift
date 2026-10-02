import AppKit
import Carbon

/// The note editor's page: the note's text in a fixed column, with the ink
/// drawn over it. While typing it is an ordinary text view; while drawing,
/// mouse input becomes ink, shapes and markers and stray keys are dropped.
final class InkNoteTextView: NSTextView {
    weak var editor: InkNoteWindowController?

    override func draw(_ dirtyRect: NSRect) {
        // Text drawing leaves the context clipped to the text column, which
        // would cut off ink in the margins around it.
        NSGraphicsContext.saveGraphicsState()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
        editor?.drawInk()
    }
    override func mouseDown(with event: NSEvent) {
        if editor?.isDrawing == true { editor?.canvasMouseDown(event) } else { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if editor?.isDrawing == true { editor?.canvasMouseDragged(event) } else { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if editor?.isDrawing == true { editor?.canvasMouseUp(event) } else { super.mouseUp(with: event) }
    }
    override func mouseMoved(with event: NSEvent) {
        if let cursor = editor?.drawingCursor { cursor.set() } else { super.mouseMoved(with: event) }
    }
    override func cursorUpdate(with event: NSEvent) {
        if let cursor = editor?.drawingCursor { cursor.set() } else { super.cursorUpdate(with: event) }
    }
    override func resetCursorRects() {
        if let cursor = editor?.drawingCursor { addCursorRect(visibleRect, cursor: cursor) } else { super.resetCursorRects() }
    }
    override func flagsChanged(with event: NSEvent) {
        editor?.modifiersChanged(event)
        super.flagsChanged(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if editor?.handleKey(event) == true { return }
        // While drawing, a key without a command does nothing: drawing only
        // stops for Command+T or Esc.
        if editor?.isDrawing == true { return }
        super.keyDown(with: event)
    }
}

/// Note editor: the note's text on a dark page, with ink, shapes and numbered
/// markers drawn over it and the marker lines in the Note box underneath, as
/// in the screenshot editor. Command+T types on the page and Command+D draws.
/// It is the third screen of the note flow (rename ⇄ note ⇄ editor); the flow
/// saves.
@MainActor
final class InkNoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSPopoverDelegate {
    enum Mode { case type, draw }

    enum Tool {
        case pen, line, arrow, rectangle, ellipse, marker, select, highlighter, eraser

        var shape: InkShape? {
            switch self {
            case .line: return .line
            case .arrow: return .arrow
            case .rectangle: return .rectangle
            case .ellipse: return .ellipse
            case .pen, .marker, .select, .highlighter, .eraser: return nil
            }
        }
    }

    /// What Select picked: a stroke or shape, or a marker (by index).
    enum Selection: Equatable { case item(Int), marker(Int) }

    /// What the editor asks the flow to do, with the note as it is now.
    enum Action: Equatable {
        case save(InkNoteDocument)
        case copyAndSave(InkNoteDocument)
        case close(InkNoteDocument)
        case backToNote(InkNoteDocument)
    }

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
    private static let penCursor = ringCursor(diameter: 8)
    private static let eraserCursor = ringCursor(diameter: 22)

    var onAction: ((Action) -> Void)?
    private(set) var noteDocument: InkNoteDocument
    let history = UndoManager()
    let textView = InkNoteTextView(frame: .zero)
    /// The editor opens for drawing: Tab from the note window is how you get here to draw.
    private(set) var mode: Mode = .draw
    private(set) var tool: Tool = .pen
    private(set) var palette: [EditorPaletteColor]
    private(set) var colorHex: String
    private let settingsStore: SettingsStore?
    private var paletteObserver: NSObjectProtocol?
    /// Stroke outlines, index-aligned with the first `paths.count` items.
    private var paths: [CGPath] = []
    private var current: InkStroke?
    private var shapeDrag: (start: CGPoint, end: CGPoint)?
    /// The note before an eraser sweep or marker drag, for its one undo step.
    private var gestureStart: InkNoteDocument?
    private var draggedMarker: (index: Int, offset: CGPoint)?
    private(set) var selection: Selection?
    private var lastSelectDragPoint: CGPoint?
    private let scrollView = NSScrollView()
    let noteBar = EditorNotePreviewBar(text: "", maxHeight: 200)
    private(set) var markerNotePopover: NSPopover?
    private var modeButtons: [Mode: NSButton] = [:]
    private var toolButtons: [Tool: NSButton] = [:]
    private var swatches: [InkSwatchButton] = []
    private let swatchRow = NSStackView()
    private var keyMonitor: Any?
    private var layoutObservation: KeyboardLayoutObservation?
    private(set) var shortcutOverlay: EditorShortcutOverlayController?
    private(set) var shortcutHints: [EditorShortcutHint] = []
    private var fixedHints: [EditorShortcutHint] = []

    var isDrawing: Bool { mode == .draw }

    /// The tool's cursor while drawing; `nil` while typing (the I-beam).
    var drawingCursor: NSCursor? {
        guard isDrawing else { return nil }
        switch tool {
        case .eraser: return Self.eraserCursor
        case .marker: return .crosshair
        case .select: return .arrow
        default: return Self.penCursor
        }
    }

    init(noteDocument: InkNoteDocument, title: String, settingsStore: SettingsStore? = nil) {
        self.noteDocument = noteDocument
        self.settingsStore = settingsStore
        palette = Self.noteColors(forPaletteIDs: settingsStore?.settings.editorColorIDs ?? EditorPalette.defaultIDs)
        colorHex = palette.first?.hex ?? "#ff3b30"
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        AppTheme.apply(to: window)
        window.title = title
        window.minSize = NSSize(width: 760, height: 400)
        window.backgroundColor = InkNoteRenderer.background
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        window.center()
        buildUI()
        textView.string = InkNoteRenderer.pageText(noteDocument)
        restoreKeyInterceptor()
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
        updateLayout()
    }

    // MARK: - Building

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let bar = makeToolbar()
        let line = NSBox()
        line.boxType = .separator

        textView.editor = self
        textView.delegate = self
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // A fixed column, laid out exactly like the saved picture.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: InkNoteRenderer.columnWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: InkNoteRenderer.margin, height: InkNoteRenderer.margin)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = InkNoteRenderer.background
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
        textView.typingAttributes = InkNoteRenderer.textAttributes

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = InkNoteRenderer.background
        scrollView.documentView = textView
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // The Note box looks like the marker lines burned into the saved picture.
        noteBar.wantsLayer = true
        noteBar.layer?.backgroundColor = WorkflowNoteRenderer.noteBackgroundColor.cgColor

        let stack = NSStackView(views: [bar, line, scrollView, noteBar])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        content.layoutSubtreeIfNeeded()
    }

    /// The screenshot editor's grouped icon toolbar: mode, tools, ink,
    /// history, then close / copy / save on the right.
    private func makeToolbar() -> NSStackView {
        func button(_ symbol: String, _ toolTip: String, _ action: Selector) -> NSButton {
            let button = EditorToolbarStyle.iconButton(symbol: symbol, toolTip: toolTip)
            button.target = self
            button.action = action
            return button
        }
        modeButtons = [.type: button("character.cursor.ibeam", "Type on the page (Cmd+T)", #selector(typePressed)),
                       .draw: button("scribble.variable", "Draw (Cmd+D)", #selector(drawPressed))]
        // The screenshot editor's tool icons, in its order.
        let tools: [(Tool, String)] = [(.pen, "pencil.tip"), (.line, "line.diagonal"), (.arrow, "arrow.right"),
                                       (.rectangle, "square"), (.ellipse, "circle"), (.marker, "1.circle"),
                                       (.select, "rectangle.dashed"), (.highlighter, "highlighter"), (.eraser, "eraser")]
        for (tool, symbol) in tools { toolButtons[tool] = button(symbol, "", #selector(toolPressed(_:))) }
        swatchRow.spacing = 2
        rebuildSwatches()
        let undo = button("arrow.uturn.left", "Undo (Cmd+Z)", #selector(undoPressed))
        let redo = button("arrow.uturn.right", "Redo (Cmd+Shift+Z)", #selector(redoPressed))
        let clear = button("trash", "Clear drawing and markers (Option+Backspace while drawing)", #selector(clearPressed))
        let close = button("xmark", "Close (Esc while drawing)", #selector(closePressed))
        let copy = button("doc.on.doc", "Copy + save (Cmd+Enter)", #selector(copyPressed))
        let save = button("tray.and.arrow.down", "Save (Enter while drawing)", #selector(savePressed))
        fixedHints = [
            .init(view: modeButtons[.type]!, key: "⌘T", label: "Type on the page (Esc goes back to drawing)"),
            .init(view: modeButtons[.draw]!, key: "⌘D", label: "Draw"),
            .init(view: undo, key: "⌘Z", label: "Undo"),
            .init(view: redo, key: "⌘⇧Z", label: "Redo"),
            .init(view: clear, key: "⌥⌫", label: "Clear drawing and markers, while drawing"),
            .init(view: close, key: "Esc", label: "Close, while drawing"),
            .init(view: copy, key: "⌘↩", label: "Copy + save"),
            .init(view: save, key: "↩", label: "Save, while drawing (⇧⇥ goes back to the note)")
        ]

        let modes: [NSView] = [Mode.type, .draw].compactMap { modeButtons[$0] }
        let drawing: [NSView] = [Tool.pen, .line, .arrow, .rectangle, .ellipse, .marker, .select].compactMap { toolButtons[$0] }
        let ink: [NSView] = [Tool.highlighter, .eraser].compactMap { toolButtons[$0] } + [swatchRow]
        let groups = [modes, drawing, ink, [undo, redo, clear], [close, copy, save]].map { EditorToolbarStyle.group($0) }
        // Groups keep their natural width; the spacer takes the spare width.
        groups.forEach { $0.setContentHuggingPriority(.init(999), for: .horizontal) }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: Array(groups.dropLast()) + [spacer, groups[groups.count - 1]])
        bar.distribution = .fill
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
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
        let tools: [(Tool, String, Int)] = [(.pen, "Pen", kVK_ANSI_W), (.line, "Line", kVK_ANSI_D), (.arrow, "Arrow", kVK_ANSI_A),
                                            (.rectangle, "Rectangle, hold ⇧ for a square", kVK_ANSI_R),
                                            (.ellipse, "Ellipse, hold ⇧ for a circle", kVK_ANSI_E),
                                            (.marker, "Numbered marker, double-click one to write its note", kVK_ANSI_F),
                                            (.select, "Select: click to pick, drag to move, Delete to remove", kVK_ANSI_S),
                                            (.highlighter, "Highlighter", kVK_ANSI_H), (.eraser, "Eraser", kVK_ANSI_X)]
        var hints: [EditorShortcutHint] = []
        for (tool, title, code) in tools {
            guard let button = toolButtons[tool] else { continue }
            button.toolTip = "\(title) (\(key(code)) while drawing)"
            hints.append(.init(view: button, key: key(code), label: "\(title), while drawing"))
        }
        let color = key(kVK_ANSI_Q)
        for swatch in swatches { swatch.toolTip = "\(swatch.colorName) (\(color) while drawing picks the next color)" }
        hints.append(.init(view: swatchRow, key: color, label: "Next color, while drawing"))
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

    private func restoreKeyInterceptor() {
        (window as? EditorWindow)?.keyEquivalentInterceptor = { [weak self] event in self?.handleKey(event) ?? false }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { history }

    func windowDidResize(_ notification: Notification) { updateLayout() }

    /// Where the page's text column sits in the text view: centered, below a
    /// margin. Note positions are page coordinates, so resizing the window
    /// moves text and drawing together.
    var pageOrigin: CGPoint { textView.textContainerOrigin }

    private func viewRect(_ pageRect: CGRect) -> CGRect {
        pageRect.offsetBy(dx: pageOrigin.x, dy: pageOrigin.y)
    }

    /// Centers the column and keeps the page at least as big as the window
    /// and everything drawn, so far-off drawings scroll into view.
    private func updateLayout() {
        let visible = scrollView.contentSize
        let side = max(InkNoteRenderer.margin, floor((visible.width - InkNoteRenderer.columnWidth) / 2))
        if textView.textContainerInset.width != side {
            textView.textContainerInset = NSSize(width: side, height: InkNoteRenderer.margin)
        }
        let drawing = InkNoteRenderer.contentBounds(noteDocument)
        let content = drawing.isNull ? CGRect.zero : viewRect(drawing)
        textView.minSize = NSSize(width: max(visible.width, content.maxX + InkNoteRenderer.margin),
                                  height: max(visible.height, content.maxY + InkNoteRenderer.margin))
        textView.frame.size.width = textView.minSize.width
        textView.sizeToFit()
        noteBar.maxHeight = max(60, (window?.contentView?.bounds.height ?? 600) / 3)
        textView.needsDisplay = true
    }

    // MARK: - Note

    /// Every drawing change goes through here, so ⌘Z steps through ink and
    /// text in the order they happened.
    private func setDocument(_ new: InkNoteDocument) {
        let old = noteDocument
        guard new != old else { return }
        textView.breakUndoCoalescing()
        history.registerUndo(withTarget: self) { $0.setDocument(old) }
        if !new.items.starts(with: old.items) { paths = [] }
        noteDocument = new
        refresh()
    }

    private func refresh() {
        switch selection {
        case .item(let index) where !noteDocument.items.indices.contains(index): selection = nil
        case .marker(let index) where !noteDocument.markers.indices.contains(index): selection = nil
        default: break
        }
        // Undo can bring back older text; typing itself never comes this way.
        let text = InkNoteRenderer.pageText(noteDocument)
        if textView.string.trimmingCharacters(in: .whitespacesAndNewlines) != text { textView.string = text }
        // The typed text is on the page; the Note box holds the marker lines.
        let lines = InkNoteRenderer.markerLines(noteDocument)
        noteBar.text = lines
        noteBar.isHidden = lines.isEmpty
        updateLayout()
    }

    /// Typing on the page edits the note's text; its marker lines stay.
    func textDidChange(_ notification: Notification) {
        noteDocument.note = MarkerNoteLogic.joined(text: textView.string, markerLines: InkNoteRenderer.markerLines(noteDocument))
        updateLayout()
    }

    func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
                  toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
        InkNoteRenderer.textAttributes
    }

    func drawInk() {
        if paths.count > noteDocument.items.count { paths = [] }
        paths += noteDocument.items[paths.count...].map { InkGeometry.path(for: $0.stroke) }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: pageOrigin.x, y: pageOrigin.y)
        InkNoteRenderer.draw(noteDocument, current: current, paths: paths, drawsText: false)
        drawSelectionOutline()
        context.restoreGState()
    }

    /// The screenshot editor's selection outlines: orange dashes around a
    /// stroke or shape, thin white dashes around a marker. Never saved.
    private func drawSelectionOutline() {
        let path: NSBezierPath
        switch selection {
        case .item(let index) where noteDocument.items.indices.contains(index):
            path = NSBezierPath(rect: InkNoteRenderer.itemBounds(noteDocument.items[index]).insetBy(dx: -5, dy: -5))
            path.setLineDash([5, 3], count: 2, phase: 0)
            path.lineWidth = 2
            NSColor.systemOrange.withAlphaComponent(0.95).setStroke()
        case .marker(let index) where noteDocument.markers.indices.contains(index):
            path = NSBezierPath(rect: InkNoteRenderer.markerBounds(noteDocument.markers[index]).insetBy(dx: -3, dy: -3))
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.lineWidth = 1
            NSColor.white.withAlphaComponent(0.8).setStroke()
        default:
            return
        }
        path.stroke()
    }

    /// The marker or stroke under `point`, topmost first, as Select sees it.
    func selectable(at point: CGPoint) -> Selection? {
        if let index = markerIndex(at: point) { return .marker(index) }
        return noteDocument.items.indices.reversed().first { index in
            let item = noteDocument.items[index]
            return item.stroke.hits(CGPoint(x: point.x - item.x, y: point.y - item.y), padding: 8)
        }.map { .item($0) }
    }

    /// Delete or Backspace with Select. A marker takes its Note box line along.
    func deleteSelection() {
        guard let selection else { return }
        var new = noteDocument
        switch selection {
        case .item(let index) where new.items.indices.contains(index):
            new.items.remove(at: index)
        case .marker(let index) where new.markers.indices.contains(index):
            new.markers.remove(at: index)
            new.note = MarkerNoteLogic.removingLines(notIn: Set(new.markers.map(\.number)), from: new.note)
        default:
            break
        }
        self.selection = nil
        setDocument(new)
        textView.needsDisplay = true
    }

    /// Adds a finished stroke (in page coordinates) to the note.
    func commit(_ absolute: InkStroke) {
        var stroke = absolute
        let origin = stroke.localize()
        stroke.roundToSavedPrecision()
        var new = noteDocument
        new.items.append(.init(stroke: stroke, x: origin.x, y: origin.y))
        setDocument(new)
    }

    /// Stamps the next number, continuing past the highest marker so removing
    /// one never renumbers the others.
    func addMarker(at point: CGPoint) {
        var new = noteDocument
        let number = min((new.markers.map(\.number).max() ?? 0) + 1, EditorDrawing.MarkerItem.maxNumber)
        new.markers.append(.init(number: number, x: point.x, y: point.y, color: colorHex))
        setDocument(new)
    }

    func markerIndex(at point: CGPoint) -> Int? {
        noteDocument.markers.lastIndex { InkNoteRenderer.markerBounds($0).insetBy(dx: -4, dy: -4).contains(point) }
    }

    /// Writes marker `number`'s line in the Note box; empty text removes it.
    func setMarkerNote(_ number: Int, text: String) {
        var new = noteDocument
        new.note = MarkerNoteLogic.update(note: new.note, number: number, newText: text)
        setDocument(new)
    }

    /// Removes strokes and markers under the eraser. Undo is registered once,
    /// when the sweep ends.
    func erase(at point: CGPoint) {
        let before = (noteDocument.items.count, noteDocument.markers.count)
        noteDocument.items.removeAll { item in item.stroke.hits(CGPoint(x: point.x - item.x, y: point.y - item.y)) }
        noteDocument.markers.removeAll { InkNoteRenderer.markerBounds($0).contains(point) }
        if before != (noteDocument.items.count, noteDocument.markers.count) {
            paths = []
            textView.needsDisplay = true
        }
    }

    /// Option+Backspace while drawing, like Clear in the screenshot editor; one undo step.
    func clearInk() {
        var new = noteDocument
        new.items = []
        new.markers = []
        new.note = MarkerNoteLogic.removingLines(notIn: [], from: new.note)
        setDocument(new)
    }

    /// Ends an eraser sweep or marker drag as one undo step. Erased markers
    /// take their Note box lines with them, as in the screenshot editor.
    private func finishGesture() {
        guard let start = gestureStart else { return }
        gestureStart = nil
        draggedMarker = nil
        lastSelectDragPoint = nil
        var after = noteDocument
        after.note = MarkerNoteLogic.removingLines(notIn: Set(after.markers.map(\.number)), from: after.note)
        noteDocument = start
        setDocument(after)
    }

    // MARK: - Mouse

    /// The mouse in page coordinates.
    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let point = textView.convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x - pageOrigin.x, y: point.y - pageOrigin.y)
    }

    private func inkPoint(_ event: NSEvent) -> InkPoint {
        let point = canvasPoint(event)
        return InkPoint(x: point.x, y: point.y, pressure: event.subtype == .tabletPoint ? CGFloat(event.pressure) : -1)
    }

    func canvasMouseDown(_ event: NSEvent) {
        window?.makeFirstResponder(textView)
        let point = canvasPoint(event)
        switch tool {
        case .eraser:
            gestureStart = noteDocument
            erase(at: point)
        case .select:
            selection = selectable(at: point)
            if selection != nil {
                gestureStart = noteDocument
                lastSelectDragPoint = point
            }
            textView.needsDisplay = true
        case .marker:
            guard let index = markerIndex(at: point) else {
                addMarker(at: point)
                return
            }
            if event.clickCount >= 2 {
                presentMarkerNotePopover(number: noteDocument.markers[index].number)
                return
            }
            gestureStart = noteDocument
            let marker = noteDocument.markers[index]
            draggedMarker = (index, CGPoint(x: point.x - marker.x, y: point.y - marker.y))
        case .pen, .highlighter:
            current = InkStroke(tool: tool == .highlighter ? .highlighter : .pen, color: colorHex,
                                width: tool == .highlighter ? 17 : 3.2, points: [inkPoint(event)])
            textView.needsDisplay = true
        case .line, .arrow, .rectangle, .ellipse:
            shapeDrag = (point, point)
            current = InkStroke(tool: .shape, color: colorHex, width: Self.shapeWidth, points: [])
        }
    }

    func canvasMouseDragged(_ event: NSEvent) {
        let point = canvasPoint(event)
        if let drag = draggedMarker {
            noteDocument.markers[drag.index].x = point.x - drag.offset.x
            noteDocument.markers[drag.index].y = point.y - drag.offset.y
            textView.needsDisplay = true
        } else if let last = lastSelectDragPoint, let selection {
            let dx = point.x - last.x, dy = point.y - last.y
            switch selection {
            case .item(let index):
                noteDocument.items[index].x += dx
                noteDocument.items[index].y += dy
            case .marker(let index):
                noteDocument.markers[index].x += dx
                noteDocument.markers[index].y += dy
            }
            lastSelectDragPoint = point
            textView.needsDisplay = true
        } else if gestureStart != nil {
            erase(at: point)
        } else if shapeDrag != nil {
            shapeDrag?.end = point
            updateShape(constrained: event.modifierFlags.contains(.shift))
        } else if let stroke = current {
            current?.points.append(inkPoint(event))
            // Only the growing end of a stroke changes shape.
            let tail = InkStroke(tool: stroke.tool, color: stroke.color, width: stroke.width,
                                 points: Array(stroke.points.suffix(13)) + [inkPoint(event)])
            textView.setNeedsDisplay(viewRect(tail.bounds.insetBy(dx: -stroke.width - 8, dy: -stroke.width - 8)))
        } else {
            return
        }
        textView.autoscroll(with: event)
    }

    func canvasMouseUp(_ event: NSEvent) {
        if gestureStart != nil {
            finishGesture()
            return
        }
        guard let stroke = current else { return }
        current = nil
        if shapeDrag != nil {
            shapeDrag = nil
            // A click with a shape tool draws nothing, as in the screenshot editor.
            guard stroke.bounds.width >= 2 || stroke.bounds.height >= 2 else {
                textView.needsDisplay = true
                return
            }
        }
        commit(stroke)
    }

    /// Redraws the shape being dragged; Shift makes a square or a circle.
    private func updateShape(constrained: Bool) {
        guard let drag = shapeDrag, let shape = tool.shape, var stroke = current else { return }
        let old = stroke.bounds
        stroke.points = shape.points(from: drag.start, to: drag.end, constrained: constrained)
            .map { InkPoint(x: $0.x, y: $0.y, pressure: -1) }
        current = stroke
        textView.setNeedsDisplay(viewRect(old.union(stroke.bounds).insetBy(dx: -stroke.width - 4, dy: -stroke.width - 4)))
    }

    func modifiersChanged(_ event: NSEvent) {
        if shapeDrag != nil { updateShape(constrained: event.modifierFlags.contains(.shift)) }
    }

    // MARK: - Marker notes

    /// The screenshot editor's marker note popover: Enter writes "N: text"
    /// into the Note box.
    func presentMarkerNotePopover(number: Int) {
        guard let marker = noteDocument.markers.first(where: { $0.number == number }) else { return }
        markerNotePopover?.close()
        let limit = InkNoteDocument.maximumNoteLength
        let capacity = MarkerNoteLogic.capacity(note: noteDocument.note, number: number, limit: limit)
        let field = MarkerNoteField(string: MarkerNoteLogic.text(for: number, in: noteDocument.note) ?? "")
        field.maxLength = capacity
        field.placeholderString = capacity > 0 ? "Note for \(number)…" : "Note is full (\(limit.formatted()) characters)"
        field.font = NSFont.systemFont(ofSize: 13)
        field.frame = NSRect(x: 10, y: 10, width: 300, height: 24)
        // Only Enter commits; focus changes while the popover opens must not.
        field.cell?.sendsActionOnEndEditing = false
        field.target = self
        field.action = #selector(markerNoteCommitted(_:))
        field.tag = number
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        content.addSubview(field)
        let controller = NSViewController()
        controller.view = content

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        markerNotePopover = popover
        (window as? EditorWindow)?.keyEquivalentInterceptor = { [weak field] event in
            field?.handleEditingShortcut(event) ?? false
        }
        guard textView.window != nil else { return }
        popover.show(relativeTo: viewRect(InkNoteRenderer.markerBounds(marker)), of: textView, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeFirstResponder(field)
    }

    @objc private func markerNoteCommitted(_ sender: NSTextField) {
        let text = MarkerNoteLogic.sanitized(sender.stringValue)
        markerNotePopover?.close()
        markerNotePopover = nil
        restoreKeyInterceptor()
        window?.makeFirstResponder(textView)
        setMarkerNote(sender.tag, text: text)
    }

    func popoverDidClose(_ notification: Notification) {
        // A stale close (after a newer popover opened) must not restore shortcuts.
        let closed = notification.object as? NSPopover
        guard markerNotePopover == nil || closed === markerNotePopover else { return }
        markerNotePopover = nil
        restoreKeyInterceptor()
    }

    // MARK: - Modes, tools and keys

    func setMode(_ new: Mode) {
        mode = new
        if new == .type { current = nil; shapeDrag = nil; selection = nil }
        syncControls()
    }

    /// Picking a tool, by key or button, starts drawing.
    func setTool(_ new: Tool) {
        if new != .select { selection = nil }
        tool = new
        setMode(.draw)
    }

    func setColor(_ index: Int) {
        guard palette.indices.contains(index) else { return }
        colorHex = palette[index].hex
        if tool == .eraser { tool = .pen }
        setMode(.draw)
    }

    /// Q steps through the palette like the screenshot editor's color key.
    func nextColor() {
        let current = palette.firstIndex { $0.hex == colorHex } ?? -1
        setColor((current + 1) % max(1, palette.count))
    }

    private func syncControls() {
        modeButtons.forEach { EditorToolbarStyle.setActive($0.value, $0.key == mode) }
        toolButtons.forEach { EditorToolbarStyle.setActive($0.value, isDrawing && $0.key == tool) }
        swatches.forEach { $0.isChosen = $0.hex == colorHex }
        window?.invalidateCursorRects(for: textView)
        if let window, textView.visibleRect.contains(textView.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            (drawingCursor ?? .iBeam).set()
        }
    }

    // Toolbar clicks run the same commands as their keys, then hand focus back to the page.
    @objc private func typePressed() { perform(.type) }
    @objc private func drawPressed() { perform(.draw) }
    @objc private func undoPressed() { perform(.undo) }
    @objc private func redoPressed() { perform(.redo) }
    @objc private func clearPressed() { perform(.clearInk) }
    @objc private func closePressed() { onAction?(.close(noteDocument)) }
    @objc private func copyPressed() { perform(.copyAndSave) }
    @objc private func savePressed() { perform(.save) }

    @objc private func toolPressed(_ sender: NSButton) {
        if let tool = toolButtons.first(where: { $0.value === sender })?.key { perform(.tool(tool)) }
    }

    @objc private func swatchClicked(_ sender: InkSwatchButton) {
        if let index = swatches.firstIndex(where: { $0 === sender }) { setColor(index) }
        window?.makeFirstResponder(textView)
    }

    @discardableResult
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let command = InkNoteKeymap.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                                                  flags: event.modifierFlags, isDrawing: isDrawing) else { return false }
        perform(command)
        return true
    }

    func perform(_ command: InkNoteKeymap.Command) {
        switch command {
        case .type: setMode(.type)
        case .draw: setMode(.draw)
        case .tool(let tool): setTool(tool)
        case .nextColor: nextColor()
        case .clearInk: clearInk()
        case .deleteSelection: deleteSelection()
        case .undo: undo()
        case .redo: redo()
        case .selectAll: textView.selectAll(nil)
        case .copy: textView.copy(nil)
        case .cut: textView.cut(nil)
        case .paste: textView.paste(nil)
        case .save: onAction?(.save(noteDocument))
        case .copyAndSave: onAction?(.copyAndSave(noteDocument))
        case .close:
            // Esc lets go of a selection first, as in the screenshot editor.
            if selection != nil {
                selection = nil
                textView.needsDisplay = true
            } else {
                onAction?(.close(noteDocument))
            }
        case .backToNote: onAction?(.backToNote(noteDocument))
        }
        if let window, window.isVisible, window.firstResponder !== textView, markerNotePopover == nil {
            window.makeFirstResponder(textView)
        }
    }

    func undo() {
        selection = nil
        textView.breakUndoCoalescing()
        if history.canUndo { history.undo() }
        textView.needsDisplay = true
    }

    func redo() {
        selection = nil
        if history.canRedo { history.redo() }
        textView.needsDisplay = true
    }

    /// The red close button closes like Esc; the flow decides whether to ask.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        perform(.close)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        markerNotePopover?.close()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        shortcutOverlay?.cancel()
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

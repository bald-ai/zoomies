import AppKit
import Carbon

/// High-level tool selection for the editor canvas.
/// Exposed separately so other parts of the app can talk to the canvas
/// without depending on its internal implementation details.
enum EditorTool: Hashable {
    case pen
    case line
    case arrow
    case rectangle
    case ellipse
    case text
    case marker
    case selection
}

/// Main drawing canvas used by the screenshot editor.
///
/// Responsibilities:
/// - Draw the base image
/// - Manage annotation items (pen, arrow, rectangle, ellipse, text)
/// - Handle mouse/keyboard input for drawing and text editing
/// - Provide an undo stack (up to 30 steps)
/// - Communicate high-level key commands back to the window controller
final class EditorCanvasView: NSView, NSTextViewDelegate {
    // MARK: - Commands sent back to the controller

    enum KeyCommand: Equatable {
        case finalAction(ScreenshotFinalAction)
        case zoomIn
        case zoomOut
        case zoomReset
        case undo
        case redo
        case clear
        case selectColor(index: Int)
        case backToNote
        case selectTool(EditorTool)
        case cycleColor
        case toggleColorPicker
        case colorPickerMove(direction: Int)
        case colorPickerSelect
        case colorPickerClose
        case copyToClipboard
        case cutSelectionToClipboard
        case pasteSelectionInCanvas
    }

    /// Type used by EditorWindowController when switching tools.
    typealias Tool = EditorTool

    /// Callback for key-level commands (zoom, undo, final actions, color).
    var onKeyCommand: ((KeyCommand) -> Void)?

    // MARK: - Public state

    let baseImage: NSImage
    var currentTool: Tool = .pen
    var currentColor: NSColor = .systemRed {
        // Palette writes this property directly; keep the marker cursor
        // preview in sync no matter which path assigns the color.
        didSet { invalidateMarkerCursorPreview() }
    }
    var isColorPickerOpen: Bool = false
    /// Test/debug hook fired whenever the marker cursor preview is invalidated.
    var onMarkerCursorInvalidation: (() -> Void)?
    /// Test/debug hook fired with each partial (gesture-only) invalidation rect.
    var onPartialInvalidation: ((NSRect) -> Void)?
    private let escapeFinalAction: ScreenshotFinalAction

    // MARK: - Internal model

    private var items: [EditorDrawing.Item] = []
    private var undoStack: [[EditorDrawing.Item]] = []
    private var redoStack: [[EditorDrawing.Item]] = []
    private let maxUndoLevels = 30
    private let annotationStrokeWidth: CGFloat = 4.0
    private var baseImageOrigin: NSPoint = .zero
    /// PNG encoding of `baseImage`, reused by every `editableState()` call.
    /// Valid only while nothing mutates `baseImage` after init (no
    /// `lockFocus`, `addRepresentation`, or size changes); `let` alone does not
    /// make an `NSImage` immutable.
    private var baseImagePNGCache: Data?

    // In-progress drawing state
    private var currentPoints: [NSPoint] = [] // for pen
    private var dragStartPoint: NSPoint?
    private var dragCurrentPoint: NSPoint?
    /// Shift state from the latest mouse/modifier event. Preview and commit both
    /// read this instead of the global modifier state so they always agree.
    private var constrainShapes = false

    // Text editing/dragging
    private var editingTextIndex: Int?
    private var textEditor: EditorInlineTextView?
    private var draggingTextIndex: Int?
    private var textDragOffset: NSPoint = .zero
    private var didPushUndoForTextDrag = false
    private var shouldPushUndoOnTextEnd = false
    private var textInteractionActive = false
    private var selectedTextIndex: Int?
    private var editingOriginalText: String?
    private var editingWasNewItem = false
    private var isCommittingText = false
    private var isCancellingText = false
    // Marker selection and dragging. Numbers are assigned on placement.
    private var selectedMarkerIndex: Int?
    private var draggingMarkerIndex: Int?
    private var markerDragOffset: NSPoint = .zero
    private var didPushUndoForMarkerDrag = false
    // Rectangle selection state.
    private var selectionRect: NSRect?
    private var selectionDragStart: NSPoint?
    private var selectionDragCurrent: NSPoint?
    private var isCutSelectionPreview = false

    // In-canvas pasted-image state for quick repositioning workflow.
    private var selectedImageIndex: Int?
    private var selectedItemIndex: Int?
    private var draggingItemIndex: Int?
    private var lastItemDragPoint: NSPoint?
    private var didPushUndoForItemDrag = false
    private var draggingImageIndex: Int?
    private var imageDragOffset: NSPoint = .zero
    private var didPushUndoForImageDrag = false
    private var copiedSelectionImage: NSImage?
    private var copiedSelectionRect: NSRect?
    private var pasteCascadeCount = 0
    private var lastMousePoint: NSPoint?
    private var trackingArea: NSTrackingArea?

    // MARK: - Init

    init(image: NSImage, escapeFinalAction: ScreenshotFinalAction = .deleteOnly, initialState: EditorCanvasState? = nil) {
        self.escapeFinalAction = escapeFinalAction
        let baseOrigin = NSPoint(x: EditorDrawing.canvasEdgeInset, y: EditorDrawing.canvasEdgeInset)
        self.baseImageOrigin = baseOrigin
        // A pending composite already contains the current annotations. When
        // editable state is available, restore its clean base image instead and
        // redraw the annotations exactly once.
        let restored = initialState.flatMap { state -> EditorDrawing? in
            guard state.isSafeToRestore() else { return nil }
            return EditorDrawing(restoring: state,
                                 baseImageOrigin: baseOrigin,
                                 fallbackBaseImage: image)
        }
        self.baseImage = restored?.baseImage ?? image
        self.items = restored?.items ?? []
        // Reuse the state's bytes only when they actually became the base
        // image; restoring falls back to `image` if they fail to decode.
        if let restored, restored.baseImage !== image {
            self.baseImagePNGCache = initialState?.baseImagePNG
        }
        let frameSize = NSSize(width: baseImage.size.width + EditorDrawing.canvasEdgeInset * 2,
                               height: baseImage.size.height + EditorDrawing.canvasEdgeInset * 2)
        let frame = NSRect(origin: .zero, size: frameSize)
        super.init(frame: frame)
        if restored != nil {
            updateCanvasSizeIfNeeded()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let backingObserver {
            NotificationCenter.default.removeObserver(backingObserver)
            self.backingObserver = nil
        }
        guard let window else { return }
        backingObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification,
            object: window,
            queue: nil) { [weak self] _ in
                self?.invalidateMarkerCursorPreview()
            }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Public API (Agent 3 spec)

    func setTool(_ tool: EditorTool) {
        textInteractionActive = false
        currentTool = tool
        if tool != .text {
            selectedTextIndex = nil
            draggingTextIndex = nil
            didPushUndoForTextDrag = false
        }
        if tool != .marker {
            selectedMarkerIndex = nil
            draggingMarkerIndex = nil
            didPushUndoForMarkerDrag = false
        }
        // Re-selecting Text keeps its inline editor; changing tools commits it.
        if textEditor != nil, tool != .text {
            endTextEditingIfNeeded()
        }
        if tool != .selection {
            clearSelectionState()
            selectedImageIndex = nil
            selectedItemIndex = nil
            draggingItemIndex = nil
            lastItemDragPoint = nil
            didPushUndoForItemDrag = false
            draggingImageIndex = nil
            didPushUndoForImageDrag = false
        }
        invalidateMarkerCursorPreview()
        needsDisplay = true
    }

    func setColor(_ color: NSColor) {
        currentColor = color
    }

    /// Ensure the full visible workspace can receive drawing events.
    func ensureDrawableAreaCoversVisibleSize(_ visibleSize: NSSize) {
        let targetWidth = max(frame.size.width, minimumCanvasSize.width, ceil(visibleSize.width))
        let targetHeight = max(frame.size.height, minimumCanvasSize.height, ceil(visibleSize.height))
        let targetSize = NSSize(width: targetWidth, height: targetHeight)
        guard targetSize != frame.size else { return }

        let dx = (targetSize.width - frame.size.width) / 2
        let dy = (targetSize.height - frame.size.height) / 2
        shiftCanvasContent(byX: dx, byY: dy)
        setFrameSize(targetSize)
        needsDisplay = true
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        if redoStack.count >= maxUndoLevels {
            redoStack.removeFirst()
        }
        redoStack.append(items)
        items = previous
        resetTransientSelectionState()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        if undoStack.count >= maxUndoLevels {
            undoStack.removeFirst()
        }
        undoStack.append(items)
        items = next
        resetTransientSelectionState()
    }

    private func resetTransientSelectionState() {
        updateCanvasSizeIfNeeded()
        selectedTextIndex = nil
        draggingTextIndex = nil
        didPushUndoForTextDrag = false
        selectedImageIndex = nil
        selectedItemIndex = nil
        draggingItemIndex = nil
        lastItemDragPoint = nil
        didPushUndoForItemDrag = false
        draggingImageIndex = nil
        didPushUndoForImageDrag = false
        selectedMarkerIndex = nil
        draggingMarkerIndex = nil
        didPushUndoForMarkerDrag = false
        clearSelectionState()
        invalidateMarkerCursorPreview()
        needsDisplay = true
    }

    func clearAll() {
        if items.isEmpty {
            _ = clearSelectionIfNeeded()
            return
        }
        pushUndoSnapshot()
        items.removeAll()
        selectedTextIndex = nil
        draggingTextIndex = nil
        didPushUndoForTextDrag = false
        selectedImageIndex = nil
        selectedItemIndex = nil
        draggingItemIndex = nil
        lastItemDragPoint = nil
        didPushUndoForItemDrag = false
        draggingImageIndex = nil
        didPushUndoForImageDrag = false
        selectedMarkerIndex = nil
        draggingMarkerIndex = nil
        didPushUndoForMarkerDrag = false
        clearSelectionState()
        endTextEditingIfNeeded()
        baseImageOrigin = NSPoint(x: EditorDrawing.canvasEdgeInset, y: EditorDrawing.canvasEdgeInset)
        setFrameSize(minimumCanvasSize)
        invalidateMarkerCursorPreview()
        needsDisplay = true
    }

    func compositeImage() -> NSImage {
        endTextEditingIfNeeded()
        let drawing = currentDrawing()
        return EditorImageRenderer.compositeImage(of: drawing,
                                                  croppingTo: EditorImageRenderer.exportBounds(of: drawing))
    }

    /// Snapshot of the base image and committed items for the renderer.
    private func currentDrawing() -> EditorDrawing {
        EditorDrawing(baseImage: baseImage, baseImageOrigin: baseImageOrigin, items: items)
    }

    func editableState() -> EditorCanvasState? {
        endTextEditingIfNeeded()
        if baseImagePNGCache == nil {
            baseImagePNGCache = ImageEncoding.pngData(from: baseImage)
        }
        guard let basePNG = baseImagePNGCache else { return nil }
        return EditorCanvasState(baseImagePNG: basePNG,
                                 baseImageOrigin: EditorCanvasState.Point(baseImageOrigin),
                                 items: items.compactMap { $0.stateItem })
    }

    @discardableResult
    func selectEditableItem(at point: NSPoint) -> Bool {
        guard let index = hitTestEditableItem(at: point) else { return false }
        selectedImageIndex = nil
        draggingImageIndex = nil
        selectedItemIndex = index
        selectionRect = nil
        selectionDragStart = nil
        selectionDragCurrent = nil
        isCutSelectionPreview = false
        needsDisplay = true
        return true
    }

    /// Renders the currently selected region from the composited image.
    func renderSelectedRegionImage() -> NSImage? {
        guard let rect = clampedSelectionRect else { return nil }
        return EditorImageRenderer.compositeImage(of: currentDrawing(), croppingTo: rect)
    }

    func selectedRegionPayload() -> (image: NSImage, rect: NSRect)? {
        guard let rect = clampedSelectionRect,
              let image = renderSelectedRegionImage() else {
            return nil
        }
        copiedSelectionImage = image
        copiedSelectionRect = rect
        pasteCascadeCount = 0
        return (image, rect)
    }

    @discardableResult
    func cutSelectedRegion() -> Bool {
        guard let rect = clampedSelectionRect else { return false }
        pushUndoSnapshot()
        items.append(.erase(rect: rect))
        selectionRect = rect
        selectionDragStart = nil
        selectionDragCurrent = nil
        isCutSelectionPreview = true
        updateCanvasSizeIfNeeded()
        needsDisplay = true
        return true
    }

    @discardableResult
    func pasteCopiedSelection() -> Bool {
        guard let image = copiedSelectionImage,
              let sourceRect = copiedSelectionRect else {
            return false
        }
        let targetRect: NSRect
        if let mousePoint = lastMousePoint {
            let centeredOrigin = NSPoint(x: mousePoint.x - sourceRect.width / 2,
                                         y: mousePoint.y - sourceRect.height / 2)
            let proposed = NSRect(origin: centeredOrigin, size: sourceRect.size)
            targetRect = clampedRectToImageBounds(proposed) ?? sourceRect
        } else {
            let offset = CGFloat(12 * pasteCascadeCount)
            targetRect = sourceRect.offsetBy(dx: offset, dy: offset)
        }
        pushUndoSnapshot()
        items.append(.image(image: image, rect: targetRect))
        selectedImageIndex = items.count - 1
        draggingImageIndex = nil
        didPushUndoForImageDrag = false
        selectionRect = nil
        selectionDragStart = nil
        selectionDragCurrent = nil
        isCutSelectionPreview = false
        pasteCascadeCount += 1
        updateCanvasSizeIfNeeded()
        needsDisplay = true
        return true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Every visibility check below uses the full painted extent (strokes,
        // outlines, shadow, antialiasing) so partial redraws never skip a
        // decoration that reaches into the dirty rect.
        if baseImagePaintedBounds.intersects(dirtyRect) {
            drawBaseImageEdgeSeparation(in: baseImageBounds)
            baseImage.draw(in: baseImageBounds, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        }

        for item in items {
            guard let bounds = paintedBounds(for: item) else { continue }
            if bounds.intersects(dirtyRect) {
                EditorImageRenderer.draw(item: item)
            }
        }

        drawSelectionOverlays(in: dirtyRect)
        drawGesturePreview()
    }

    private func drawSelectionOverlays(in dirtyRect: NSRect) {
        if let selectionRect, selectionOutlinePaintedRect(selectionRect).intersects(dirtyRect) {
            drawSelectionOutline(selectionRect)
        }
        drawSelectedImageOutline(in: dirtyRect)
        drawSelectedItemOutline(in: dirtyRect)
        drawSelectedTextOutline(in: dirtyRect)
        drawSelectedMarkerOutline(in: dirtyRect)
    }

    private func drawSelectedImageOutline(in dirtyRect: NSRect) {
        if let selectedImageIndex,
           case let .image(_, rect) = items[selectedImageIndex],
           itemSelectionOutlinePaintedRect(rect).intersects(dirtyRect) {
            drawImageSelectionOutline(rect)
        }

    }

    private func drawSelectedItemOutline(in dirtyRect: NSRect) {
        if let selectedItemIndex,
           selectedItemIndex < items.count,
           let rect = itemSelectionOutlineBase(for: items[selectedItemIndex]),
           itemSelectionOutlinePaintedRect(rect).intersects(dirtyRect) {
            drawItemSelectionOutline(rect)
        }

    }

    private func drawSelectedTextOutline(in dirtyRect: NSRect) {
        if let index = selectedTextIndex, textEditor == nil {
            if case let .text(textItem) = items[index] {
                let rect = textSelectionOutlineRect(for: textItem)
                if outlinePaintedRect(rect, lineWidth: 1).intersects(dirtyRect) {
                    drawDashedSelectionOutline(rect)
                }
            }
        }

    }

    private func drawSelectedMarkerOutline(in dirtyRect: NSRect) {
        if let index = selectedMarkerIndex, textEditor == nil, index < items.count {
            if case let .marker(markerItem) = items[index] {
                let rect = markerSelectionOutlineRect(for: markerItem)
                if outlinePaintedRect(rect, lineWidth: 1).intersects(dirtyRect) {
                    drawDashedSelectionOutline(rect)
                }
            }
        }

    }

    private func drawGesturePreview() {
        // In-progress shapes
        if let start = dragStartPoint, let current = dragCurrentPoint {
            drawShapePreview(from: start, to: current)
        } else if let start = selectionDragStart, let current = selectionDragCurrent {
            let rect = normalizedRect(from: start, to: current)
            drawSelectionOutline(rect)
        } else if currentTool == .pen && !currentPoints.isEmpty {
            EditorImageRenderer.drawPen(points: currentPoints, color: currentColor, lineWidth: annotationStrokeWidth, isPreview: true)
        }
    }

    private func drawShapePreview(from start: NSPoint, to current: NSPoint) {
        let shiftHeld = constrainShapes
        switch currentTool {
        case .pen:
            EditorImageRenderer.drawPen(points: currentPoints, color: currentColor, lineWidth: annotationStrokeWidth, isPreview: true)
        case .line:
            EditorImageRenderer.drawPen(points: [start, current], color: currentColor, lineWidth: annotationStrokeWidth, isPreview: true)
        case .arrow:
            EditorImageRenderer.drawArrow(from: start, to: current, color: currentColor, lineWidth: annotationStrokeWidth, isPreview: true)
        case .rectangle:
            let rect = normalizedRect(from: start, to: current, constrain: shiftHeld)
            EditorImageRenderer.drawRect(rect, color: currentColor, lineWidth: annotationStrokeWidth, isPreview: true)
        case .ellipse:
            let rect = normalizedRect(from: start, to: current, constrain: shiftHeld)
            EditorImageRenderer.drawEllipse(rect, color: currentColor, lineWidth: annotationStrokeWidth, isPreview: true)
        case .text, .marker, .selection:
            break
        }
    }

    private static let baseImageShadowBlur: CGFloat = 3
    private static let baseImageShadowOffset: CGFloat = 1

    /// Keep screenshot edges visible against both light and dark native backgrounds.
    private func drawBaseImageEdgeSeparation(in rect: NSRect) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        let borderRect = rect.insetBy(dx: -0.5, dy: -0.5)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = Self.baseImageShadowBlur
        shadow.shadowOffset = NSSize(width: 0, height: -Self.baseImageShadowOffset)
        shadow.set()

        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = 1
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectionOutline(_ rect: NSRect) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        if isCutSelectionPreview {
            NSColor.white.withAlphaComponent(0.16).setFill()
            rect.fill()
        }
        let path = NSBezierPath(rect: rect)
        let dash: [CGFloat] = [6, 4]
        path.setLineDash(dash, count: dash.count, phase: 0)
        let strokeColor = isCutSelectionPreview
            ? NSColor.systemOrange.withAlphaComponent(0.95)
            : NSColor.white.withAlphaComponent(0.92)
        strokeColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func drawImageSelectionOutline(_ rect: NSRect) {
        drawItemSelectionOutline(rect)
    }

    private func drawItemSelectionOutline(_ rect: NSRect) {
        let outlineRect = rect.insetBy(dx: -2, dy: -2)
        guard outlineRect.width >= 1, outlineRect.height >= 1 else { return }
        let path = NSBezierPath(rect: outlineRect)
        let dash: [CGFloat] = [5, 3]
        path.setLineDash(dash, count: dash.count, phase: 0)
        NSColor.systemOrange.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    /// Dashed outline around a selected text item or marker.
    private func drawDashedSelectionOutline(_ rect: NSRect) {
        let path = NSBezierPath(rect: rect)
        let dash: [CGFloat] = [4, 3]
        path.setLineDash(dash, count: dash.count, phase: 0)
        NSColor.white.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// Rect passed to `drawItemSelectionOutline` for a selected non-image item.
    private func itemSelectionOutlineBase(for item: EditorDrawing.Item) -> NSRect? {
        EditorImageRenderer.bounds(for: item)?.insetBy(dx: -3, dy: -3)
    }

    private func textSelectionOutlineRect(for item: EditorDrawing.TextItem) -> NSRect {
        EditorImageRenderer.textBounds(for: item).insetBy(dx: -2, dy: -2)
    }

    private func markerSelectionOutlineRect(for item: EditorDrawing.MarkerItem) -> NSRect {
        EditorImageRenderer.markerBounds(for: item).insetBy(dx: -2, dy: -2)
    }

    // MARK: - Painted bounds & partial invalidation

    /// Device pixels per canvas unit: live magnification times backing scale.
    private var deviceScale: CGFloat {
        let scale = canvasToScreenScale * (window?.backingScaleFactor ?? 1)
        return (scale.isFinite && scale > 0) ? scale : 1
    }

    /// Grows `rect` by one device pixel of antialiasing and rounds it out to
    /// the device-pixel grid, so the margin stays correct at any zoom level.
    private func deviceAligned(_ rect: NSRect) -> NSRect {
        let scale = deviceScale
        let padded = rect.insetBy(dx: -1 / scale, dy: -1 / scale)
        let minX = floor(padded.minX * scale) / scale
        let minY = floor(padded.minY * scale) / scale
        let maxX = ceil(padded.maxX * scale) / scale
        let maxY = ceil(padded.maxY * scale) / scale
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Area touched by stroking `rect` with a line of `lineWidth`.
    private func outlinePaintedRect(_ rect: NSRect, lineWidth: CGFloat) -> NSRect {
        deviceAligned(rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2))
    }

    private func selectionOutlinePaintedRect(_ rect: NSRect) -> NSRect {
        outlinePaintedRect(rect, lineWidth: 2)
    }

    /// Area painted by `drawItemSelectionOutline(rect)`.
    private func itemSelectionOutlinePaintedRect(_ rect: NSRect) -> NSRect {
        outlinePaintedRect(rect.insetBy(dx: -2, dy: -2), lineWidth: 2)
    }

    /// Base image plus its 1pt border and drop shadow. Shadow blur and offset
    /// are applied in screen space, so their reach in canvas units grows as the
    /// canvas is zoomed out. Twice the blur radius covers the Gaussian tail.
    private var baseImagePaintedBounds: NSRect {
        let shadowReach = (2 * Self.baseImageShadowBlur + Self.baseImageShadowOffset) / canvasToScreenScale
        let reach = 1 + shadowReach
        return deviceAligned(baseImageBounds.insetBy(dx: -reach, dy: -reach))
    }

    private func paintedBounds(for item: EditorDrawing.Item) -> NSRect? {
        EditorImageRenderer.bounds(for: item).map(deviceAligned)
    }

    /// Painted area of an item plus whichever selection outline is drawn for it.
    private func paintedBoundsIncludingSelection(ofItemAt index: Int) -> NSRect? {
        guard items.indices.contains(index) else { return nil }
        let item = items[index]
        var rects = [paintedBounds(for: item)].compactMap { $0 }
        if index == selectedImageIndex, case let .image(_, rect) = item {
            rects.append(itemSelectionOutlinePaintedRect(rect))
        }
        if index == selectedItemIndex, let base = itemSelectionOutlineBase(for: item) {
            rects.append(itemSelectionOutlinePaintedRect(base))
        }
        rects += textSelectionPaintedRects(for: item, at: index)
        return rects.dropFirst().reduce(rects.first) { $0?.union($1) }
    }

    private func textSelectionPaintedRects(for item: EditorDrawing.Item, at index: Int) -> [NSRect] {
        guard textEditor == nil else { return [] }
        var rects: [NSRect] = []
        if index == selectedTextIndex, case let .text(textItem) = item {
            rects.append(outlinePaintedRect(textSelectionOutlineRect(for: textItem), lineWidth: 1))
        }
        if index == selectedMarkerIndex, case let .marker(markerItem) = item {
            rects.append(outlinePaintedRect(markerSelectionOutlineRect(for: markerItem), lineWidth: 1))
        }
        return rects
    }

    /// Canvas region the in-flight drag gesture currently paints, or nil when
    /// no drag gesture is active.
    private func activeGestureDirtyRect() -> NSRect? {
        if let start = selectionDragStart, let current = selectionDragCurrent {
            return selectionOutlinePaintedRect(normalizedRect(from: start, to: current))
        }
        if let index = [draggingImageIndex, draggingItemIndex, draggingTextIndex, draggingMarkerIndex].compactMap({ $0 }).first {
            return paintedBoundsIncludingSelection(ofItemAt: index)
        }
        guard let start = dragStartPoint, let current = dragCurrentPoint else { return nil }
        return shapeGestureBounds(from: start, to: current).map(deviceAligned)
    }

    private func shapeGestureBounds(from start: NSPoint, to current: NSPoint) -> NSRect? {
        let halfWidth = annotationStrokeWidth / 2
        let rect: NSRect?
        switch currentTool {
        case .pen:
            // Appending a point only reshapes the smoothed curve across the
            // last three points; earlier segments are geometrically unchanged.
            // CoreGraphics may re-rasterize them by at most one level (of 255),
            // which the full redraw on mouse-up clears.
            rect = EditorImageRenderer.boundsForPoints(Array(currentPoints.suffix(3)), padding: halfWidth)
        case .line:
            rect = EditorImageRenderer.boundsForPoints([start, current], padding: halfWidth)
        case .arrow:
            rect = EditorImageRenderer.boundsForArrow(start: start, end: current, lineWidth: annotationStrokeWidth)
        case .rectangle, .ellipse:
            // Cover both the free and Shift-constrained preview so a modifier
            // change between events can never strand the other shape.
            rect = normalizedRect(from: start, to: current)
                .union(normalizedRect(from: start, to: current, constrain: true))
                .insetBy(dx: -halfWidth, dy: -halfWidth)
        case .text, .marker, .selection:
            rect = nil
        }
        return rect
    }

    /// Invalidates what the gesture painted before (`before`) and paints now.
    private func invalidateGesture(from before: NSRect?) {
        let after = activeGestureDirtyRect()
        guard let dirty = [before, after].compactMap({ $0 }).reduce(nil, { $0?.union($1) ?? $1 }) else { return }
        setNeedsDisplay(dirty)
        onPartialInvalidation?(dirty)
    }

    private var defaultTextFontSize: CGFloat {
        // Annotation size follows the image, not the editor window or zoom.
        // A gentler curve keeps small captures readable without oversized
        // annotations on full-screen captures. 1000 canvas units remains 40.
        let size = 40 * pow(baseImage.size.width / 1000, 0.65)
        return min(max(size, 16), ImageSafetyLimits.runtime.maxFontSize)
    }

    /// Marker diameter shares the text font-size calculation so markers scale
    /// identically to text under canvas zoom and image export.
    private var defaultMarkerDiameter: CGFloat {
        defaultTextFontSize
    }

    /// Next sequential marker number: one more than the highest existing
    /// marker. Deriving it from the items keeps numbering correct across
    /// delete, undo/redo, clear, and reopened images without a separate
    /// counter that could drift. `nil` once the supported range is exhausted;
    /// the guard ordering means `+ 1` can never overflow Int.
    private var nextMarkerNumber: Int? {
        guard let maxNumber = items.lazy.compactMap({ item -> Int? in
            guard case let .marker(marker) = item else { return nil }
            return marker.number
        }).max() else {
            return 1
        }
        guard maxNumber < EditorDrawing.MarkerItem.maxNumber else { return nil }
        return maxNumber + 1
    }

    // MARK: - Geometry helpers

    private var baseImageBounds: NSRect {
        NSRect(x: baseImageOrigin.x, y: baseImageOrigin.y, width: baseImage.size.width, height: baseImage.size.height)
    }

    private var minimumCanvasSize: NSSize {
        NSSize(width: baseImage.size.width + EditorDrawing.canvasEdgeInset * 2,
               height: baseImage.size.height + EditorDrawing.canvasEdgeInset * 2)
    }

    private func shiftCanvasContent(byX dx: CGFloat, byY dy: CGFloat) {
        guard dx != 0 || dy != 0 else { return }

        baseImageOrigin = EditorImageRenderer.shiftedPoint(baseImageOrigin, byX: dx, byY: dy)
        items = EditorImageRenderer.shiftedItems(items, byX: dx, byY: dy)
        undoStack = undoStack.map { EditorImageRenderer.shiftedItems($0, byX: dx, byY: dy) }
        redoStack = redoStack.map { EditorImageRenderer.shiftedItems($0, byX: dx, byY: dy) }

        dragStartPoint = dragStartPoint.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) }
        dragCurrentPoint = dragCurrentPoint.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) }
        currentPoints = currentPoints.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) }

        selectionDragStart = selectionDragStart.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) }
        selectionDragCurrent = selectionDragCurrent.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) }
        selectionRect = selectionRect.map { EditorImageRenderer.shiftedRect($0, byX: dx, byY: dy) }

        copiedSelectionRect = copiedSelectionRect.map { EditorImageRenderer.shiftedRect($0, byX: dx, byY: dy) }
        lastMousePoint = lastMousePoint.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) }

        if let editor = textEditor {
            editor.frame = EditorImageRenderer.shiftedRect(editor.frame, byX: dx, byY: dy)
        }
    }

    private func moveItem(at index: Int, byX dx: CGFloat, byY dy: CGFloat) {
        guard index < items.count, dx != 0 || dy != 0 else { return }

        items[index] = EditorImageRenderer.shiftedItem(items[index], byX: dx, byY: dy)
    }

    private var clampedSelectionRect: NSRect? {
        guard let selectionRect else { return nil }
        let clipped = selectionRect.intersection(baseImageBounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }

        let minX = max(baseImageBounds.minX, floor(clipped.minX))
        let minY = max(baseImageBounds.minY, floor(clipped.minY))
        let maxX = min(baseImageBounds.maxX, ceil(clipped.maxX))
        let maxY = min(baseImageBounds.maxY, ceil(clipped.maxY))
        guard maxX > minX, maxY > minY else { return nil }

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clearSelectionState() {
        selectionRect = nil
        selectionDragStart = nil
        selectionDragCurrent = nil
        isCutSelectionPreview = false
    }

    private func clearSelectionIfNeeded() -> Bool {
        guard selectionRect != nil else { return false }
        clearSelectionState()
        needsDisplay = true
        return true
    }

    private func clampedRectToImageBounds(_ rect: NSRect) -> NSRect? {
        let size = rect.size
        guard size.width > 0, size.height > 0 else { return nil }
        guard size.width <= baseImageBounds.width, size.height <= baseImageBounds.height else { return nil }

        let minX = baseImageBounds.minX
        let minY = baseImageBounds.minY
        let maxX = baseImageBounds.maxX - size.width
        let maxY = baseImageBounds.maxY - size.height

        let clampedX = min(max(rect.origin.x, minX), maxX)
        let clampedY = min(max(rect.origin.y, minY), maxY)
        return NSRect(x: clampedX, y: clampedY, width: size.width, height: size.height)
    }

    private func normalizedRect(from p1: NSPoint, to p2: NSPoint, constrain: Bool = false) -> NSRect {
        var dx = p2.x - p1.x
        var dy = p2.y - p1.y
        if constrain {
            let side = max(abs(dx), abs(dy))
            dx = dx >= 0 ? side : -side
            dy = dy >= 0 ? side : -side
        }
        let end = NSPoint(x: p1.x + dx, y: p1.y + dy)
        let minX = min(p1.x, end.x)
        let maxX = max(p1.x, end.x)
        let minY = min(p1.y, end.y)
        let maxY = max(p1.y, end.y)
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func distance(from point: NSPoint, toSegmentStart start: NSPoint, end: NSPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return EditorImageRenderer.distance(from: point, to: start) }

        let progress = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clampedProgress = max(0, min(1, progress))
        let projection = NSPoint(x: start.x + clampedProgress * dx,
                                 y: start.y + clampedProgress * dy)
        return EditorImageRenderer.distance(from: point, to: projection)
    }

    private func pushUndoSnapshot() {
        if undoStack.count >= maxUndoLevels {
            undoStack.removeFirst()
        }
        undoStack.append(items)
        redoStack.removeAll()
    }

    /// Ensure the canvas is large enough to contain the base image and all annotations.
    private func updateCanvasSizeIfNeeded() {
        var unionRect = baseImageBounds

        for item in items {
            guard let itemBounds = EditorImageRenderer.bounds(for: item) else { continue }
            unionRect = unionRect.union(itemBounds)
        }

        let newWidth = max(unionRect.maxX, minimumCanvasSize.width, frame.size.width)
        let newHeight = max(unionRect.maxY, minimumCanvasSize.height, frame.size.height)
        guard let width = ImageSafety.pixelLength(newWidth),
              let height = ImageSafety.pixelLength(newHeight),
              ImageSafety.canAllocateBitmap(width: width, height: height) else {
            return
        }
        let newSize = NSSize(width: CGFloat(width), height: CGFloat(height))

        if newSize != frame.size {
            setFrameSize(newSize)
            needsDisplay = true
        }
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = point
        constrainShapes = event.modifierFlags.contains(.shift)

        switch currentTool {
        case .selection: beginSelectionGesture(at: point); return
        case .text: beginTextGesture(at: point, clickCount: event.clickCount); return
        case .marker: beginMarkerGesture(at: point); return
        default: break
        }

        selectedTextIndex = nil
        selectedItemIndex = nil
        draggingItemIndex = nil
        lastItemDragPoint = nil
        didPushUndoForItemDrag = false
        endTextEditingIfNeeded()

        dragStartPoint = point
        dragCurrentPoint = point
        currentPoints.removeAll()

        if currentTool == .pen {
            currentPoints.append(point)
        }

        needsDisplay = true
    }

    private func beginSelectionGesture(at point: NSPoint) {
        selectedTextIndex = nil
        endTextEditingIfNeeded()
        if let (index, rect) = hitTestImage(at: point) {
            selectedImageIndex = index
            selectedItemIndex = nil
            draggingItemIndex = nil
            lastItemDragPoint = nil
            didPushUndoForItemDrag = false
            draggingImageIndex = index
            imageDragOffset = NSPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
            didPushUndoForImageDrag = false
            clearSelectionState()
            needsDisplay = true
            return
        }
        selectedImageIndex = nil
        draggingImageIndex = nil
        if selectEditableItem(at: point) {
            draggingItemIndex = selectedItemIndex
            lastItemDragPoint = point
            didPushUndoForItemDrag = false
            return
        }
        selectedItemIndex = nil
        draggingItemIndex = nil
        lastItemDragPoint = nil
        didPushUndoForItemDrag = false
        selectionRect = nil
        selectionDragStart = point
        selectionDragCurrent = point
        isCutSelectionPreview = false
        needsDisplay = true
        return
    }

    private func beginTextGesture(at point: NSPoint, clickCount: Int) {
        let activeBounds = activeTextBounds
        if (textInteractionActive || textEditor != nil),
           activeBounds?.contains(point) != true {
            endTextEditingIfNeeded()
            setTool(.pen)
            onKeyCommand?(.selectTool(.pen))
            // Consume this click; the next gesture starts the pen stroke.
            return
        }
        // Finishing a new, empty text item can remove it from `items`.
        // Commit before hit testing so the index we pass to the editor is
        // always derived from the current collection.
        endTextEditingIfNeeded()

        if let (index, rect) = hitTestText(at: point) {
            textInteractionActive = true
            selectedTextIndex = index
            selectedItemIndex = nil
            draggingItemIndex = nil
            lastItemDragPoint = nil
            didPushUndoForItemDrag = false
            if clickCount >= 2 {
                beginEditingText(at: index, pushUndoOnEnd: true, isNewItem: false)
            } else {
                draggingTextIndex = index
                didPushUndoForTextDrag = false
                textDragOffset = NSPoint(x: point.x - rect.origin.x, y: point.y - rect.origin.y)
            }
            needsDisplay = true
            return
        } else {
            selectedTextIndex = nil
            selectedItemIndex = nil
            draggingItemIndex = nil
            lastItemDragPoint = nil
            didPushUndoForItemDrag = false

            let item = EditorDrawing.TextItem(text: "", origin: point, color: currentColor, fontSize: defaultTextFontSize)
            pushUndoSnapshot()
            items.append(.text(item))
            let index = items.count - 1
            selectedTextIndex = index
            beginEditingText(at: index, pushUndoOnEnd: false, isNewItem: true)
            updateCanvasSizeIfNeeded()
            needsDisplay = true
            return
        }
    }

    private func beginMarkerGesture(at point: NSPoint) {
        // Commit any open inline editor before hit testing, like the text flow.
        endTextEditingIfNeeded()
        if let (index, rect) = hitTestMarker(at: point) {
            selectedMarkerIndex = index
            selectedTextIndex = nil
            selectedImageIndex = nil
            selectedItemIndex = nil
            draggingItemIndex = nil
            lastItemDragPoint = nil
            didPushUndoForItemDrag = false
            // Repeated clicks only select or drag; number editing is disabled.
            draggingMarkerIndex = index
            didPushUndoForMarkerDrag = false
            markerDragOffset = NSPoint(x: point.x - rect.midX, y: point.y - rect.midY)
            needsDisplay = true
            return
        }

        selectedMarkerIndex = nil
        selectedTextIndex = nil
        selectedImageIndex = nil
        selectedItemIndex = nil
        draggingItemIndex = nil
        lastItemDragPoint = nil
        didPushUndoForItemDrag = false

        // Range exhausted (all numbers up to the supported cap in use):
        // refuse placement rather than duplicate or wrap.
        guard let number = nextMarkerNumber else {
            needsDisplay = true
            return
        }
        let marker = EditorDrawing.MarkerItem(number: number,
                                            center: point,
                                            color: currentColor,
                                            diameter: defaultMarkerDiameter)
        pushUndoSnapshot()
        items.append(.marker(marker))
        selectedMarkerIndex = items.count - 1
        updateCanvasSizeIfNeeded()
        invalidateMarkerCursorPreview()
        needsDisplay = true
        return
    }

    private var activeTextBounds: NSRect? {
        if let editor = textEditor { return editor.frame }
        guard let index = selectedTextIndex, items.indices.contains(index),
              case .text(let item) = items[index] else { return nil }
        return EditorImageRenderer.textBounds(for: item)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = point
        // Only the gesture's before/after footprint changes during a drag.
        // `defer` covers every early return below.
        let paintedBeforeDrag = activeGestureDirtyRect()
        defer { invalidateGesture(from: paintedBeforeDrag) }
        constrainShapes = event.modifierFlags.contains(.shift)

        if currentTool == .selection {
            dragSelection(to: point)
            return
        }
        if draggingTextIndex != nil {
            dragText(to: point)
            return
        }
        if draggingMarkerIndex != nil {
            dragMarker(to: point)
            return
        }

        guard dragStartPoint != nil else { return }

        dragCurrentPoint = point

        if currentTool == .pen {
            currentPoints.append(point)
        }
    }

    private func dragSelection(to point: NSPoint) {
        if let index = draggingImageIndex {
            dragImage(at: index, to: point)
            return
        }
        if let index = draggingItemIndex, index < items.count, let lastPoint = lastItemDragPoint {
            if !didPushUndoForItemDrag {
                pushUndoSnapshot()
                didPushUndoForItemDrag = true
            }
            moveItem(at: index, byX: point.x - lastPoint.x, byY: point.y - lastPoint.y)
            lastItemDragPoint = point
            return
        }
        guard selectionDragStart != nil else { return }
        selectionDragCurrent = point
        return
    }

    private func dragImage(at index: Int, to point: NSPoint) {
        if !didPushUndoForImageDrag {
            pushUndoSnapshot()
            didPushUndoForImageDrag = true
        }
        if case let .image(image, oldRect) = items[index] {
            let newOrigin = NSPoint(x: point.x - imageDragOffset.x, y: point.y - imageDragOffset.y)
            let newRect = NSRect(origin: newOrigin, size: oldRect.size)
            items[index] = .image(image: image, rect: newRect)
        }
    }

    private func dragText(to point: NSPoint) {
        if let index = draggingTextIndex {
            if case var .text(item) = items[index] {
                let newOrigin = NSPoint(x: point.x - textDragOffset.x, y: point.y - textDragOffset.y)
                guard newOrigin != item.origin else { return }
                if !didPushUndoForTextDrag {
                    pushUndoSnapshot()
                    didPushUndoForTextDrag = true
                }
                item.origin = newOrigin
                items[index] = .text(item)
            }
            return
        }

    }

    private func dragMarker(to point: NSPoint) {
        if let index = draggingMarkerIndex {
            if case var .marker(item) = items[index] {
                let newCenter = NSPoint(x: point.x - markerDragOffset.x, y: point.y - markerDragOffset.y)
                guard newCenter != item.center else { return }
                if !didPushUndoForMarkerDrag {
                    pushUndoSnapshot()
                    didPushUndoForMarkerDrag = true
                }
                item.center = newCenter
                items[index] = .marker(item)
            }
            return
        }

    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let paintedBefore = activeGestureDirtyRect()
        constrainShapes = event.modifierFlags.contains(.shift)
        if dragStartPoint != nil && (currentTool == .rectangle || currentTool == .ellipse) {
            invalidateGesture(from: paintedBefore)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = point
        constrainShapes = event.modifierFlags.contains(.shift)

        if currentTool == .selection {
            finishSelection(at: point)
            return
        }

        if draggingTextIndex != nil {
            draggingTextIndex = nil
            didPushUndoForTextDrag = false
            updateCanvasSizeIfNeeded()
            needsDisplay = true
            return
        }

        if draggingMarkerIndex != nil {
            draggingMarkerIndex = nil
            didPushUndoForMarkerDrag = false
            updateCanvasSizeIfNeeded()
            needsDisplay = true
            return
        }
        guard let start = dragStartPoint else { return }
        dragCurrentPoint = point

        if let item = completedShape(from: start, to: point) {
            pushUndoSnapshot()
            items.append(item)
            updateCanvasSizeIfNeeded()
        }

        dragStartPoint = nil
        dragCurrentPoint = nil
        currentPoints.removeAll()
        needsDisplay = true
    }

    private func finishSelection(at point: NSPoint) {
        if draggingImageIndex != nil {
            draggingImageIndex = nil
            selectedItemIndex = nil
            didPushUndoForImageDrag = false
            updateCanvasSizeIfNeeded()
            needsDisplay = true
            return
        }
        if draggingItemIndex != nil {
            draggingItemIndex = nil
            lastItemDragPoint = nil
            didPushUndoForItemDrag = false
            updateCanvasSizeIfNeeded()
            needsDisplay = true
            return
        }
        guard let start = selectionDragStart else { return }
        selectionDragCurrent = point
        let rect = normalizedRect(from: start, to: point)
        selectionDragStart = nil
        selectionDragCurrent = nil
        selectionRect = rect.width >= 2 && rect.height >= 2 ? rect : nil
        if let clampedRect = clampedSelectionRect {
            selectionRect = clampedRect
        } else {
            selectionRect = nil
        }
        isCutSelectionPreview = false
        needsDisplay = true
        return
    }

    /// Build a committed item before changing history. Invalid/tiny gestures
    /// leave both the canvas and undo stack untouched.
    private func completedShape(from start: NSPoint, to point: NSPoint) -> EditorDrawing.Item? {
        switch currentTool {
        case .pen:
            guard currentPoints.count > 1 else { return nil }
            return .pen(points: currentPoints, color: currentColor, lineWidth: annotationStrokeWidth)
        case .line, .arrow:
            return completedLine(from: start, to: point)
        case .rectangle, .ellipse:
            return completedArea(from: start, to: point)
        case .text, .marker, .selection:
            return nil
        }
    }

    private func completedLine(from start: NSPoint, to point: NSPoint) -> EditorDrawing.Item? {
        guard EditorImageRenderer.distance(from: start, to: point) >= 2 else { return nil }
        if currentTool == .line {
            return .pen(points: [start, point], color: currentColor, lineWidth: annotationStrokeWidth)
        }
        return .arrow(start: start, end: point, color: currentColor, lineWidth: annotationStrokeWidth)
    }

    private func completedArea(from start: NSPoint, to point: NSPoint) -> EditorDrawing.Item? {
        let rect = normalizedRect(from: start, to: point, constrain: constrainShapes)
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        if currentTool == .rectangle {
            return .rect(rect: rect, color: currentColor, lineWidth: annotationStrokeWidth)
        }
        return .ellipse(rect: rect, color: currentColor, lineWidth: annotationStrokeWidth)
    }

    // MARK: - Text editing helpers

    private func hitTestText(at point: NSPoint) -> (Int, NSRect)? {
        for index in items.indices.reversed() {
            guard case let .text(textItem) = items[index] else { continue }
            let rect = EditorImageRenderer.textBounds(for: textItem)
            if rect.insetBy(dx: -4, dy: -4).contains(point) {
                return (index, rect)
            }
        }
        return nil
    }

    private func hitTestMarker(at point: NSPoint) -> (Int, NSRect)? {
        for index in items.indices.reversed() {
            guard case let .marker(markerItem) = items[index] else { continue }
            let rect = EditorImageRenderer.markerRect(for: markerItem).insetBy(dx: -4, dy: -4)
            let radius = rect.height / 2
            if NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).contains(point) {
                return (index, rect)
            }
        }
        return nil
    }

    private func hitTestImage(at point: NSPoint) -> (Int, NSRect)? {
        for index in items.indices.reversed() {
            guard case let .image(_, rect) = items[index] else { continue }
            if rect.insetBy(dx: -3, dy: -3).contains(point) {
                return (index, rect)
            }
        }
        return nil
    }

    private func hitTestEditableItem(at point: NSPoint) -> Int? {
        for index in items.indices.reversed() {
            guard !isImageItem(items[index]),
                  hitTest(item: items[index], at: point) else {
                continue
            }
            return index
        }
        return nil
    }

    private func isImageItem(_ item: EditorDrawing.Item) -> Bool {
        if case .image = item {
            return true
        }
        return false
    }

    private func hitTest(item: EditorDrawing.Item, at point: NSPoint) -> Bool {
        switch item {
        case .pen(let points, _, let lineWidth):
            return hitTestPolyline(points, at: point, tolerance: selectionTolerance(for: lineWidth))
        case .arrow(let start, let end, _, let lineWidth):
            return hitTestArrow(start: start, end: end, at: point, tolerance: selectionTolerance(for: lineWidth))
        case .rect(let rect, _, let lineWidth):
            return hitTestRectStroke(rect, at: point, tolerance: selectionTolerance(for: lineWidth))
        case .ellipse(let rect, _, let lineWidth):
            return hitTestEllipseStroke(rect, at: point, tolerance: selectionTolerance(for: lineWidth))
        case .text(let textItem):
            return EditorImageRenderer.textBounds(for: textItem).insetBy(dx: -4, dy: -4).contains(point)
        case .marker(let markerItem):
            let rect = EditorImageRenderer.markerRect(for: markerItem).insetBy(dx: -4, dy: -4)
            let radius = rect.height / 2
            return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).contains(point)
        case .image(_, let rect), .erase(let rect):
            return rect.insetBy(dx: -3, dy: -3).contains(point)
        }
    }

    private func selectionTolerance(for lineWidth: CGFloat) -> CGFloat {
        max(8, lineWidth + 4)
    }

    private func hitTestPolyline(_ points: [NSPoint], at point: NSPoint, tolerance: CGFloat) -> Bool {
        guard points.count > 1 else { return false }
        for index in 1..<points.count {
            if distance(from: point, toSegmentStart: points[index - 1], end: points[index]) <= tolerance {
                return true
            }
        }
        return false
    }

    private func hitTestArrow(start: NSPoint, end: NSPoint, at point: NSPoint, tolerance: CGFloat) -> Bool {
        guard EditorImageRenderer.distance(from: start, to: end) >= 2 else { return false }
        if distance(from: point, toSegmentStart: start, end: end) <= tolerance {
            return true
        }

        let (point1, point2) = EditorImageRenderer.arrowHeadPoints(from: start, to: end)
        return distance(from: point, toSegmentStart: end, end: point1) <= tolerance
            || distance(from: point, toSegmentStart: end, end: point2) <= tolerance
    }

    private func hitTestRectStroke(_ rect: NSRect, at point: NSPoint, tolerance: CGFloat) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
        guard outer.contains(point) else { return false }
        let inner = rect.insetBy(dx: tolerance, dy: tolerance)
        guard inner.width > 0, inner.height > 0 else { return true }
        return !inner.contains(point)
    }

    private func hitTestEllipseStroke(_ rect: NSRect, at point: NSPoint, tolerance: CGFloat) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2
        guard radiusX > 0, radiusY > 0 else { return false }

        let normalizedX = (point.x - center.x) / radiusX
        let normalizedY = (point.y - center.y) / radiusY
        let value = normalizedX * normalizedX + normalizedY * normalizedY
        let maxRadius = max(radiusX, radiusY)
        let band = max(0.08, tolerance / maxRadius)
        let inner = max(0, 1 - band)
        let outer = 1 + band
        return value >= inner * inner && value <= outer * outer
    }

    private func makeInlineEditor(in frame: NSRect) -> EditorInlineTextView {
        let editor = EditorInlineTextView(frame: frame)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.drawsBackground = false
        editor.textContainerInset = EditorImageRenderer.textPadding
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.lineBreakMode = .byClipping
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude)
        editor.focusRingType = .none
        editor.delegate = self
        editor.onCommit = { [weak self] in
            self?.commitTextEditing()
        }
        editor.onCancel = { [weak self] in
            self?.cancelTextEditing()
        }
        editor.wantsLayer = true
        editor.layer?.borderWidth = 1
        editor.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        editor.layer?.cornerRadius = 4
        return editor
    }

    private func beginEditingText(at index: Int, pushUndoOnEnd: Bool, isNewItem: Bool) {
        endTextEditingIfNeeded()
        guard items.indices.contains(index),
              case let .text(item) = items[index] else {
            return
        }

        let rect = EditorImageRenderer.textBounds(for: item)
        let editor = makeInlineEditor(in: rect)
        editor.string = item.text
        editor.textColor = item.color
        editor.font = NSFont.systemFont(ofSize: item.fontSize, weight: .regular)
        editor.onDidChange = { [weak self] in
            self?.resizeTextEditorToFit()
        }

        addSubview(editor)
        window?.makeFirstResponder(editor)

        textInteractionActive = true
        editingTextIndex = index
        editingOriginalText = item.text
        editingWasNewItem = isNewItem
        shouldPushUndoOnTextEnd = pushUndoOnEnd
        textEditor = editor
        resizeTextEditorToFit()
    }

    private func resizeTextEditorToFit() {
        guard let editor = textEditor else { return }
        let font = editor.font ?? NSFont.systemFont(ofSize: defaultTextFontSize, weight: .regular)
        let text = editor.string
        let contentSize = EditorImageRenderer.textContentSize(for: text, font: font)
        let width = max(contentSize.width + EditorImageRenderer.textPadding.width * 2, 60)
        let height = max(contentSize.height + EditorImageRenderer.textPadding.height * 2, 28)
        editor.frame.size = NSSize(width: width, height: height)
    }

    private func commitTextEditing() {
        guard !isCommittingText else { return }
        guard let index = editingTextIndex,
              let editor = textEditor,
              items.indices.contains(index) else {
            removeTextEditor()
            return
        }
        isCommittingText = true
        defer { isCommittingText = false }

        updateTextItem(at: index, from: editor.string)

        removeTextEditor()
        updateCanvasSizeIfNeeded()
        needsDisplay = true
    }

    private func updateTextItem(at index: Int, from rawText: String) {
        let updatedText = trimTrailingWhitespace(rawText.replacingOccurrences(of: "\r", with: ""))
        let isEmpty = updatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isEmpty {
            if editingWasNewItem {
                items.remove(at: index)
                selectedTextIndex = nil
            } else if let original = editingOriginalText, case var .text(item) = items[index] {
                item.text = original
                items[index] = .text(item)
            }
        } else if case var .text(item) = items[index] {
            let textChanged = item.text != updatedText
            if shouldPushUndoOnTextEnd && textChanged {
                pushUndoSnapshot()
            }
            item.text = updatedText
            items[index] = .text(item)
            selectedTextIndex = index
        }

    }

    private func cancelTextEditing() {
        guard let index = editingTextIndex else { return }
        isCancellingText = true
        guard items.indices.contains(index) else {
            removeTextEditor()
            isCancellingText = false
            return
        }
        if editingWasNewItem {
            items.remove(at: index)
            selectedTextIndex = nil
        } else if let original = editingOriginalText, case var .text(item) = items[index] {
            item.text = original
            items[index] = .text(item)
            selectedTextIndex = index
        }
        removeTextEditor()
        updateCanvasSizeIfNeeded()
        needsDisplay = true
        isCancellingText = false
    }

    private func removeTextEditor() {
        textEditor?.removeFromSuperview()
        editingTextIndex = nil
        textEditor = nil
        editingOriginalText = nil
        editingWasNewItem = false
        shouldPushUndoOnTextEnd = false
        window?.makeFirstResponder(self)
    }

    private func endTextEditingIfNeeded() {
        if textEditor != nil {
            commitTextEditing()
        }
    }

    func textDidEndEditing(_ notification: Notification) {
        guard !isCancellingText else { return }
        commitTextEditing()
    }

    private func trimTrailingWhitespace(_ text: String) -> String {
        var value = text
        while let last = value.last, last.isWhitespace || last.isNewline {
            value.removeLast()
        }
        return value
    }

    private func deleteSelectedTextIfNeeded() -> Bool {
        guard let index = selectedTextIndex else { return false }
        pushUndoSnapshot()
        items.remove(at: index)
        selectedTextIndex = nil
        updateCanvasSizeIfNeeded()
        needsDisplay = true
        return true
    }

    private func deleteSelectedMarkerIfNeeded() -> Bool {
        guard let index = selectedMarkerIndex, index < items.count else { return false }
        pushUndoSnapshot()
        items.remove(at: index)
        selectedMarkerIndex = nil
        draggingMarkerIndex = nil
        didPushUndoForMarkerDrag = false
        updateCanvasSizeIfNeeded()
        invalidateMarkerCursorPreview()
        needsDisplay = true
        return true
    }

    private func deleteSelectedImageIfNeeded() -> Bool {
        guard let index = selectedImageIndex else { return false }
        guard case .image = items[index] else { return false }
        pushUndoSnapshot()
        items.remove(at: index)
        selectedImageIndex = nil
        draggingImageIndex = nil
        didPushUndoForImageDrag = false
        updateCanvasSizeIfNeeded()
        needsDisplay = true
        return true
    }

    private func deleteSelectedItemIfNeeded() -> Bool {
        guard let index = selectedItemIndex, index < items.count else { return false }
        pushUndoSnapshot()
        items.remove(at: index)
        selectedItemIndex = nil
        updateCanvasSizeIfNeeded()
        invalidateMarkerCursorPreview()
        needsDisplay = true
        return true
    }

    // MARK: - Keyboard & gestures

    override func keyDown(with event: NSEvent) {
        guard textEditor == nil else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Order matters: picker Escape precedes selection Escape, and final
        // actions (Cmd+Delete) precede deletion of an annotation.
        let handlers = [handlePaletteShortcut, handleToolShortcut, handleEditingShortcut,
                        handleEscapeShortcut, handleWorkflowShortcut, handleDeletionShortcut]
        for handler in handlers {
            if handler(event, flags) { return }
        }
        super.keyDown(with: event)
    }

    private func openPickerCommands(for key: UInt16) -> [KeyCommand]? {
        if let index = Self.colorPickerKeyCodeToColorIndex[key] {
            return [.selectColor(index: index), .colorPickerClose]
        }
        let navigation: [UInt16: KeyCommand] = [123: .colorPickerMove(direction: -1),
            124: .colorPickerMove(direction: 1), 36: .colorPickerSelect,
            76: .colorPickerSelect, 53: .colorPickerClose]
        return navigation[key].map { [$0] }
    }

    private func handlePaletteShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if event.keyCode == UInt16(kVK_ANSI_Q),
           flags.intersection([.command, .control, .option, .shift]).isEmpty {
            onKeyCommand?(.cycleColor)
            return true
        }
        if isColorPickerOpen, let commands = openPickerCommands(for: event.keyCode) {
            commands.forEach { onKeyCommand?($0) }
            return true
        }
        if flags.intersection([.command, .control, .shift]).isEmpty,
           Self.colorPickerToggleKeyCodes.contains(event.keyCode) {
            if !isColorPickerOpen { onKeyCommand?(.toggleColorPicker) }
            return true
        }
        return false
    }

    private func handleToolShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.intersection([.command, .control, .option, .shift]).isEmpty,
              let tool = Self.toolKeyCodeToTool[event.keyCode] else { return false }
        onKeyCommand?(.selectTool(tool))
        return true
    }

    private func handleEditingShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if flags.contains(.option), event.keyCode == 51 {
            onKeyCommand?(.clear)
            return true
        }
        guard flags.contains(.command), let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let commands: [String: KeyCommand] = ["=": .zoomIn, "+": .zoomIn, "-": .zoomOut,
            "0": .zoomReset, "c": .copyToClipboard, "x": .cutSelectionToClipboard,
            "v": .pasteSelectionInCanvas, "z": flags.contains(.shift) ? .redo : .undo]
        guard let command = commands[chars] else { return false }
        onKeyCommand?(command)
        return true
    }

    private func handleEscapeShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == 53 else { return false }
        if currentTool == .marker {
            setTool(.pen)
            onKeyCommand?(.selectTool(.pen))
            return true
        }
        return clearSelectionIfNeeded()
    }

    private func handleWorkflowShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if let final = interpretFinalAction(from: event, flags: flags) {
            onKeyCommand?(.finalAction(final))
            return true
        }
        if event.keyCode == 48, flags.contains(.shift) {
            onKeyCommand?(.backToNote)
            return true
        }
        return false
    }

    private func handleDeletionShortcut(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == 51 || event.keyCode == 117 else { return false }
        return deleteSelectedImageIfNeeded() || deleteSelectedItemIfNeeded()
            || deleteSelectedTextIfNeeded() || deleteSelectedMarkerIfNeeded()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd-based key equivalents can be intercepted by the window/menu before keyDown.
        // Handle editor commands here so they work reliably in the canvas.
        if textEditor != nil {
            return super.performKeyEquivalent(with: event)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        guard let command = Self.keyEquivalentCommand(chars: chars, flags: flags) else {
            return super.performKeyEquivalent(with: event)
        }
        onKeyCommand?(command)
        return true
    }

    private static func keyEquivalentCommand(chars: String, flags: NSEvent.ModifierFlags) -> KeyCommand? {
        if chars == "z", flags == [.command, .shift] { return .redo }
        guard flags == [.command] else { return nil }
        let commands: [String: KeyCommand] = ["z": .undo, "c": .copyToClipboard,
                                              "x": .cutSelectionToClipboard, "v": .pasteSelectionInCanvas]
        return commands[chars]
    }

    @objc func copy(_ sender: Any?) {
        guard textEditor == nil else { return }
        onKeyCommand?(.copyToClipboard)
    }

    @objc func cut(_ sender: Any?) {
        guard textEditor == nil else { return }
        onKeyCommand?(.cutSelectionToClipboard)
    }

    @objc func paste(_ sender: Any?) {
        guard textEditor == nil else { return }
        onKeyCommand?(.pasteSelectionInCanvas)
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)

        if event.magnification > 0 {
            onKeyCommand?(.zoomIn)
        } else if event.magnification < 0 {
            onKeyCommand?(.zoomOut)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        lastMousePoint = convert(event.locationInWindow, from: nil)
        super.mouseMoved(with: event)
    }

    // MARK: - Marker cursor preview

    /// While the marker tool is active the cursor becomes the badge that the
    /// next click will place, rendered at the size it would appear on screen
    /// at the current display zoom.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard currentTool == .marker else { return }
        addCursorRect(bounds, cursor: markerPreviewCursor())
    }

    /// Canvas-units-to-screen-points scale: the live scroll magnification
    /// (baseScale * userZoomFactor). Falls back to 1 outside a scroll view.
    private var canvasToScreenScale: CGFloat {
        let magnification = enclosingScrollView?.magnification ?? 1
        return (magnification.isFinite && magnification > 0) ? magnification : 1
    }

    /// Screen-point size the cursor preview must occupy so it exactly matches
    /// the marker a click would place: the placed marker's canvas bounds
    /// (capsule + outline bleed) transformed by the live magnification.
    /// Internal for tests.
    func markerPreviewScreenSize() -> NSSize {
        let probe = EditorDrawing.MarkerItem(number: nextMarkerNumber ?? EditorDrawing.MarkerItem.maxNumber,
                                             center: .zero,
                                             color: currentColor,
                                             diameter: defaultMarkerDiameter)
        let canvasBounds = EditorImageRenderer.markerBounds(for: probe)
        let scale = canvasToScreenScale
        return NSSize(width: canvasBounds.width * scale, height: canvasBounds.height * scale)
    }

    /// Everything the rendered marker cursor depends on.
    private struct MarkerCursorKey: Equatable {
        let number: Int
        let color: NSColor
        let diameter: CGFloat
        let magnification: CGFloat
        let backing: CGFloat
    }

    /// Last rendered marker cursor. Cursor rects are reset on every scroll and
    /// zoom step, so reuse the bitmap while its inputs are unchanged.
    private var markerCursorCache: (key: MarkerCursorKey, cursor: NSCursor)?

    /// Internal for tests.
    func markerPreviewCursor() -> NSCursor {
        let screenSize = markerPreviewScreenSize()
        guard screenSize.width >= 1, screenSize.height >= 1 else { return .crosshair }

        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = MarkerCursorKey(number: nextMarkerNumber ?? EditorDrawing.MarkerItem.maxNumber,
                                  color: currentColor,
                                  diameter: defaultMarkerDiameter,
                                  magnification: canvasToScreenScale,
                                  backing: backing)
        if let cached = markerCursorCache, cached.key == key {
            return cached.cursor
        }

        let cursor = renderMarkerCursor(key: key, screenSize: screenSize)
        markerCursorCache = (key, cursor)
        return cursor
    }

    private func renderMarkerCursor(key: MarkerCursorKey, screenSize: NSSize) -> NSCursor {
        var badge = EditorDrawing.MarkerItem(number: key.number,
                                               center: .zero,
                                               color: key.color,
                                               diameter: key.diameter)
        let canvasBounds = EditorImageRenderer.markerBounds(for: badge)
        badge.center = NSPoint(x: canvasBounds.width / 2, y: canvasBounds.height / 2)

        // Render the exact placed-marker geometry, scaled by the live
        // magnification, into a bitmap at the display's backing factor so the
        // cursor is Retina-sharp and the outline/width ratios are identical.
        let pixelW = max(1, Int((screenSize.width * key.backing).rounded()))
        let pixelH = max(1, Int((screenSize.height * key.backing).rounded()))
        let image = NSImage(size: screenSize)
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: pixelW,
                                      pixelsHigh: pixelH,
                                      bitsPerSample: 8,
                                      samplesPerPixel: 4,
                                      hasAlpha: true,
                                      isPlanar: false,
                                      colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0,
                                      bitsPerPixel: 0),
           let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) {
            image.addRepresentation(rep)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            graphicsContext.cgContext.scaleBy(x: key.backing * canvasToScreenScale,
                                              y: key.backing * canvasToScreenScale)
            EditorImageRenderer.drawMarker(badge)
            NSGraphicsContext.restoreGraphicsState()
        }
        let cursor = NSCursor(image: image,
                              hotSpot: NSPoint(x: screenSize.width / 2, y: screenSize.height / 2))
        return cursor
    }

    private func invalidateMarkerCursorPreview() {
        window?.invalidateCursorRects(for: self)
        onMarkerCursorInvalidation?()
    }

    /// Re-render the preview whenever the live magnification can change: zoom
    /// controls, auto-fit, and trackpad pinch all go through the scroll view's
    /// magnification, which changes the clip view's bounds. Scrolling also
    /// fires this notification; the extra invalidation is harmless.
    private var magnificationObserver: NSObjectProtocol?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let magnificationObserver {
            NotificationCenter.default.removeObserver(magnificationObserver)
            self.magnificationObserver = nil
        }
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        magnificationObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: nil) { [weak self] _ in
                self?.invalidateMarkerCursorPreview()
            }
    }

    private var backingObserver: NSObjectProtocol?

    deinit {
        if let magnificationObserver {
            NotificationCenter.default.removeObserver(magnificationObserver)
        }
        if let backingObserver {
            NotificationCenter.default.removeObserver(backingObserver)
        }
    }

    private func interpretFinalAction(from event: NSEvent, flags: NSEvent.ModifierFlags) -> ScreenshotFinalAction? {
        switch event.keyCode {
        case 36, 76: // Return / Enter
            if flags.contains(.command) {
                return .copyAndSave
            } else {
                return .saveOnly
            }
        case 51: // Delete / Backspace
            if flags.contains(.command) {
                return .copyAndDelete
            }
        case 53: // Escape
            return escapeFinalAction
        default:
            break
        }

        return nil
    }

    // Use hardware key codes so 1-6 selection works regardless of the active keyboard layout.
    private static let colorPickerKeyCodeToColorIndex: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 0,
        UInt16(kVK_ANSI_2): 1,
        UInt16(kVK_ANSI_3): 2,
        UInt16(kVK_ANSI_4): 3,
        UInt16(kVK_ANSI_5): 4,
        UInt16(kVK_ANSI_6): 5,
        UInt16(kVK_ANSI_Keypad1): 0,
        UInt16(kVK_ANSI_Keypad2): 1,
        UInt16(kVK_ANSI_Keypad3): 2,
        UInt16(kVK_ANSI_Keypad4): 3,
        UInt16(kVK_ANSI_Keypad5): 4,
        UInt16(kVK_ANSI_Keypad6): 5
    ]

    private static let colorPickerToggleKeyCodes: Set<UInt16> = [
        UInt16(kVK_ANSI_K)
    ]

    private static let toolKeyCodeToTool: [UInt16: EditorTool] = [
        UInt16(kVK_ANSI_W): .pen,
        UInt16(kVK_ANSI_D): .line,
        UInt16(kVK_ANSI_A): .arrow,
        UInt16(kVK_ANSI_R): .rectangle,
        UInt16(kVK_ANSI_E): .ellipse,
        UInt16(kVK_ANSI_T): .text,
        UInt16(kVK_ANSI_F): .marker,
        UInt16(kVK_ANSI_S): .selection
    ]
}

private final class EditorInlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDidChange: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76: // Return / Enter
            if flags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onCommit?()
            }
        case 53: // Escape
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onDidChange?()
    }
}

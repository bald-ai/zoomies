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

    enum KeyCommand {
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
    var currentColor: NSColor = .systemRed
    var isColorPickerOpen: Bool = false
    private let escapeFinalAction: ScreenshotFinalAction

    // MARK: - Internal model

    private var items: [EditorDrawing.Item] = []
    private var undoStack: [[EditorDrawing.Item]] = []
    private var redoStack: [[EditorDrawing.Item]] = []
    private let maxUndoLevels = 30
    private let annotationStrokeWidth: CGFloat = 4.0
    private var baseImageOrigin: NSPoint = .zero

    // In-progress drawing state
    private var currentPoints: [NSPoint] = [] // for pen
    private var dragStartPoint: NSPoint?
    private var dragCurrentPoint: NSPoint?

    // Text editing/dragging
    private var editingTextIndex: Int?
    private var textEditor: EditorInlineTextView?
    private var draggingTextIndex: Int?
    private var textDragOffset: NSPoint = .zero
    private var didPushUndoForTextDrag = false
    private var shouldPushUndoOnTextEnd = false
    private var selectedTextIndex: Int?
    private var editingOriginalText: String?
    private var editingWasNewItem = false
    private var isCommittingText = false
    private var isCancellingText = false
    // Use the editor's initial zoom so newly created text has a stable on-screen size
    // at open (100% vs 200% default start).
    private var textCreationZoomFactor: CGFloat = 1.0

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
        currentTool = tool
        if tool != .text {
            selectedTextIndex = nil
            draggingTextIndex = nil
            didPushUndoForTextDrag = false
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
        needsDisplay = true
    }

    func setColor(_ color: NSColor) {
        currentColor = color
    }

    func setInitialTextZoomFactor(_ zoomFactor: CGFloat) {
        guard zoomFactor.isFinite, zoomFactor > 0 else { return }
        textCreationZoomFactor = zoomFactor
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
        clearSelectionState()
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
        clearSelectionState()
        endTextEditingIfNeeded()
        baseImageOrigin = NSPoint(x: EditorDrawing.canvasEdgeInset, y: EditorDrawing.canvasEdgeInset)
        setFrameSize(minimumCanvasSize)
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
        guard let basePNG = ImageEncoding.pngData(from: baseImage) else { return nil }
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

        if baseImageBounds.intersects(dirtyRect) {
            drawBaseImageEdgeSeparation(in: baseImageBounds)
            baseImage.draw(in: baseImageBounds, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        }

        for item in items {
            guard let bounds = EditorImageRenderer.bounds(for: item) else { continue }
            if bounds.intersects(dirtyRect) {
                EditorImageRenderer.draw(item: item)
            }
        }

        if let selectionRect, selectionRect.intersects(dirtyRect) {
            drawSelectionOutline(selectionRect)
        }

        if let selectedImageIndex,
           case let .image(_, rect) = items[selectedImageIndex],
           rect.intersects(dirtyRect) {
            drawImageSelectionOutline(rect)
        }

        if let selectedItemIndex,
           selectedItemIndex < items.count,
           let rect = EditorImageRenderer.bounds(for: items[selectedItemIndex])?.insetBy(dx: -3, dy: -3),
           rect.intersects(dirtyRect) {
            drawItemSelectionOutline(rect)
        }

        if let index = selectedTextIndex, textEditor == nil {
            if case let .text(textItem) = items[index] {
                let rect = EditorImageRenderer.textBounds(for: textItem).insetBy(dx: -2, dy: -2)
                if rect.intersects(dirtyRect) {
                    let path = NSBezierPath(rect: rect)
                    let dash: [CGFloat] = [4, 3]
                    path.setLineDash(dash, count: dash.count, phase: 0)
                    NSColor.white.withAlphaComponent(0.8).setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            }
        }

        // In-progress shapes
        if let start = dragStartPoint, let current = dragCurrentPoint {
            let shiftHeld = NSEvent.modifierFlags.contains(.shift)
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
            case .text:
                break
            case .selection:
                break
            }
        } else if let start = selectionDragStart, let current = selectionDragCurrent {
            let rect = normalizedRect(from: start, to: current)
            drawSelectionOutline(rect)
        } else if currentTool == .pen && !currentPoints.isEmpty {
            EditorImageRenderer.drawPen(points: currentPoints, color: currentColor, lineWidth: annotationStrokeWidth, isPreview: true)
        }
    }

    /// Keep screenshot edges visible against both light and dark native backgrounds.
    private func drawBaseImageEdgeSeparation(in rect: NSRect) {
        guard rect.width >= 1, rect.height >= 1 else { return }
        let borderRect = rect.insetBy(dx: -0.5, dy: -0.5)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
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

    private var defaultTextFontSize: CGFloat {
        let targetOnScreenSize: CGFloat = 38.4
        let normalizedZoom = max(0.01, textCreationZoomFactor)
        return round(targetOnScreenSize / normalizedZoom)
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

        if let point = dragStartPoint {
            dragStartPoint = EditorImageRenderer.shiftedPoint(point, byX: dx, byY: dy)
        }
        if let point = dragCurrentPoint {
            dragCurrentPoint = EditorImageRenderer.shiftedPoint(point, byX: dx, byY: dy)
        }
        currentPoints = currentPoints.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) }

        if let point = selectionDragStart {
            selectionDragStart = EditorImageRenderer.shiftedPoint(point, byX: dx, byY: dy)
        }
        if let point = selectionDragCurrent {
            selectionDragCurrent = EditorImageRenderer.shiftedPoint(point, byX: dx, byY: dy)
        }
        if let rect = selectionRect {
            selectionRect = EditorImageRenderer.shiftedRect(rect, byX: dx, byY: dy)
        }

        if let rect = copiedSelectionRect {
            copiedSelectionRect = EditorImageRenderer.shiftedRect(rect, byX: dx, byY: dy)
        }
        if let point = lastMousePoint {
            lastMousePoint = EditorImageRenderer.shiftedPoint(point, byX: dx, byY: dy)
        }

        if let editor = textEditor {
            editor.frame = EditorImageRenderer.shiftedRect(editor.frame, byX: dx, byY: dy)
        }
    }

    private func moveItem(at index: Int, byX dx: CGFloat, byY dy: CGFloat) {
        guard index < items.count, dx != 0 || dy != 0 else { return }

        switch items[index] {
        case .pen(let points, let color, let lineWidth):
            items[index] = .pen(points: points.map { EditorImageRenderer.shiftedPoint($0, byX: dx, byY: dy) },
                                color: color,
                                lineWidth: lineWidth)
        case .arrow(let start, let end, let color, let lineWidth):
            items[index] = .arrow(start: EditorImageRenderer.shiftedPoint(start, byX: dx, byY: dy),
                                  end: EditorImageRenderer.shiftedPoint(end, byX: dx, byY: dy),
                                  color: color,
                                  lineWidth: lineWidth)
        case .rect(let rect, let color, let lineWidth):
            items[index] = .rect(rect: EditorImageRenderer.shiftedRect(rect, byX: dx, byY: dy),
                                 color: color,
                                 lineWidth: lineWidth)
        case .ellipse(let rect, let color, let lineWidth):
            items[index] = .ellipse(rect: EditorImageRenderer.shiftedRect(rect, byX: dx, byY: dy),
                                    color: color,
                                    lineWidth: lineWidth)
        case .text(var textItem):
            textItem.origin = EditorImageRenderer.shiftedPoint(textItem.origin, byX: dx, byY: dy)
            items[index] = .text(textItem)
        case .image(let image, let rect):
            items[index] = .image(image: image, rect: EditorImageRenderer.shiftedRect(rect, byX: dx, byY: dy))
        case .erase(let rect):
            items[index] = .erase(rect: EditorImageRenderer.shiftedRect(rect, byX: dx, byY: dy))
        }
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

        if currentTool == .selection {
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

        if currentTool == .text {
            // Finishing a new, empty text item can remove it from `items`.
            // Commit before hit testing so the index we pass to the editor is
            // always derived from the current collection.
            endTextEditingIfNeeded()
            let clickCount = event.clickCount

            if let (index, rect) = hitTestText(at: point) {
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

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = point

        if currentTool == .selection {
            if let index = draggingImageIndex {
                if !didPushUndoForImageDrag {
                    pushUndoSnapshot()
                    didPushUndoForImageDrag = true
                }
                if case let .image(image, oldRect) = items[index] {
                    let newOrigin = NSPoint(x: point.x - imageDragOffset.x, y: point.y - imageDragOffset.y)
                    let newRect = NSRect(origin: newOrigin, size: oldRect.size)
                    items[index] = .image(image: image, rect: newRect)
                    needsDisplay = true
                }
                return
            }
            if let index = draggingItemIndex, index < items.count, let lastPoint = lastItemDragPoint {
                if !didPushUndoForItemDrag {
                    pushUndoSnapshot()
                    didPushUndoForItemDrag = true
                }
                moveItem(at: index, byX: point.x - lastPoint.x, byY: point.y - lastPoint.y)
                lastItemDragPoint = point
                needsDisplay = true
                return
            }
            guard selectionDragStart != nil else { return }
            selectionDragCurrent = point
            needsDisplay = true
            return
        }

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
                needsDisplay = true
            }
            return
        }

        guard dragStartPoint != nil else { return }

        dragCurrentPoint = point

        if currentTool == .pen {
            currentPoints.append(point)
        }

        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if dragStartPoint != nil && (currentTool == .rectangle || currentTool == .ellipse) {
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastMousePoint = point

        if currentTool == .selection {
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

        if draggingTextIndex != nil {
            draggingTextIndex = nil
            didPushUndoForTextDrag = false
            updateCanvasSizeIfNeeded()
            needsDisplay = true
            return
        }
        guard let start = dragStartPoint else { return }
        dragCurrentPoint = point

        switch currentTool {
        case .pen:
            if currentPoints.count > 1 {
                pushUndoSnapshot()
                items.append(.pen(points: currentPoints, color: currentColor, lineWidth: annotationStrokeWidth))
                updateCanvasSizeIfNeeded()
            }
        case .line:
            if EditorImageRenderer.distance(from: start, to: point) >= 2 {
                pushUndoSnapshot()
                // A two-point stroke is a straight line and already supports
                // selection, moving, clipboard operations, and saved edit state.
                items.append(.pen(points: [start, point], color: currentColor, lineWidth: annotationStrokeWidth))
                updateCanvasSizeIfNeeded()
            }
        case .arrow:
            if EditorImageRenderer.distance(from: start, to: point) >= 2 {
                pushUndoSnapshot()
                items.append(.arrow(start: start, end: point, color: currentColor, lineWidth: annotationStrokeWidth))
                updateCanvasSizeIfNeeded()
            }
        case .rectangle:
            let shiftHeld = event.modifierFlags.contains(.shift)
            let rect = normalizedRect(from: start, to: point, constrain: shiftHeld)
            if rect.width >= 2, rect.height >= 2 {
                pushUndoSnapshot()
                items.append(.rect(rect: rect, color: currentColor, lineWidth: annotationStrokeWidth))
                updateCanvasSizeIfNeeded()
            }
        case .ellipse:
            let shiftHeld = event.modifierFlags.contains(.shift)
            let rect = normalizedRect(from: start, to: point, constrain: shiftHeld)
            if rect.width >= 2, rect.height >= 2 {
                pushUndoSnapshot()
                items.append(.ellipse(rect: rect, color: currentColor, lineWidth: annotationStrokeWidth))
                updateCanvasSizeIfNeeded()
            }
        case .text:
            break
        case .selection:
            break
        }

        dragStartPoint = nil
        dragCurrentPoint = nil
        currentPoints.removeAll()
        needsDisplay = true
    }

    // MARK: - Text editing helpers

    private func hitTestText(at point: NSPoint) -> (Int, NSRect)? {
        for (index, item) in items.enumerated() {
            guard case let .text(textItem) = item else { continue }
            let rect = EditorImageRenderer.textBounds(for: textItem).insetBy(dx: -4, dy: -4)
            if rect.contains(point) {
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
        case .image(_, let rect):
            return rect.insetBy(dx: -3, dy: -3).contains(point)
        case .erase(let rect):
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

    private func beginEditingText(at index: Int, pushUndoOnEnd: Bool, isNewItem: Bool) {
        endTextEditingIfNeeded()
        guard items.indices.contains(index),
              case let .text(item) = items[index] else {
            return
        }

        let rect = EditorImageRenderer.textBounds(for: item)
        let editor = EditorInlineTextView(frame: rect)
        editor.string = item.text
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.drawsBackground = false
        editor.textColor = item.color
        editor.font = NSFont.systemFont(ofSize: item.fontSize, weight: .regular)
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
        editor.onDidChange = { [weak self] in
            self?.resizeTextEditorToFit()
        }
        editor.wantsLayer = true
        editor.layer?.borderWidth = 1
        editor.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
        editor.layer?.cornerRadius = 4

        addSubview(editor)
        window?.makeFirstResponder(editor)

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

        let updatedText = trimTrailingWhitespace(editor.string.replacingOccurrences(of: "\r", with: ""))
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

        removeTextEditor()
        updateCanvasSizeIfNeeded()
        needsDisplay = true
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
        needsDisplay = true
        return true
    }

    // MARK: - Keyboard & gestures

    override func keyDown(with event: NSEvent) {
        if textEditor != nil {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if isColorPickerOpen {
            if let index = Self.colorPickerKeyCodeToColorIndex[event.keyCode] {
                onKeyCommand?(.selectColor(index: index))
                onKeyCommand?(.colorPickerClose)
                return
            }
            switch event.keyCode {
            case 123: // left arrow
                onKeyCommand?(.colorPickerMove(direction: -1))
                return
            case 124: // right arrow
                onKeyCommand?(.colorPickerMove(direction: 1))
                return
            case 36, 76: // enter
                onKeyCommand?(.colorPickerSelect)
                return
            case 53: // escape
                onKeyCommand?(.colorPickerClose)
                return
            default:
                break
            }
        }

        if !flags.contains(.command)
            && !flags.contains(.control)
            && !flags.contains(.shift)
            && Self.colorPickerToggleKeyCodes.contains(event.keyCode) {
            if isColorPickerOpen { return }
            onKeyCommand?(.toggleColorPicker)
            return
        }

        if !flags.contains(.command)
            && !flags.contains(.control)
            && !flags.contains(.option)
            && !flags.contains(.shift),
           let tool = Self.toolKeyCodeToTool[event.keyCode] {
            onKeyCommand?(.selectTool(tool))
            return
        }

        if flags.contains(.option) && event.keyCode == 51 {
            onKeyCommand?(.clear)
            return
        }

        if flags.contains(.command), let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "=", "+":
                onKeyCommand?(.zoomIn)
                return
            case "-":
                onKeyCommand?(.zoomOut)
                return
            case "0":
                onKeyCommand?(.zoomReset)
                return
            case "z":
                // FloatingInputPanel models the same distinction for text views:
                // Cmd+Z undoes, Cmd+Shift+Z redoes.
                if flags.contains(.shift) {
                    onKeyCommand?(.redo)
                } else {
                    onKeyCommand?(.undo)
                }
                return
            case "c":
                onKeyCommand?(.copyToClipboard)
                return
            case "x":
                onKeyCommand?(.cutSelectionToClipboard)
                return
            case "v":
                onKeyCommand?(.pasteSelectionInCanvas)
                return
            default:
                break
            }
        }

        if event.keyCode == 53, clearSelectionIfNeeded() {
            return
        }

        if let final = interpretFinalAction(from: event, flags: flags) {
            onKeyCommand?(.finalAction(final))
            return
        }

        if event.keyCode == 48 && flags.contains(.shift) { // Shift+Tab
            onKeyCommand?(.backToNote)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            if deleteSelectedImageIfNeeded() { return }
            if deleteSelectedItemIfNeeded() { return }
            if deleteSelectedTextIfNeeded() { return }
        }

        super.keyDown(with: event)
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

        if chars == "z" {
            if flags == [.command] {
                onKeyCommand?(.undo)
                return true
            }
            if flags == [.command, .shift] {
                onKeyCommand?(.redo)
                return true
            }
        }

        guard flags == [.command] else {
            return super.performKeyEquivalent(with: event)
        }

        switch chars {
        case "c":
            onKeyCommand?(.copyToClipboard)
            return true
        case "x":
            onKeyCommand?(.cutSelectionToClipboard)
            return true
        case "v":
            onKeyCommand?(.pasteSelectionInCanvas)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
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
        UInt16(kVK_ANSI_K),
        UInt16(kVK_ANSI_Q)
    ]

    private static let toolKeyCodeToTool: [UInt16: EditorTool] = [
        UInt16(kVK_ANSI_W): .pen,
        UInt16(kVK_ANSI_D): .line,
        UInt16(kVK_ANSI_A): .arrow,
        UInt16(kVK_ANSI_R): .rectangle,
        UInt16(kVK_ANSI_E): .ellipse,
        UInt16(kVK_ANSI_T): .text,
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

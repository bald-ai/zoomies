import AppKit

protocol SelectionOverlayDelegate: AnyObject {
    func selectionOverlay(_ overlay: SelectionOverlay,
                          didFinishWith rectInScreenCoordinates: CGRect?,
                          onScreen screen: NSScreen)
}

/// Full-screen transparent overlay for drag-to-select area capture.
final class SelectionOverlay: NSObject {
    weak var delegate: SelectionOverlayDelegate?

    private var screen: NSScreen?
    private var window: SelectionOverlayWindow?
    private(set) var selectionView: SelectionOverlayView?
    private var screenParametersObserver: NSObjectProtocol?
    private let screenProvider: () -> NSScreen?
    private let presenter: (SelectionOverlayWindow, SelectionOverlayView) -> Void

    private(set) var isActive = false

    init(screenProvider: @escaping () -> NSScreen? = SelectionOverlay.screenUnderMouse,
         presenter: @escaping (SelectionOverlayWindow, SelectionOverlayView) -> Void = SelectionOverlay.present) {
        self.screenProvider = screenProvider
        self.presenter = presenter
        super.init()

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateCachedOverlay()
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func beginSelection() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.beginSelection()
            }
            return
        }

        guard !isActive else {
            return
        }

        guard let targetScreen = screenProvider() else {
            return
        }

        let overlayWindow = buildOverlayIfNeeded(for: targetScreen)
        guard let selectionView else {
            return
        }

        screen = targetScreen
        overlayWindow.setFrame(targetScreen.frame, display: false)
        selectionView.frame = CGRect(origin: .zero, size: targetScreen.frame.size)
        selectionView.prepareForSelection(backingScaleFactor: targetScreen.backingScaleFactor)
        presenter(overlayWindow, selectionView)
        isActive = true
    }

    private static func screenUnderMouse() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func present(_ window: SelectionOverlayWindow, _ view: SelectionOverlayView) {
        view.pushCursorIfNeeded()
        window.orderFront(nil)
        window.makeKey()
        window.makeFirstResponder(view)
    }

    func cancelSelection() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.cancelSelection()
            }
            return
        }

        finish(with: nil)
    }

    private func buildOverlayIfNeeded(for screen: NSScreen) -> SelectionOverlayWindow {
        if let window {
            return window
        }

        let overlayWindow = SelectionOverlayWindow.makeOverlayWindow(screen: screen)
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.level = .screenSaver
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.hasShadow = false
        overlayWindow.acceptsMouseMovedEvents = true
        // Keep selection available when the user switches desktop or full-screen Spaces.
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = SelectionOverlayView(frame: .zero)
        overlayView.autoresizingMask = [.width, .height]
        overlayView.onComplete = { [weak self] rectInView in
            self?.finish(with: rectInView)
        }

        overlayWindow.contentView = overlayView
        window = overlayWindow
        selectionView = overlayView
        return overlayWindow
    }

    private func finish(with rectInView: CGRect?) {
        guard let currentScreen = screen else {
            tearDown()
            return
        }

        var rectInScreenCoordinates: CGRect?
        if let rectInView, let window {
            let rectInWindow = selectionView?.convert(rectInView, to: nil) ?? rectInView
            let selectionRect = window.convertToScreen(rectInWindow)
            let minimumSizePoints: CGFloat = 5
            if selectionRect.width >= minimumSizePoints && selectionRect.height >= minimumSizePoints {
                rectInScreenCoordinates = selectionRect
            }
        }

        tearDown()
        delegate?.selectionOverlay(self, didFinishWith: rectInScreenCoordinates, onScreen: currentScreen)
    }

    private func tearDown() {
        selectionView?.releaseCursor()
        window?.orderOut(nil)
        selectionView?.resetSelectionState()
        screen = nil
        isActive = false
    }

    private func invalidateCachedOverlay() {
        selectionView?.releaseCursor()
        window?.orderOut(nil)
        screen = nil
        isActive = false
        window = nil
        selectionView = nil
    }
}

final class SelectionOverlayWindow: NSPanel {
    static func makeOverlayWindow(screen: NSScreen?) -> SelectionOverlayWindow {
        let window = SelectionOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        return window
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionOverlayView: NSView {
    var onComplete: ((CGRect?) -> Void)?
    var backingScaleFactor: CGFloat = 1

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var cursorPushed = false
    private var hasDrawn = false

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func prepareForSelection(backingScaleFactor: CGFloat) {
        self.backingScaleFactor = backingScaleFactor
        resetSelectionState()
        needsDisplay = true
    }

    func resetSelectionState() {
        startPoint = nil
        currentPoint = nil
        hasDrawn = false
    }

    func pushCursorIfNeeded() {
        guard !cursorPushed else {
            return
        }

        NSCursor.crosshair.push()
        cursorPushed = true
        window?.invalidateCursorRects(for: self)
    }

    func releaseCursor() {
        guard cursorPushed else {
            return
        }

        NSCursor.pop()
        cursorPushed = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        hasDrawn = true

        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        if let rect = currentSelectionRect {
            NSColor.clear.setFill()
            rect.fill(using: .clear)

            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()

        } else {
            drawInstructions()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else {
            return
        }

        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        onComplete?(currentSelectionRect)
    }

    override func rightMouseDown(with event: NSEvent) {
        onComplete?(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onComplete?(nil)
        case 36:
            onComplete?(currentSelectionRect)
        default:
            super.keyDown(with: event)
        }
    }

    private var currentSelectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        let minX = min(startPoint.x, currentPoint.x)
        let minY = min(startPoint.y, currentPoint.y)
        let width = abs(currentPoint.x - startPoint.x)
        let height = abs(currentPoint.y - startPoint.y)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private func drawInstructions() {
        let text = "Drag to select area, Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor.white
        ]

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        var fullAttributes = attributes
        fullAttributes[.shadow] = shadow

        let size = (text as NSString).size(withAttributes: fullAttributes)
        let point = CGPoint(x: bounds.midX - size.width / 2,
                            y: bounds.midY - size.height / 2)
        (text as NSString).draw(at: point, withAttributes: fullAttributes)
    }
}

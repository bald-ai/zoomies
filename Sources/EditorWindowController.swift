import AppKit
import Carbon

/// Routes command-key equivalents before AppKit's window/menu handling can
/// consume them. The canvas remains the first responder during normal editing;
/// inline text editors intentionally keep their standard text undo manager.
final class EditorWindow: NSWindow {
    /// Consulted first; the marker note popover uses it to keep its shortcuts.
    var keyEquivalentInterceptor: ((NSEvent) -> Bool)?
    /// Sees left-mouse events before AppKit routes them, so drags that start
    /// in the empty chrome can reach the canvas. Returns true when consumed.
    var mouseInterceptor: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            if mouseInterceptor?(event) == true { return }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentInterceptor?(event) == true { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased()

        if chars == "z", let canvas = firstResponder as? EditorCanvasView {
            if flags == [.command] {
                canvas.undo()
                return true
            }
            if flags == [.command, .shift] {
                canvas.redo()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }
}

/// Window controller for the screenshot editor.
///
/// The editor provides basic annotation tools (pen, arrow, rectangle,
/// ellipse, text, numbered markers), a small color palette with keyboard access, an undo
/// stack, and zoom controls. When the user finishes (save, copy+save,
/// copy+delete, delete), the controller calls `onComplete` with the
/// final image and desired action. The caller (ScreenshotWorkflowController)
/// is responsible for writing the image to disk, clipboard operations,
/// and backup/delete semantics.
final class EditorWindowController: NSWindowController {
    /// Called when the user finishes editing.
    /// - Parameters:
    ///   - image: The final composited image, or `nil` for delete-only.
    ///   - action: The requested final action.
    var onComplete: ((NSImage?, ScreenshotFinalAction, EditorCanvasState?) -> Void)?
    var onBackToNote: (() -> Void)?
    /// Double-clicking a marker edits that marker's line in the note: the host
    /// supplies its existing text and remaining character room, then applies the edit.
    var markerNoteContext: ((Int) -> (text: String?, capacity: Int))?
    var onMarkerNote: ((Int, String) -> Void)?
    /// Current marker numbers whenever markers are added or removed.
    var onMarkerNumbersChanged: ((Set<Int>) -> Void)?
    /// Confirmation callbacks for Esc/X paths. Cancelling keeps drawings intact.
    /// The setting gates both callbacks; nil proceeds without a prompt.
    var onConfirmDelete: (() -> Bool)?
    var onConfirmClose: (() -> Bool)?

    private let canvasView: EditorCanvasView
    private let scrollView = EditorScrollView()
    private let chromeInkView = EditorChromeInkView()
    private var scrollBoundsObserver: NSObjectProtocol?
    private let clipboardService: ClipboardService
    private let settingsStore: SettingsStore
    private var notePreviewRaw: String?
    private weak var rootStackView: NSStackView?
    private var markerNotePopover: NSPopover?
    private let targetScreen: NSScreen?
    private var notePreviewContainer: EditorNotePreviewBar?
    // Toolbar Cancel (X) and the red window close button mirror Escape:
    // - For editor sessions that own the temp file: delete on cancel.
    // - For Finder-selected originals: close without deleting.
    private let escapeFinalAction: ScreenshotFinalAction

    private var toolButtons: [EditorTool: NSButton] = [:]
    private var selectedColorIndex = 0

    private let colorIndicatorButton = NSButton(frame: .zero)
    private let zoomLabel = NSTextField(labelWithString: "100%")

    private var paletteIDs: [String]
    private var colors: [NSColor]
    private var paletteObserver: NSObjectProtocol?
    private var layoutObservation: KeyboardLayoutObservation?

    private func refreshPhysicalShortcutLabels() {
        let tools: [(EditorTool, Int, String, String)] = [
            (.pen, kVK_ANSI_W, "Pen", ""), (.line, kVK_ANSI_D, "Line", ""),
            (.arrow, kVK_ANSI_A, "Arrow", ""), (.rectangle, kVK_ANSI_R, "Rectangle", ", Hold ⇧: Square"),
            (.ellipse, kVK_ANSI_E, "Ellipse", ", Hold ⇧: Circle"), (.text, kVK_ANSI_T, "Text", ""),
            (.marker, kVK_ANSI_F, "Numbered marker", ""), (.selection, kVK_ANSI_S, "Selection", "")
        ]
        for (tool, code, title, suffix) in tools {
            guard let button = toolButtons[tool] else { continue }
            let key = HotKeyService.describeShortcut(keyCode: UInt32(code), carbonFlags: 0)
            button.toolTip = "\(title) (\(key)\(suffix))"
            if let index = shortcutHints.firstIndex(where: { $0.view === button }) {
                shortcutHints[index] = .init(view: button, key: key, label: shortcutHints[index].label)
            }
        }
        let next = HotKeyService.describeShortcut(keyCode: UInt32(kVK_ANSI_Q), carbonFlags: 0)
        colorIndicatorButton.toolTip = "Next color (\(next))"
        if let index = shortcutHints.firstIndex(where: { $0.view === colorIndicatorButton }) {
            shortcutHints[index] = .init(view: colorIndicatorButton, key: next, label: "Next color")
        }
        shortcutOverlay?.refreshLabels()
    }

    // Match mac_screenshot behavior:
    // - The window opens sized to the image (with caps).
    // - The image may be scaled down to fit (baseScale <= 1).
    // - Zoom controls are relative to that baseScale (start at 100%).
    private var userZoomFactor: CGFloat = 1.0
    private var baseScale: CGFloat = 1.0
    private var defaultUserZoomFactor: CGFloat = 1.0
    // Effective zoom the editor opened at; refitting never zooms past it.
    private var openingEffectiveZoom: CGFloat = 1.0
    // True until the user zooms by hand; while true, note changes refit the image.
    private var followsAutomaticFit = true
    // Height the window gained for the note bar, so removing the note gives
    // back only what the note added.
    private var windowHeightAddedForNote: CGFloat = 0
    // A press in the empty chrome is being forwarded to the canvas until mouse up.
    private var forwardsChromeDragToCanvas = false
    // Total padding amount around the image (not per-side).
    private var totalPadding: CGFloat = 0.0

    // Auto-zoom small captures so they fill most of the editor canvas.
    private let autoZoomFillRatio: CGFloat = 0.90
    private let maxAutoUserZoom: CGFloat = 2.0

    // User zoom bounds (multiplier relative to fit).
    private let minUserZoom: CGFloat = 0.2
    private let maxUserZoom: CGFloat = 6.0

    // Absolute bounds enforced by NSScrollView.
    private let minEffectiveZoom: CGFloat = 0.02
    private let maxEffectiveZoom: CGFloat = 8.0

    private var didSendCompletion = false
    private var keyDownMonitor: Any?
    private(set) var shortcutOverlay: EditorShortcutOverlayController?
    private var shortcutHints: [EditorShortcutHint] = []

    private weak var toolbarBackgroundView: NSView?
    private var toolbarMinimumHeight: CGFloat = 72.0

    // MARK: - Init

    convenience init?(imageURL: URL,
                      settingsStore: SettingsStore,
                      notePreview: String? = nil,
                      targetScreen: NSScreen? = nil,
                      escapeKeyDeletesFile: Bool = true) {
        guard let image = NSImage(contentsOf: imageURL) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unable to open image"
            alert.informativeText = "The captured image could not be loaded for editing."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return nil
        }
        self.init(image: image,
                  settingsStore: settingsStore,
                  notePreview: notePreview,
                  targetScreen: targetScreen,
                  escapeKeyDeletesFile: escapeKeyDeletesFile)
    }

    init(image: NSImage,
         settingsStore: SettingsStore,
         notePreview: String? = nil,
         targetScreen: NSScreen? = nil,
         escapeKeyDeletesFile: Bool = true,
         initialState: EditorCanvasState? = nil,
         clipboardService: ClipboardService = ClipboardService()) {
        let escapeFinal: ScreenshotFinalAction = escapeKeyDeletesFile ? .deleteOnly : .closeOnly
        // The canvas validates and restores editable state through EditorDrawing,
        // using the supplied image as the fallback when restoration is unavailable.
        self.canvasView = EditorCanvasView(
            image: image,
            escapeFinalAction: escapeFinal,
            initialState: initialState
        )
        self.clipboardService = clipboardService
        self.settingsStore = settingsStore
        self.paletteIDs = EditorPalette.normalized(settingsStore.settings.editorColorIDs)
        self.colors = EditorPalette.colors(for: paletteIDs).map(\.color)
        self.notePreviewRaw = notePreview
        self.targetScreen = targetScreen
        self.escapeFinalAction = escapeFinal

        // Provisional size. We'll resize to match the image (native-like) after building UI.
        let contentRect = NSRect(x: 0, y: 0, width: 720, height: 520)

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = EditorWindow(contentRect: contentRect,
                                  styleMask: style,
                                  backing: .buffered,
                                  defer: false)
        window.title = "Edit Screenshot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        // Size is dynamic; do not autosave window frame.
        window.contentMinSize = NSSize(width: 580, height: 250)
        window.backgroundColor = .clear
        AppTheme.apply(to: window)

        super.init(window: window)

        window.delegate = self
        window.mouseInterceptor = { [weak self, weak window] event in
            self?.handleChromeMouseEvent(event, isKeyWindow: window?.isKeyWindow == true) ?? false
        }
        configureContent()
        paletteObserver = NotificationCenter.default.addObserver(forName: SettingsStore.didChangeNotification, object: settingsStore, queue: .main) { [weak self] _ in self?.reloadPaletteIfNeeded() }
        shortcutOverlay = EditorShortcutOverlayController(window: window) { [weak self] in self?.shortcutHints ?? [] }

        refreshPhysicalShortcutLabels()
        layoutObservation = KeyboardLayoutObservation { [weak self] in
            self?.refreshPhysicalShortcutLabels()
        }

        // Now that UI exists, choose an initial window size based on the image and current screen.
        sizeWindowToImage()
        positionWindowOnTargetScreen()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let paletteObserver { NotificationCenter.default.removeObserver(paletteObserver) }
        if let scrollBoundsObserver { NotificationCenter.default.removeObserver(scrollBoundsObserver) }
        removeKeyDownMonitor()
    }

    func show() {
        guard let window = window else { return }
        installKeyDownMonitor()
        // Make the editor immediately key so keyboard shortcuts work without extra click.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(canvasView)
        updateScrollLockAndRecentering()
    }

    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handleMonitoredEvent(event, isKeyWindow: self.window?.isKeyWindow == true,
                                             isEditingText: self.window?.firstResponder is NSTextView)
        }
    }

    /// Event decision used by the local monitor; explicit context keeps hidden
    /// component fixtures independent of focus and the application's event loop.
    func handleMonitoredEvent(_ event: NSEvent, isKeyWindow: Bool, isEditingText: Bool) -> NSEvent? {
        guard isKeyWindow, markerNotePopover == nil else { return event }
        shortcutOverlay?.handle(event)
        guard event.type == .keyDown, !isEditingText else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.charactersIgnoringModifiers?.lowercased() == "z" else { return event }
        if flags == [.command] {
            canvasView.undo()
            return nil
        }
        if flags == [.command, .shift] {
            canvasView.redo()
            return nil
        }
        return event
    }

    private func removeKeyDownMonitor() {
        shortcutOverlay?.cancel()
        guard let keyDownMonitor else { return }
        NSEvent.removeMonitor(keyDownMonitor)
        self.keyDownMonitor = nil
    }

    func currentCompositeImage() -> NSImage {
        canvasView.compositeImage()
    }

    func currentEditableState() -> EditorCanvasState? {
        canvasView.editableState()
    }

    func dismissWithoutCompletion() {
        didSendCompletion = true
        close()
    }

    // MARK: - UI setup

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let surfaceView = MenuSurfaceMaterial.makeFillingView(frame: contentView.bounds)
        contentView.addSubview(surfaceView)

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 10
        rootStack.alignment = .centerX
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        // Behind the toolbar and canvas: shows strokes that leave the viewport.
        chromeInkView.frame = surfaceView.bounds
        chromeInkView.autoresizingMask = [.width, .height]
        chromeInkView.canvas = canvasView
        chromeInkView.excludedWindowRects = { [weak self] in
            guard let self else { return [] }
            // The viewport draws itself, and annotations on parts of the image
            // panned out of view stay hidden with the image.
            var rects = [self.scrollView.convert(self.scrollView.bounds, to: nil),
                         self.canvasView.convert(self.canvasView.baseImageBounds, to: nil)]
            if let noteBar = self.notePreviewContainer {
                rects.append(noteBar.convert(noteBar.bounds, to: nil))
            }
            return rects
        }
        surfaceView.addSubview(chromeInkView)
        surfaceView.addSubview(rootStack)
        rootStackView = rootStack

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: surfaceView.safeAreaLayoutGuide.topAnchor, constant: 8),
            rootStack.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor, constant: 12),
            rootStack.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor, constant: -12),
            rootStack.bottomAnchor.constraint(equalTo: surfaceView.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        let toolbarBackground = makeToolbarBackground()
        let toolbarStack = makeToolbarStack()
        toolbarBackground.addSubview(toolbarStack)
        toolbarBackgroundView = toolbarBackground

        NSLayoutConstraint.activate([
            toolbarStack.topAnchor.constraint(equalTo: toolbarBackground.topAnchor, constant: 6),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbarBackground.bottomAnchor, constant: -6),
            toolbarStack.leadingAnchor.constraint(equalTo: toolbarBackground.leadingAnchor, constant: 8),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbarBackground.trailingAnchor, constant: -8)
        ])

        // Use intrinsic toolbar height when sizing the editor window.
        toolbarMinimumHeight = max(72.0, toolbarStack.fittingSize.height + 12.0)

        rootStack.addArrangedSubview(toolbarBackground)

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        // Native screenshot/markup windows do not show scrollers; panning still works
        // with trackpad/mouse when zoomed.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minEffectiveZoom
        scrollView.maxMagnification = maxEffectiveZoom
        let centeringClipView = CenteringClipView()
        scrollView.contentView = centeringClipView
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = canvasView
        scrollView.magnification = 1.0
        scrollView.shouldAllowScroll = { [weak self] in
            return self?.isContentScrollable ?? true
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        // Allow the window to open small for small screenshots (native behavior).
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        // Note preview should feel like the burned-in bottom bar (but is UI-only).
        // Place it under the canvas so its position matches the final saved image.
        if let noteView = makeNotePreviewView() {
            notePreviewContainer = noteView
            rootStack.addArrangedSubview(noteView)
            noteView.translatesAutoresizingMaskIntoConstraints = false
            noteView.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        canvasView.onDisplayInvalidated = { [weak self] in
            self?.chromeInkView.needsDisplay = true
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            self?.chromeInkView.needsDisplay = true
        }

        canvasView.onKeyCommand = { [weak self] command in
            self?.handleKeyCommand(command)
        }
        canvasView.onMarkerNumbersChanged = { [weak self] numbers in
            self?.onMarkerNumbersChanged?(numbers)
        }
        canvasView.onMarkerNoteRequest = { [weak self] number, rect in
            self?.presentMarkerNotePopover(number: number, rect: rect)
        }

        selectTool(.pen)
        selectColor(index: 0)
    }

    /// Replaces the UI-only note bar after the workflow's note text changes.
    func updateNotePreview(_ text: String) {
        let previousNoteHeight = notePreviewStackHeight
        notePreviewRaw = text
        if let existing = notePreviewContainer, let displayText = notePreviewDisplayText {
            existing.text = displayText
        } else {
            notePreviewContainer?.removeFromSuperview()
            notePreviewContainer = nil
            if let rootStack = rootStackView, let noteView = makeNotePreviewView() {
                notePreviewContainer = noteView
                rootStack.addArrangedSubview(noteView)
                noteView.translatesAutoresizingMaskIntoConstraints = false
                noteView.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
            }
        }
        notePreviewContainer?.updateHeight(forWidth: rootStackView?.bounds.width ?? 0)
        preserveCanvasSize(afterNoteHeightChangeFrom: previousNoteHeight)
        refitImageIfFollowingFit()
    }

    /// Height the note bar takes from the root stack, including its spacing.
    private var notePreviewStackHeight: CGFloat {
        guard let noteView = notePreviewContainer else { return 0 }
        return noteView.frame.height + (rootStackView?.spacing ?? 0)
    }

    /// Resizes the window by the note bar's height change so the canvas keeps
    /// its size instead of shrinking under the image and becoming scrollable.
    private func preserveCanvasSize(afterNoteHeightChangeFrom previousHeight: CGFloat) {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        var delta = notePreviewStackHeight - previousHeight
        if delta < 0 {
            delta = max(delta, -windowHeightAddedForNote)
        }
        guard abs(delta) > 0.5 else { return }
        let previousWindowHeight = window.frame.height
        let minFrameHeight = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).height
        let frame = EditorWindowLayoutLogic.frameAdjustedForChromeChange(
            window.frame,
            heightDelta: delta,
            minHeight: minFrameHeight,
            visibleFrame: window.screen?.visibleFrame ?? layoutVisibleFrame
        )
        window.setFrame(frame, display: true)
        windowHeightAddedForNote = max(0, windowHeightAddedForNote + window.frame.height - previousWindowHeight)
        window.contentView?.layoutSubtreeIfNeeded()
        updateScrollLockAndRecentering()
    }

    /// While the user has not zoomed by hand, keeps the image fitted to the
    /// canvas: it shrinks when the note bar takes space the window could not
    /// add, and grows back toward the opening zoom when that space returns.
    private func refitImageIfFollowingFit() {
        guard followsAutomaticFit, userZoomFactor > 0 else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        let viewport = scrollView.contentSize
        let zoom = EditorWindowLayoutLogic.fittedZoom(
            contentSize: canvasView.panningContentBounds.size,
            viewportSize: NSSize(width: viewport.width - totalPadding, height: viewport.height - totalPadding),
            preferredZoom: openingEffectiveZoom
        )
        baseScale = zoom / userZoomFactor
        applyZoom()
    }

    // MARK: - Chrome gestures

    private enum ChromeRegion {
        case ink
        case windowDrag
        case other
    }

    /// Drags that start in the empty chrome around the canvas (title bar,
    /// toolbar sides, window edges) go to the canvas, and the ink layer shows
    /// the part outside the viewport. Empty toolbar space moves the window,
    /// since the title bar is drawable.
    func handleChromeMouseEvent(_ event: NSEvent, isKeyWindow: Bool) -> Bool {
        switch event.type {
        case .leftMouseDown:
            guard isKeyWindow, markerNotePopover == nil else { return false }
            switch chromeRegion(at: event.locationInWindow) {
            case .windowDrag:
                window?.performDrag(with: event)
                return true
            case .ink:
                // Text and markers act on a click, which would land off-canvas.
                switch canvasView.currentTool {
                case .text, .marker: return false
                default: break
                }
                forwardsChromeDragToCanvas = true
                canvasView.mouseDown(with: event)
                return true
            case .other:
                return false
            }
        case .leftMouseDragged:
            guard forwardsChromeDragToCanvas else { return false }
            canvasView.mouseDragged(with: event)
            return true
        case .leftMouseUp:
            guard forwardsChromeDragToCanvas else { return false }
            forwardsChromeDragToCanvas = false
            canvasView.mouseUp(with: event)
            return true
        default:
            return false
        }
    }

    private func chromeRegion(at windowPoint: NSPoint) -> ChromeRegion {
        // The frame view is the window's root view, so window coordinates
        // are what its hitTest expects.
        guard let frameView = window?.contentView?.superview,
              let hit = frameView.hitTest(windowPoint) else { return .other }
        if Self.isInsideControl(hit) { return .other }
        if hit.isDescendant(of: scrollView) { return .other }
        if let noteBar = notePreviewContainer, hit.isDescendant(of: noteBar) { return .other }
        if let toolbar = toolbarBackgroundView {
            if hit.isDescendant(of: toolbar) { return .windowDrag }
            // The strip straight above the toolbar stays a plain title bar
            // (window drag), so stray presses there never start a stroke.
            let toolbarFrame = toolbar.convert(toolbar.bounds, to: nil)
            if windowPoint.y >= toolbarFrame.maxY,
               windowPoint.x >= toolbarFrame.minX, windowPoint.x <= toolbarFrame.maxX {
                return .other
            }
        }
        return .ink
    }

    private static func isInsideControl(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate is NSControl { return true }
            current = candidate.superview
        }
        return false
    }

    private func presentMarkerNotePopover(number: Int, rect: NSRect) {
        markerNotePopover?.close()
        let context = markerNoteContext?(number) ?? (text: nil, capacity: WorkflowNoteRenderer.maxNoteLength)
        let field = MarkerNoteField(string: context.text ?? "")
        field.maxLength = context.capacity
        field.placeholderString = context.capacity > 0
            ? "Note for \(number)…"
            : "Note is full (\(WorkflowNoteRenderer.maxNoteLength) characters)"
        field.font = NSFont.systemFont(ofSize: 13)
        field.frame = NSRect(x: 10, y: 10, width: 300, height: 24)
        // Only Enter commits; focus changes while the popover opens must not.
        field.cell?.sendsActionOnEndEditing = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        content.addSubview(field)
        let controller = NSViewController()
        controller.view = content

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        field.target = self
        field.action = #selector(markerNoteCommitted(_:))
        field.tag = number
        popover.delegate = self
        markerNotePopover = popover
        canvasView.suspendsKeyEquivalents = true
        (window as? EditorWindow)?.keyEquivalentInterceptor = { [weak field] event in
            field?.handleEditingShortcut(event) ?? false
        }
        popover.show(relativeTo: rect, of: canvasView, preferredEdge: .maxY)
        let popoverWindow = popover.contentViewController?.view.window
        popoverWindow?.makeFirstResponder(field)
    }

    @objc private func markerNoteCommitted(_ sender: NSTextField) {
        let text = MarkerNoteLogic.sanitized(sender.stringValue)
        markerNotePopover?.close()
        markerNotePopover = nil
        window?.makeFirstResponder(canvasView)
        onMarkerNote?(sender.tag, text)
    }

    /// Note text as it will be burned in: prefix plus character cap, without
    /// modifying the image here. `nil` when there is no note to show.
    private var notePreviewDisplayText: String? {
        let raw = (notePreviewRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        var text = String(raw.prefix(WorkflowNoteRenderer.maxNoteLength))
        let settings = settingsStore.settings
        if settings.notePrefixEnabled {
            let prefix = settings.notePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                text = prefix + " " + text
            }
        }
        return text
    }

    private func makeNotePreviewView() -> EditorNotePreviewBar? {
        guard let text = notePreviewDisplayText else { return nil }
        let maxContentSize = EditorWindowLayoutLogic.maximumContentSize(
            visibleFrame: layoutVisibleFrame,
            minContentSize: window?.contentMinSize ?? .zero
        )
        return EditorNotePreviewBar(
            text: text,
            maxHeight: EditorWindowLayoutLogic.noteBarMaxHeight(maxContentHeight: maxContentSize.height)
        )
    }

    private func makeToolbarBackground() -> NSView {
        let background = NSView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.wantsLayer = true
        background.layer?.cornerRadius = 13
        background.layer?.backgroundColor = NSColor(hex: "#131515").cgColor
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor(hex: "#343737").cgColor
        return background
    }

    private func makeToolbarStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let penButton = makeToolButton(symbol: "pencil.tip", tool: .pen, toolTip: "Pen (W)")
        let lineButton = makeToolButton(symbol: "line.diagonal", tool: .line, toolTip: "Line (D)")
        let arrowButton = makeToolButton(symbol: "arrow.right", tool: .arrow, toolTip: "Arrow (A)")
        let rectButton = makeToolButton(symbol: "square", tool: .rectangle, toolTip: "Rectangle (R, Hold ⇧: Square)")
        let ovalButton = makeToolButton(symbol: "circle", tool: .ellipse, toolTip: "Ellipse (E, Hold ⇧: Circle)")
        let textButton = makeToolButton(symbol: "textformat", tool: .text, toolTip: "Text (T)")
        let markerButton = makeToolButton(symbol: "1.circle", tool: .marker, toolTip: "Numbered marker (F)")
        let selectionButton = makeToolButton(symbol: "rectangle.dashed", tool: .selection, toolTip: "Selection (S)")

        let undoButton = makeActionButton(symbol: "arrow.uturn.left", toolTip: "Undo (Cmd+Z)", action: #selector(undoPressed))
        let redoButton = makeActionButton(symbol: "arrow.uturn.right", toolTip: "Redo (Cmd+Shift+Z)", action: #selector(redoPressed))
        let clearButton = makeActionButton(symbol: "eraser", toolTip: "Clear (Option+Backspace)", action: #selector(clearPressed))

        let zoomOutButton = makeActionButton(symbol: "minus.magnifyingglass", toolTip: "Zoom Out (Cmd+-)", action: #selector(zoomOutPressed))
        let zoomInButton = makeActionButton(symbol: "plus.magnifyingglass", toolTip: "Zoom In (Cmd++)", action: #selector(zoomInPressed))

        let cancelButton = makeActionButton(symbol: "xmark", toolTip: "Cancel (Esc)", action: #selector(deletePressed))

        let saveButton = makeSaveButton()

        configureColorIndicator()

        zoomLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        zoomLabel.textColor = NSColor.secondaryLabelColor
        zoomLabel.alignment = .center
        zoomLabel.setContentHuggingPriority(.required, for: .horizontal)
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        // Give the color swatch the same footprint as the icon buttons.
        let colorContainer = NSView()
        colorContainer.translatesAutoresizingMaskIntoConstraints = false
        colorContainer.addSubview(colorIndicatorButton)
        NSLayoutConstraint.activate([
            colorContainer.widthAnchor.constraint(equalToConstant: 26),
            colorContainer.heightAnchor.constraint(equalToConstant: 26),
            colorIndicatorButton.centerXAnchor.constraint(equalTo: colorContainer.centerXAnchor),
            colorIndicatorButton.centerYAnchor.constraint(equalTo: colorContainer.centerYAnchor),
        ])

        shortcutHints = [
            .init(view: penButton, key: "W", label: "Pen"),
            .init(view: lineButton, key: "D", label: "Line"),
            .init(view: arrowButton, key: "A", label: "Arrow"),
            .init(view: rectButton, key: "R", label: "Rectangle"),
            .init(view: ovalButton, key: "E", label: "Ellipse"),
            .init(view: textButton, key: "T", label: "Text"),
            .init(view: markerButton, key: "F", label: "Numbered marker"),
            .init(view: selectionButton, key: "S", label: "Select"),
            .init(view: colorIndicatorButton, key: "Q", label: "Next color"),
            .init(view: undoButton, key: "⌘Z", label: "Undo"),
            .init(view: redoButton, key: "⌘⇧Z", label: "Redo"),
            .init(view: clearButton, key: "⌥⌫", label: "Clear annotations"),
            .init(view: zoomOutButton, key: "⌘−", label: "Zoom out"),
            .init(view: zoomLabel, key: "⌘0", label: "Reset zoom"),
            .init(view: zoomInButton, key: "⌘+", label: "Zoom in"),
            .init(view: cancelButton, key: "Esc", label: "Cancel"),
            .init(view: saveButton, key: "↩", label: "Save (⌘↩ to copy and save)")
        ]

        let drawingTools = makeToolbarGroup([
            penButton, lineButton, arrowButton, rectButton, ovalButton,
            textButton, markerButton, selectionButton, colorContainer
        ])
        let editActions = makeToolbarGroup([undoButton, redoButton, clearButton])
        let zoomControls = makeToolbarGroup([zoomOutButton, zoomLabel, zoomInButton])
        let sessionActions = makeToolbarGroup([cancelButton, saveButton])

        [drawingTools, editActions, zoomControls, sessionActions]
            .forEach { stack.addArrangedSubview($0) }

        stack.spacing = 8

        return stack
    }

    private func makeToolbarGroup(_ controls: [NSView]) -> NSView {
        EditorToolbarStyle.group(controls)
    }

    private func makeToolButton(symbol: String, tool: EditorTool, toolTip: String) -> NSButton {
        let button = makeIconButton(symbol: symbol, toolTip: toolTip)
        button.target = self
        button.action = #selector(toolButtonPressed(_:))
        toolButtons[tool] = button
        return button
    }

    private func makeActionButton(symbol: String, toolTip: String, action: Selector) -> NSButton {
        let button = makeIconButton(symbol: symbol, toolTip: toolTip)
        button.target = self
        button.action = action
        return button
    }

    private func makeIconButton(symbol: String, toolTip: String) -> NSButton {
        EditorToolbarStyle.iconButton(symbol: symbol, toolTip: toolTip)
    }

    private func makeSaveButton() -> NSButton {
        let button = makeActionButton(symbol: "tray.and.arrow.down",
                                      toolTip: "Save (Enter)",
                                      action: #selector(savePressed))
        button.title = ""
        return button
    }

    private func configureColorIndicator() {
        colorIndicatorButton.isBordered = false
        colorIndicatorButton.bezelStyle = .shadowlessSquare
        colorIndicatorButton.refusesFirstResponder = true
        colorIndicatorButton.wantsLayer = true
        colorIndicatorButton.layer?.cornerRadius = 9
        colorIndicatorButton.layer?.borderWidth = 2
        colorIndicatorButton.layer?.borderColor = NSColor.clear.cgColor
        colorIndicatorButton.translatesAutoresizingMaskIntoConstraints = false
        colorIndicatorButton.widthAnchor.constraint(equalToConstant: 18).isActive = true
        colorIndicatorButton.heightAnchor.constraint(equalToConstant: 18).isActive = true
        colorIndicatorButton.toolTip = "Next color (Q)"
        colorIndicatorButton.target = self
        colorIndicatorButton.action = #selector(colorIndicatorPressed)
        colorIndicatorButton.title = ""
    }

    private func reloadPaletteIfNeeded() {
        let updated = EditorPalette.normalized(settingsStore.settings.editorColorIDs)
        guard updated != paletteIDs else { return }
        let selectedID = paletteIDs[selectedColorIndex]
        paletteIDs = updated
        colors = EditorPalette.colors(for: updated).map(\.color)
        selectedColorIndex = updated.firstIndex(of: selectedID) ?? 0
        selectColor(index: selectedColorIndex)
    }

    // MARK: - Toolbar actions

    @objc private func toolButtonPressed(_ sender: NSButton) {
        guard let tool = toolButtons.first(where: { $0.value === sender })?.key else { return }
        selectTool(tool)
    }

    private func selectTool(_ tool: EditorTool) {
        canvasView.setTool(tool)
        for (key, button) in toolButtons {
            EditorToolbarStyle.setActive(button, key == tool)
        }
    }

    @objc private func colorIndicatorPressed() {
        cycleColor()
    }

    private func cycleColor() {
        selectColor(index: (selectedColorIndex + 1) % colors.count)
    }

    private func selectColor(index: Int) {
        guard colors.indices.contains(index) else { return }
        selectedColorIndex = index
        canvasView.currentColor = colors[index]
        colorIndicatorButton.layer?.backgroundColor = colors[index].cgColor
    }

    @objc private func undoPressed() {
        canvasView.undo()
    }

    @objc private func redoPressed() {
        canvasView.redo()
    }

    @objc private func clearPressed() {
        canvasView.clearAll()
    }

    @objc private func zoomInPressed() {
        setZoom(userZoomFactor * 1.2)
    }

    @objc private func zoomOutPressed() {
        setZoom(userZoomFactor / 1.2)
    }

    @objc private func savePressed() {
        finish(with: .saveOnly)
    }

    @objc private func deletePressed() {
        finish(with: escapeFinalAction)
    }

    // MARK: - Key commands from canvas

    private func handleKeyCommand(_ command: EditorCanvasView.KeyCommand) {
        switch command {
        case .finalAction(let action): finish(with: action)
        case .zoomIn: setZoom(userZoomFactor * 1.2)
        case .zoomOut: setZoom(userZoomFactor / 1.2)
        case .zoomReset: setZoom(defaultUserZoomFactor)
        case .backToNote:
            onBackToNote?()
            window?.orderOut(nil)
        case .selectTool(let tool): selectTool(tool)
        case .undo:
            canvasView.undo()
        case .redo:
            canvasView.redo()
        case .clear:
            canvasView.clearAll()
        case .copyToClipboard:
            copySelectionOrEditedImageToClipboard()
        case .cutSelectionToClipboard:
            cutSelectionToClipboard()
        case .pasteSelectionInCanvas:
            pasteSelectionInCanvas()
        case .cycleColor:
            cycleColor()
        }
    }

    private func setZoom(_ value: CGFloat) {
        let clampedUser = max(minUserZoom, min(maxUserZoom, value))
        userZoomFactor = clampedUser
        followsAutomaticFit = abs(clampedUser - defaultUserZoomFactor) < 0.001
        applyZoom()
    }

    private func applyZoom() {
        let desired = baseScale * userZoomFactor
        let effective = max(minEffectiveZoom, min(maxEffectiveZoom, desired))

        // Keep the user factor consistent if we had to clamp the effective zoom.
        if baseScale > 0 {
            userZoomFactor = max(minUserZoom, min(maxUserZoom, effective / baseScale))
        }

        scrollView.magnification = effective

        // Match mac_screenshot: zoom label is user zoom (starts at 100%),
        // independent of any base downscaling needed to fit the window.
        let percent = Int(round(userZoomFactor * 100))
        zoomLabel.stringValue = "\(percent)%"

        updateScrollLockAndRecentering()
    }

    private var layoutVisibleFrame: NSRect? {
        targetScreen?.visibleFrame ?? window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    private func sizeWindowToImage() {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()

        let imageSize = canvasView.baseImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scaleFactor = max(window.backingScaleFactor, 1.0)
        let pixelSize = imagePixelSize(canvasView.baseImage)
        let pointW = pixelSize.width / scaleFactor
        let pointH = pixelSize.height / scaleFactor

        let minW: CGFloat = 580.0
        let minH: CGFloat = 250.0
        let toolbarH: CGFloat = toolbarMinimumHeight
        let chromeW: CGFloat = 24.0
        let minContentSize = NSSize(width: minW, height: minH)
        let maxContentSize = EditorWindowLayoutLogic.maximumContentSize(
            visibleFrame: layoutVisibleFrame,
            minContentSize: minContentSize
        )

        func makeLayout(noteHeight noteH: CGFloat, minWidth: CGFloat) -> EditorWindowLayoutResult {
            // Root stack spacing is 10. If we have a note preview bar, add its height + spacing.
            let chromeH: CGFloat = 24.0 + toolbarH + 10.0 + (noteH > 0 ? (10.0 + noteH) : 0.0)
            return EditorWindowLayoutLogic.makeLayout(
                EditorWindowLayoutInput(imagePointSize: NSSize(width: pointW, height: pointH),
                                        maxContentSize: maxContentSize,
                                        minContentSize: NSSize(width: minWidth, height: minContentSize.height),
                                        chromeSize: NSSize(width: chromeW, height: chromeH),
                                        autoZoomFillRatio: autoZoomFillRatio,
                                        maxAutoUserZoom: maxAutoUserZoom)
            )
        }
        // Size the width for the image alone. A note then only takes height:
        // if the image must shrink to make room, the window keeps its width
        // so the note wraps at full width instead of growing taller.
        var layout = makeLayout(noteHeight: 0, minWidth: minW)
        if let noteBar = notePreviewContainer {
            let width = layout.contentSize.width
            layout = makeLayout(noteHeight: noteBar.preferredHeight(forWidth: width - chromeW), minWidth: width)
        }
        totalPadding = layout.totalPadding

        let pointToCanvasScaleW = pointW / imageSize.width
        let pointToCanvasScaleH = pointH / imageSize.height
        let pointToCanvasScale = min(pointToCanvasScaleW, pointToCanvasScaleH)
        baseScale = layout.fitScale * pointToCanvasScale

        window.setContentSize(layout.contentSize)

        defaultUserZoomFactor = layout.defaultUserZoomFactor
        userZoomFactor = defaultUserZoomFactor
        openingEffectiveZoom = baseScale * defaultUserZoomFactor
        applyZoom()

    }

    private func positionWindowOnTargetScreen() {
        guard let window else { return }

        if let targetScreen {
            let frame = targetScreen.visibleFrame
            let windowSize = window.frame.size
            let origin = NSPoint(x: frame.midX - windowSize.width / 2,
                                 y: frame.midY - windowSize.height / 2)
            window.setFrameOrigin(origin)
            return
        }

        window.center()
    }

    private func imagePixelSize(_ image: NSImage) -> NSSize {
        if let bestBitmap = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { lhs, rhs in lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh }),
           bestBitmap.pixelsWide > 0,
           bestBitmap.pixelsHigh > 0 {
            return NSSize(width: CGFloat(bestBitmap.pixelsWide), height: CGFloat(bestBitmap.pixelsHigh))
        }

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        }

        return image.size
    }

    /// Panning is only for reaching content: the image, annotations, or an
    /// open text box. The blank canvas margin around them never scrolls.
    private func scrollableAxes() -> (x: Bool, y: Bool) {
        let clipSize = scrollView.contentView.bounds.size
        let content = canvasView.panningContentBounds
        // Small epsilon so rounding at some magnifications doesn't count as scrollable.
        let epsilon: CGFloat = 1.0
        return (content.width > clipSize.width + epsilon, content.height > clipSize.height + epsilon)
    }

    private var isContentScrollable: Bool {
        let axes = scrollableAxes()
        return axes.x || axes.y
    }

    private func updateScrollLockAndRecentering() {
        guard let documentView = scrollView.documentView else { return }
        canvasView.ensureDrawableAreaCoversVisibleSize(scrollView.contentView.bounds.size)
        let clipSize = scrollView.contentView.bounds.size
        let docSize = documentView.frame.size
        let content = canvasView.panningContentBounds
        let (scrollableX, scrollableY) = scrollableAxes()

        scrollView.horizontalScrollElasticity = scrollableX ? .automatic : .none
        scrollView.verticalScrollElasticity = scrollableY ? .automatic : .none

        // Keep non-scrollable axes centered on the content (native feel).
        var origin = scrollView.contentView.bounds.origin
        origin.x = Self.clipOrigin(current: origin.x, scrollable: scrollableX, clip: clipSize.width,
                                   document: docSize.width, contentMid: content.midX)
        origin.y = Self.clipOrigin(current: origin.y, scrollable: scrollableY, clip: clipSize.height,
                                   document: docSize.height, contentMid: content.midY)

        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func clipOrigin(current: CGFloat, scrollable: Bool, clip: CGFloat,
                                   document: CGFloat, contentMid: CGFloat) -> CGFloat {
        guard document > clip else { return floor((document - clip) / 2.0) }
        let maxOrigin = document - clip
        let origin = scrollable ? current : floor(contentMid - clip / 2.0)
        return max(0, min(origin, maxOrigin))
    }

    private func copySelectionOrEditedImageToClipboard() {
        if let payload = canvasView.selectedRegionPayload() {
            clipboardService.writeImage(payload.image)
            return
        }
        clipboardService.writeImage(canvasView.compositeImage())
    }

    private func cutSelectionToClipboard() {
        guard let payload = canvasView.selectedRegionPayload() else { return }
        clipboardService.writeImage(payload.image)
        _ = canvasView.cutSelectedRegion()
    }

    private func pasteSelectionInCanvas() {
        _ = canvasView.pasteCopiedSelection()
    }

    // MARK: - Finishing

    private func finish(with action: ScreenshotFinalAction) {
        // Cancelling keeps the editor open with drawings intact: no
        // completion is sent, so the workflow stays alive and the window
        // never closes.
        guard confirmCancellation(for: action) else { return }
        guard let completion = onComplete else {
            close()
            return
        }

        let shouldExportEditedImage = action != .deleteOnly && action != .closeOnly
        let image = shouldExportEditedImage ? canvasView.compositeImage() : nil
        let state = shouldExportEditedImage ? canvasView.editableState() : nil
        didSendCompletion = true
        completion(image, action, state)
        close()
    }

    private func confirmCancellation(for action: ScreenshotFinalAction) -> Bool {
        guard settingsStore.settings.confirmBeforeClosing else { return true }
        switch action {
        case .deleteOnly:
            return onConfirmDelete?() ?? true
        case .closeOnly:
            return onConfirmClose?() ?? true
        default:
            return true
        }
    }
}

extension EditorWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Post-completion and programmatic closes always proceed.
        guard !didSendCompletion else { return true }
        // Cancelling either confirmation leaves the editing session intact.
        return confirmCancellation(for: escapeFinalAction)
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyDownMonitor()
        guard !didSendCompletion else { return }
        guard let completion = onComplete else { return }
        didSendCompletion = true
        completion(nil, escapeFinalAction, nil)
    }

    func windowDidResize(_ notification: Notification) {
        // Native screenshot editor does not auto-scale the image when you manually resize the window.
        // Keep zoom stable; just update panning lock and centering.
        updateScrollLockAndRecentering()
    }
}

/// Marker note field. The popover window has no Edit menu behind it, so the
/// standard editing shortcuts are routed to the field editor directly.
final class MarkerNoteField: NSTextField {
    var maxLength = Int.max

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        guard stringValue.count > maxLength else { return }
        stringValue = String(stringValue.prefix(maxLength))
        NSSound.beep()
    }

    private static let editingSelectors: [String: Selector] = [
        "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "x": #selector(NSText.cut(_:)), "a": #selector(NSText.selectAll(_:))
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event) || super.performKeyEquivalent(with: event)
    }

    func handleEditingShortcut(_ event: NSEvent) -> Bool {
        guard let editor = currentEditor() as? NSTextView else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased()
        if chars == "z" {
            if flags == [.command] { editor.undoManager?.undo(); return true }
            if flags == [.command, .shift] { editor.undoManager?.redo(); return true }
        }
        if flags == [.command], let chars, let selector = Self.editingSelectors[chars] {
            return NSApp.sendAction(selector, to: editor, from: self)
        }
        return false
    }
}

extension EditorWindowController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // A stale close (after a newer popover opened) must not restore shortcuts.
        let closed = notification.object as? NSPopover
        guard markerNotePopover == nil || closed === markerNotePopover else { return }
        markerNotePopover = nil
        canvasView.suspendsKeyEquivalents = false
        (window as? EditorWindow)?.keyEquivalentInterceptor = nil
    }
}

/// Centers the document view when it is smaller than the visible area.
/// This matches the native screenshot editor feel (image stays centered while resizing).
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }

        let docSize = documentView.frame.size
        let clipSize = bounds.size

        if docSize.width < clipSize.width {
            rect.origin.x = floor((docSize.width - clipSize.width) / 2.0)
        }
        if docSize.height <= clipSize.height {
            rect.origin.y = floor((docSize.height - clipSize.height) / 2.0)
        } else {
            let maxY = docSize.height - clipSize.height
            rect.origin.y = max(0, min(rect.origin.y, maxY))
        }

        return rect
    }
}

private final class EditorScrollView: NSScrollView {
    var shouldAllowScroll: (() -> Bool)?

    override func scrollWheel(with event: NSEvent) {
        if let shouldAllowScroll, !shouldAllowScroll() {
            return
        }
        super.scrollWheel(with: event)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if normalized.count == 6 {
            normalized.append("FF")
        }
        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)
        let red = CGFloat((value >> 24) & 0xFF) / 255
        let green = CGFloat((value >> 16) & 0xFF) / 255
        let blue = CGFloat((value >> 8) & 0xFF) / 255
        let alpha = CGFloat(value & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

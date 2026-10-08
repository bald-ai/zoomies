import AppKit

/// Active colors define both the Q cycling order and the visual picker's order.
/// One row: the active colors left to right (drag to reorder, click to remove)
/// and a + menu listing every color to add or remove.
final class EditorPaletteSettingsView: NSStackView {
    private let store: SettingsStore
    // Internal so tests can drive the strip and menus directly.
    let strip = PaletteStripView()
    let addButton: NSButton
    private let footnote = SettingsGroupView.footnote("Q in the editor cycles through these left to right. Drag to reorder, click to remove.")
    private var observer: NSObjectProtocol?

    init(settingsStore: SettingsStore) {
        store = settingsStore
        let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add color")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        addButton = NSButton(image: plus ?? NSImage(), target: nil, action: nil)
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6

        strip.onMove = { [weak self] from, to in self?.move(from: from, to: to) }
        strip.menuForColor = { [weak self] index in self?.menu(forColorAt: index) }
        addButton.bezelStyle = .circular
        addButton.controlSize = .small
        addButton.toolTip = "Add or remove colors"
        addButton.target = self
        addButton.action = #selector(showAddMenu(_:))

        let group = SettingsGroupView(rows: [SettingsGroupView.row([strip, NSView(), addButton])])
        addArrangedSubview(group)
        addArrangedSubview(footnote)
        group.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        footnote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14).isActive = true
        footnote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14).isActive = true
        reload()
        observer = NotificationCenter.default.addObserver(forName: SettingsStore.didChangeNotification, object: store, queue: .main) { [weak self] _ in self?.reload() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func reload() {
        strip.colors = EditorPalette.colors(for: store.settings.editorColorIDs)
    }

    // MARK: - Menus

    func menu(forColorAt index: Int) -> NSMenu {
        let ids = store.settings.editorColorIDs
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard ids.indices.contains(index) else { return menu }
        let name = EditorPalette.colors(for: ids)[index].name
        let remove = NSMenuItem(title: "Remove \(name)", action: #selector(removeColor(_:)), keyEquivalent: "")
        remove.target = self
        remove.tag = index
        remove.isEnabled = ids.count > 1
        menu.addItem(remove)
        return menu
    }

    /// Every color, checked when active; picking one adds or removes it.
    func addMenu() -> NSMenu {
        let ids = store.settings.editorColorIDs
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, color) in EditorPalette.available.enumerated() {
            let active = ids.contains(color.id)
            let item = NSMenuItem(title: color.name, action: #selector(toggleColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = active ? .on : .off
            item.image = PaletteStripView.menuSwatch(color.color)
            item.isEnabled = active ? ids.count > 1 : ids.count < EditorPalette.maximumCount
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showAddMenu(_ sender: NSButton) {
        addMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    // MARK: - Changes

    @objc private func toggleColor(_ sender: NSMenuItem) {
        let id = EditorPalette.available[sender.tag].id
        store.update { settings in
            if let index = settings.editorColorIDs.firstIndex(of: id) {
                guard settings.editorColorIDs.count > 1 else { return }
                settings.editorColorIDs.remove(at: index)
            } else {
                guard settings.editorColorIDs.count < EditorPalette.maximumCount else { return }
                settings.editorColorIDs.append(id)
            }
        }
    }
    @objc private func removeColor(_ sender: NSMenuItem) {
        store.update { settings in
            guard settings.editorColorIDs.count > 1, settings.editorColorIDs.indices.contains(sender.tag) else { return }
            settings.editorColorIDs.remove(at: sender.tag)
        }
    }
    private func move(from source: Int, to destination: Int) {
        store.update { settings in
            guard settings.editorColorIDs.indices.contains(source),
                  settings.editorColorIDs.indices.contains(destination) else { return }
            let id = settings.editorColorIDs.remove(at: source)
            settings.editorColorIDs.insert(id, at: destination)
        }
    }
}

/// The active colors as dots. Dragging one slides it into a new slot; a click
/// without dragging opens that color's menu.
final class PaletteStripView: NSView {
    static let diameter: CGFloat = 26
    static let gap: CGFloat = 12

    var colors: [EditorPaletteColor] = [] {
        didSet {
            order = Array(colors.indices)
            invalidateIntrinsicContentSize()
            rebuildToolTips()
            needsDisplay = true
        }
    }
    var onMove: ((Int, Int) -> Void)?
    var menuForColor: ((Int) -> NSMenu?)?

    /// Display order during a drag, as indices into `colors`.
    private var order: [Int] = []
    private var dragged: (index: Int, startX: CGFloat, x: CGFloat, moved: Bool)?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        let count = CGFloat(max(colors.count, 1))
        return NSSize(width: count * Self.diameter + (count - 1) * Self.gap + 4, height: Self.diameter + 4)
    }

    private func slotRect(_ slot: Int) -> NSRect {
        NSRect(x: 2 + CGFloat(slot) * (Self.diameter + Self.gap), y: 2, width: Self.diameter, height: Self.diameter)
    }
    private func slot(at point: NSPoint) -> Int? {
        order.indices.first { slotRect($0).insetBy(dx: -Self.gap / 2, dy: -2).contains(point) }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (slot, index) in order.enumerated() where index != dragged?.index {
            Self.drawDot(colors[index].color, in: slotRect(slot))
        }
        if let dragged {
            // The held dot follows the pointer, lifted slightly.
            let rect = slotRect(dragged.index).offsetBy(dx: dragged.x - dragged.startX, dy: 0)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 6
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.set()
            Self.drawDot(colors[dragged.index].color, in: rect.insetBy(dx: -2, dy: -2))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func drawDot(_ color: NSColor, in rect: NSRect) {
        let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        color.setFill()
        dot.fill()
        NSColor(white: 1, alpha: 0.28).setStroke()
        dot.lineWidth = 1
        dot.stroke()
    }

    static func menuSwatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            drawDot(color, in: rect.insetBy(dx: 0.5, dy: 0.5))
            return true
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let slot = slot(at: point) else { return }
        dragged = (order[slot], point.x, point.x, false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = dragged else { return }
        current.x = convert(event.locationInWindow, from: nil).x
        current.moved = current.moved || abs(current.x - current.startX) > 3
        dragged = current
        // Slide the held dot into whichever slot its center is over.
        let center = slotRect(current.index).midX + current.x - current.startX
        let target = max(0, min(order.count - 1, Int((center - 2) / (Self.diameter + Self.gap))))
        if let from = order.firstIndex(of: current.index), from != target {
            order.remove(at: from)
            order.insert(current.index, at: target)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = dragged else { return }
        dragged = nil
        let destination = order.firstIndex(of: current.index) ?? current.index
        order = Array(colors.indices)
        needsDisplay = true
        if !current.moved, let slot = order.firstIndex(of: current.index), let menu = menuForColor?(current.index) {
            menu.popUp(positioning: nil, at: NSPoint(x: slotRect(slot).minX, y: slotRect(slot).maxY + 6), in: self)
        } else if destination != current.index {
            onMove?(current.index, destination)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        slot(at: convert(event.locationInWindow, from: nil)).flatMap { menuForColor?($0) }
    }

    private func rebuildToolTips() {
        removeAllToolTips()
        for (slot, color) in colors.enumerated() {
            addToolTip(slotRect(slot), owner: "\(slot + 1). \(color.name)" as NSString, userData: nil)
        }
    }
}

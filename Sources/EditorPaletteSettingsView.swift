import AppKit

/// Active colors define both the Q cycling order and the visual picker's order.
final class EditorPaletteSettingsView: NSStackView {
    private let store: SettingsStore
    private var observer: NSObjectProtocol?

    init(settingsStore: SettingsStore) {
        store = settingsStore
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 12
        reload()
        observer = NotificationCenter.default.addObserver(forName: SettingsStore.didChangeNotification, object: store, queue: .main) { [weak self] _ in self?.reload() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func reload() {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        let ids = store.settings.editorColorIDs
        let title = NSTextField(labelWithString: "Your color order · \(ids.count) of 6")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        addArrangedSubview(title)
        let help = NSTextField(wrappingLabelWithString: "Press Q in the editor to cycle through this list. Choose 1–6 colors and use the arrows to change their order.")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: widthAnchor).isActive = true

        for (index, color) in EditorPalette.colors(for: ids).enumerated() {
            let number = NSTextField(labelWithString: "\(index + 1)")
            number.textColor = .secondaryLabelColor
            number.widthAnchor.constraint(equalToConstant: 16).isActive = true
            let swatch = makeSwatch(color.color)
            let name = NSTextField(labelWithString: color.name)
            let up = button("↑", action: #selector(moveColorEarlier(_:)), tag: index)
            up.isEnabled = index > 0
            up.toolTip = "Move \(color.name) earlier"
            let down = button("↓", action: #selector(moveColorLater(_:)), tag: index)
            down.isEnabled = index < ids.count - 1
            down.toolTip = "Move \(color.name) later"
            let remove = button("−", action: #selector(removeColor(_:)), tag: index)
            remove.isEnabled = ids.count > 1
            remove.toolTip = "Remove \(color.name)"
            let row = NSStackView(views: [number, swatch, name, NSView(), up, down, remove])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }

        addAvailableColors(ids: ids)
    }

    private func addAvailableColors(ids: [String]) {
        let choose = NSTextField(labelWithString: ids.count == 6 ? "Available colors · remove one above to add another" : "Available colors · click to add")
        choose.font = .systemFont(ofSize: 12, weight: .medium)
        choose.textColor = .secondaryLabelColor
        addArrangedSubview(choose)
        for rowStart in stride(from: 0, to: EditorPalette.available.count, by: 5) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 8
            for index in rowStart..<min(rowStart + 5, EditorPalette.available.count) {
                let color = EditorPalette.available[index]
                let selected = ids.contains(color.id)
                let button = NSButton(title: (selected ? "✓ " : "") + color.name, target: self, action: #selector(addColor(_:)))
                button.tag = index
                button.bezelStyle = .rounded
                button.font = .systemFont(ofSize: 11)
                button.isEnabled = !selected && ids.count < 6
                button.toolTip = selected ? "Already in your color order" : "Add \(color.name)"
                button.image = swatchImage(color.color)
                button.imagePosition = .imageLeading
                row.addArrangedSubview(button)
            }
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
    }

    private func button(_ title: String, action: Selector, tag: Int) -> NSButton {
        let result = NSButton(title: title, target: self, action: action)
        result.tag = tag
        result.bezelStyle = .rounded
        result.widthAnchor.constraint(equalToConstant: 32).isActive = true
        return result
    }
    private func makeSwatch(_ color: NSColor) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = 6
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.gray.cgColor
        view.widthAnchor.constraint(equalToConstant: 20).isActive = true
        view.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return view
    }
    private func swatchImage(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            path.fill()
            NSColor.gray.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
    @objc private func addColor(_ sender: NSButton) {
        let id = EditorPalette.available[sender.tag].id
        store.update { settings in
            guard settings.editorColorIDs.count < 6, !settings.editorColorIDs.contains(id) else { return }
            settings.editorColorIDs.append(id)
        }
    }
    @objc private func removeColor(_ sender: NSButton) {
        store.update { settings in
            guard settings.editorColorIDs.count > 1, settings.editorColorIDs.indices.contains(sender.tag) else { return }
            settings.editorColorIDs.remove(at: sender.tag)
        }
    }
    @objc private func moveColorEarlier(_ sender: NSButton) { move(sender.tag, by: -1) }
    @objc private func moveColorLater(_ sender: NSButton) { move(sender.tag, by: 1) }
    private func move(_ index: Int, by offset: Int) {
        store.update { settings in
            guard settings.editorColorIDs.indices.contains(index), settings.editorColorIDs.indices.contains(index + offset) else { return }
            settings.editorColorIDs.swapAt(index, index + offset)
        }
    }
}

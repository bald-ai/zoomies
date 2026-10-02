import AppKit

/// Toolbar look shared by the screenshot editor and the note editor, so both
/// read as the same app.
enum EditorToolbarStyle {
    static func iconButton(symbol: String, toolTip: String) -> NSButton {
        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.refusesFirstResponder = true
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(hex: "#dedfe0")
        button.toolTip = toolTip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    /// Marks the chosen tool the way the screenshot editor always has.
    static func setActive(_ button: NSButton, _ isActive: Bool) {
        button.layer?.backgroundColor = isActive ? NSColor(hex: "#253e54").cgColor : NSColor.clear.cgColor
        button.contentTintColor = isActive ? NSColor(hex: "#8ac5ff") : NSColor(hex: "#dedfe0")
    }

    static func group(_ controls: [NSView]) -> NSView {
        let surface = NSView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 9
        surface.layer?.backgroundColor = NSColor(hex: "#2b2e2e").cgColor
        surface.layer?.borderWidth = 0.5
        surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let controlsStack = NSStackView(views: controls)
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 2
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(controlsStack)
        NSLayoutConstraint.activate([
            controlsStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 3),
            controlsStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -3),
            controlsStack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 3),
            controlsStack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -3)
        ])
        return surface
    }
}

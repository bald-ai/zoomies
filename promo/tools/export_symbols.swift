import AppKit

// Exports the SF Symbols used by the Zoomies UI as white PNGs (tinted later via CSS masks).
let symbols = [
    "pencil.tip", "line.diagonal", "arrow.right", "square", "circle", "textformat",
    "1.circle", "rectangle.dashed", "arrow.uturn.left", "arrow.uturn.right", "eraser",
    "minus.magnifyingglass", "plus.magnifyingglass", "xmark", "tray.and.arrow.down",
    "camera", "keyboard", "doc.on.clipboard", "note.text", "record.circle", "command",
    "option", "shift", "return", "sparkles", "cursorarrow", "folder", "photo"
]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for name in symbols {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        print("missing \(name)"); continue
    }
    let config = NSImage.SymbolConfiguration(pointSize: 160, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    guard let img = base.withSymbolConfiguration(config) else { continue }
    let size = img.size
    let scale: CGFloat = 1
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                     pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(origin: .zero, size: NSSize(width: size.width * scale, height: size.height * scale)))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("\(name) \(Int(size.width))x\(Int(size.height))")
}

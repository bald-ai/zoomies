import XCTest
import AppKit

enum TestSupport {
    /// Ends a bare view's responder chain so keys it passes on are dropped
    /// quietly. With no window behind the view, AppKit plays the system alert
    /// sound for every unhandled key, which makes `swift test` beep.
    static func swallowingUnhandledKeys<View: NSView>(_ view: View) -> View {
        view.nextResponder = unhandledKeySink
        return view
    }

    private final class UnhandledKeySink: NSResponder {
        override func keyDown(with event: NSEvent) {}
        override func keyUp(with event: NSEvent) {}
        override func noResponder(for eventSelector: Selector) {}
    }

    /// `nextResponder` is not retained, so the sink must outlive every view.
    private static let unhandledKeySink = UnhandledKeySink()

    static func makeTemporaryDirectory(function: StaticString = #function) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let name = "zoomies_tests_\(function)_\(UUID().uuidString)"
        let directory = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func solidImage(width: CGFloat = 100, height: CGFloat = 60, color: NSColor = .systemBlue) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    static func solidImagePNGData(width: CGFloat = 100,
                                  height: CGFloat = 60,
                                  color: NSColor = .systemBlue) throws -> Data {
        let image = solidImage(width: width, height: height, color: color)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TestSupport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode test PNG image"])
        }
        return data
    }

    /// Builds JPEG bytes for tests only. The app never encodes JPEG; this exists
    /// solely to fabricate a non-PNG file and verify it gets converted to PNG.
    static func solidImageJPEGData(width: CGFloat = 100,
                                   height: CGFloat = 60,
                                   color: NSColor = .systemBlue) throws -> Data {
        let image = solidImage(width: width, height: height, color: color)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [:]) else {
            throw NSError(domain: "TestSupport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode test JPEG image"])
        }
        return data
    }

    /// Deterministic noisy PNG. Noise barely compresses, so ImageIO splits the
    /// pixel data across many IDAT chunks, like a real screenshot.
    static func noiseImagePNGData(width: Int, height: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let pixels = rep.bitmapData else {
            throw NSError(domain: "TestSupport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate noise bitmap"])
        }
        var seed: UInt32 = 0x2545_F491
        for index in 0..<(rep.bytesPerRow * height) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "TestSupport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode noise PNG"])
        }
        return data
    }

    static func writeSolidImagePNG(to url: URL,
                                   width: CGFloat = 100,
                                   height: CGFloat = 60,
                                   color: NSColor = .systemBlue) throws {
        let data = try solidImagePNGData(width: width, height: height, color: color)
        try data.write(to: url, options: .atomic)
    }
}

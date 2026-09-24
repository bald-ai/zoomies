import AppKit
import Foundation

/// Generic NSImage → bitmap/PNG conversion shared by capture saving, editor
/// state persistence, and workflow output. Keeps the image's native pixel
/// dimensions and logical point size instead of inheriting a screen scale.
enum ImageEncoding {
    static func pngData(from image: NSImage) -> Data? {
        guard let bitmap = bitmapRepresentation(from: image) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func bitmapRepresentation(from image: NSImage) -> NSBitmapImageRep? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if image.size.width > 0, image.size.height > 0 {
                bitmap.size = image.size
            }
            return bitmap
        }

        return renderBitmap(from: image)
    }

    private static func preferredPixelSize(for image: NSImage) -> NSSize {
        image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { lhs, rhs in
                (ImageSafety.pixelCount(width: lhs.pixelsWide, height: lhs.pixelsHigh) ?? 0)
                    < (ImageSafety.pixelCount(width: rhs.pixelsWide, height: rhs.pixelsHigh) ?? 0)
            })
            .map { NSSize(width: CGFloat($0.pixelsWide), height: CGFloat($0.pixelsHigh)) }
            ?? image.size
    }

    /// Some image representations cannot expose a CGImage. Render their best
    /// available pixel size without inheriting the current display's scale.
    private static func renderBitmap(from image: NSImage) -> NSBitmapImageRep? {
        let pointSize = image.size
        let pixelSize = preferredPixelSize(for: image)
        guard let pixelWidth = ImageSafety.pixelLength(pixelSize.width.rounded(.up)),
              let pixelHeight = ImageSafety.pixelLength(pixelSize.height.rounded(.up)),
              let bitmap = ImageSafety.makeBitmapRep(pixelsWide: pixelWidth, pixelsHigh: pixelHeight) else {
            return nil
        }

        bitmap.size = pointSize.width > 0 && pointSize.height > 0
            ? pointSize
            : NSSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: bitmap.size),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        return bitmap
    }
}

import AppKit
import Foundation
import ImageIO

/// Centralized, overflow-safe limits for file size, decoded pixels, and bitmap
/// allocation. Used before AppKit/ImageIO is asked to materialize pixels.
struct ImageSafetyLimits: Equatable {
    var maxDimension: Int
    var maxDecodedPixels: Int
    var maxExportPixelArea: Int
    var maxAbsoluteCoordinate: CGFloat
    var maxItemCount: Int
    var maxPenPointCount: Int
    var maxEmbeddedImageBytes: Int
    var maxFileBytes: Int
    var maxEditorStateChunkBytes: Int
    var maxOriginalPNGChunkBytes: Int
    var maxPromptChunkBytes: Int
    var maxPromptLength: Int
    var maxTextLength: Int
    var maxLineWidth: CGFloat
    var maxFontSize: CGFloat

    /// Generous enough for 5K/8K Retina screenshots and Zoomies round-trip
    /// metadata; tight enough that RGBA decode stays well under a gigabyte.
    static let runtime = ImageSafetyLimits(
        maxDimension: 16_384,
        maxDecodedPixels: 50_000_000,
        maxExportPixelArea: 50_000_000,
        maxAbsoluteCoordinate: 16_384,
        maxItemCount: 5_000,
        maxPenPointCount: 100_000,
        maxEmbeddedImageBytes: WorkflowImagePersistenceLogic.maxEmbeddedOriginalBytes,
        maxFileBytes: 256 * 1024 * 1024,
        maxEditorStateChunkBytes: 90 * 1024 * 1024,
        maxOriginalPNGChunkBytes: 80 * 1024 * 1024,
        maxPromptChunkBytes: 256 * 1024,
        maxPromptLength: 16_384,
        maxTextLength: 50_000,
        maxLineWidth: 1_000,
        maxFontSize: 2_000
    )
}

enum ImageFileInspection: Equatable {
    case safe
    case notAnImage
    case tooLarge
}

enum ImageSafety {
    static func pixelCount(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let (count, overflowed) = width.multipliedReportingOverflow(by: height)
        return overflowed ? nil : count
    }

    static func pixelLength(_ value: CGFloat) -> Int? {
        guard value.isFinite, value > 0 else { return nil }
        let rounded = value.rounded()
        guard rounded <= CGFloat(Int.max) else { return nil }
        let length = Int(rounded)
        return length > 0 ? length : nil
    }

    static func isSafePixelSize(width: Int,
                                height: Int,
                                limits: ImageSafetyLimits = .runtime,
                                maxPixels: Int? = nil) -> Bool {
        let pixelBudget = maxPixels ?? limits.maxDecodedPixels
        guard width > 0, height > 0,
              width <= limits.maxDimension,
              height <= limits.maxDimension,
              let count = pixelCount(width: width, height: height) else {
            return false
        }
        return count <= pixelBudget
    }

    static func canAllocateBitmap(width: Int,
                                  height: Int,
                                  limits: ImageSafetyLimits = .runtime) -> Bool {
        isSafePixelSize(width: width, height: height, limits: limits, maxPixels: limits.maxExportPixelArea)
    }

    static func makeBitmapRep(pixelsWide: Int,
                              pixelsHigh: Int,
                              limits: ImageSafetyLimits = .runtime) -> NSBitmapImageRep? {
        guard canAllocateBitmap(width: pixelsWide, height: pixelsHigh, limits: limits) else {
            return nil
        }
        return NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: pixelsWide,
                                pixelsHigh: pixelsHigh,
                                bitsPerSample: 8,
                                samplesPerPixel: 4,
                                hasAlpha: true,
                                isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0,
                                bitsPerPixel: 0)
    }

    static func isSafePNG(_ data: Data, limits: ImageSafetyLimits = .runtime) -> Bool {
        inspectData(data, limits: limits) == .safe && PNGMetadata.isPNG(data)
    }

    static func inspectFile(at url: URL, limits: ImageSafetyLimits = .runtime) -> ImageFileInspection {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size >= 0 else {
            return .notAnImage
        }
        if size > limits.maxFileBytes {
            return .tooLarge
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .notAnImage
        }
        return inspectData(data, limits: limits)
    }

    static func boundedFileData(at url: URL, limits: ImageSafetyLimits = .runtime) -> Data? {
        guard inspectFile(at: url, limits: limits) != .tooLarge else { return nil }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size >= 0, size <= limits.maxFileBytes else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func inspectData(_ data: Data, limits: ImageSafetyLimits = .runtime) -> ImageFileInspection {
        if data.count > limits.maxFileBytes {
            return .tooLarge
        }
        if let dimensions = PNGMetadata.pixelDimensions(ofPNG: data) {
            return isSafePixelSize(width: dimensions.width, height: dimensions.height, limits: limits)
                ? .safe
                : .tooLarge
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else {
            return .notAnImage
        }
        guard let width = cfInt(props[kCGImagePropertyPixelWidth]),
              let height = cfInt(props[kCGImagePropertyPixelHeight]) else {
            return .notAnImage
        }
        return isSafePixelSize(width: width, height: height, limits: limits) ? .safe : .tooLarge
    }

    static func loadImageIfSafe(_ data: Data, limits: ImageSafetyLimits = .runtime) -> NSImage? {
        guard inspectData(data, limits: limits) == .safe else { return nil }
        return NSImage(data: data)
    }

    private static func cfInt(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            let intValue = number.intValue
            return intValue > 0 ? intValue : nil
        }
        return nil
    }
}

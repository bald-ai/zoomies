import XCTest
import AppKit
@testable import Zoomies

final class ImageEncodingTests: XCTestCase {
    private final class FallbackImage: NSImage {
        override func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?,
                              context: NSGraphicsContext?, hints: [NSImageRep.HintKey: Any]?) -> CGImage? { nil }
    }

    func testFallbackRendersPixelsAtLargestBackingResolutionAndKeepsLogicalSize() throws {
        let image = FallbackImage(size: NSSize(width: 10, height: 5))
        for width: CGFloat in [10, 20] {
            let data = try TestSupport.solidImagePNGData(width: width, height: width / 2, color: .red)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
            rep.size = image.size
            image.addRepresentation(rep)
        }
        let result = try XCTUnwrap(ImageEncoding.bitmapRepresentation(from: image))
        XCTAssertEqual(result.pixelsWide, 40)
        XCTAssertEqual(result.pixelsHigh, 20)
        XCTAssertEqual(result.size, NSSize(width: 10, height: 5))
        let center = try XCTUnwrap(result.colorAt(x: 20, y: 10)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(center.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(center.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(center.blueComponent, 0, accuracy: 0.01)
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.01)
    }

    func testFallbackWithoutBackingRepUsesPointsAndRejectsZeroSize() throws {
        let image = FallbackImage(size: NSSize(width: 12, height: 9))
        let result = try XCTUnwrap(ImageEncoding.bitmapRepresentation(from: image))
        XCTAssertEqual(result.pixelsWide, 12)
        XCTAssertEqual(result.pixelsHigh, 9)
        XCTAssertNil(ImageEncoding.bitmapRepresentation(from: FallbackImage(size: .zero)))
        XCTAssertNil(ImageEncoding.pngData(from: FallbackImage(size: .zero)))
    }

    func testBitmapRepresentationPreservesBackingPixelDimensions() throws {
        let pointSize = NSSize(width: 200, height: 100)
        let pixelWidth = 400
        let pixelHeight = 200

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelWidth,
                                         pixelsHigh: pixelHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            XCTFail("Failed to create bitmap rep")
            return
        }

        rep.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)

        let bitmap = try XCTUnwrap(ImageEncoding.bitmapRepresentation(from: image))
        XCTAssertEqual(bitmap.pixelsWide, pixelWidth)
        XCTAssertEqual(bitmap.pixelsHigh, pixelHeight)
        XCTAssertEqual(bitmap.size.width, pointSize.width, accuracy: 0.01)
        XCTAssertEqual(bitmap.size.height, pointSize.height, accuracy: 0.01)
    }
}

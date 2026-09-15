import XCTest
import AppKit
@testable import Zoomies

final class ImageEncodingTests: XCTestCase {
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

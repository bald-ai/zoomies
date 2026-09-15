import XCTest
import AppKit
@testable import Zoomies

final class ImageSafetyTests: XCTestCase {
    func testPixelCountReportsOverflowInsteadOfWrapping() {
        XCTAssertNil(ImageSafety.pixelCount(width: Int.max, height: 2))
        XCTAssertEqual(ImageSafety.pixelCount(width: 3200, height: 1800), 5_760_000)
    }

    func testPixelLengthRejectsNonFiniteAndOverflowingValues() {
        XCTAssertNil(ImageSafety.pixelLength(.infinity))
        XCTAssertNil(ImageSafety.pixelLength(.nan))
        XCTAssertNil(ImageSafety.pixelLength(-4))
        XCTAssertEqual(ImageSafety.pixelLength(12.4), 12)
    }

    func testStubPNGWithUnsafeDeclaredPixelAreaIsRejectedWithoutDecoding() throws {
        let stub = try XCTUnwrap(PNGMetadata.stubPNGDeclaringSize(width: 32_768, height: 32_768))
        XCTAssertLessThan(stub.count, 128)
        XCTAssertEqual(ImageSafety.inspectData(stub), .tooLarge)
        XCTAssertNil(ImageSafety.loadImageIfSafe(stub))
        XCTAssertNil(ImageSafety.makeBitmapRep(pixelsWide: 32_768, pixelsHigh: 32_768))
    }

    func testReasonableRetinaSizedPNGIsAccepted() throws {
        let png = try TestSupport.solidImagePNGData(width: 2048, height: 1536)
        XCTAssertEqual(ImageSafety.inspectData(png), .safe)
        XCTAssertNotNil(ImageSafety.loadImageIfSafe(png))
        XCTAssertNotNil(ImageSafety.makeBitmapRep(pixelsWide: 2048, pixelsHigh: 1536))
    }

    func testInspectFileBoundsSizeBeforeReadingContents() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let url = root.appendingPathComponent("huge.bin")
        try Data(repeating: 0x89, count: 64).write(to: url, options: .atomic)

        var limits = ImageSafetyLimits.runtime
        limits.maxFileBytes = 16
        XCTAssertEqual(ImageSafety.inspectFile(at: url, limits: limits), .tooLarge)
        XCTAssertNil(ImageSafety.boundedFileData(at: url, limits: limits))

        let resolved = WorkflowReopenMetadataLogic.resolve(fileURL: url, initialImage: nil, limits: limits)
        XCTAssertTrue(resolved.outerImageIsUnsafe)
        XCTAssertNil(resolved.image)
        XCTAssertNil(resolved.editorState)
    }

    func testUnsafeOuterStubPNGIsReportedRatherThanOpened() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let url = root.appendingPathComponent("declared-huge.png")
        let stub = try XCTUnwrap(PNGMetadata.stubPNGDeclaringSize(width: 100_000, height: 100_000))
        try stub.write(to: url, options: .atomic)

        XCTAssertEqual(ImageSafety.inspectFile(at: url), .tooLarge)
        let resolved = WorkflowReopenMetadataLogic.resolve(fileURL: url, initialImage: nil)
        XCTAssertTrue(resolved.outerImageIsUnsafe)
        XCTAssertNil(resolved.image)
        XCTAssertNil(ImageSafety.loadImageIfSafe(stub))
    }

    func testInvalidLegacyOriginalFallsBackToSafeVisiblePNG() throws {
        let visible = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemRed)
        let unsafeOriginal = try XCTUnwrap(PNGMetadata.stubPNGDeclaringSize(width: 40_000, height: 40_000))
        let embedded = try XCTUnwrap(
            PNGMetadata.embed(intoPNG: visible, originalPNG: unsafeOriginal, prompt: "legacy")
        )

        XCTAssertNil(PNGMetadata.extract(fromPNG: embedded))
        let resolved = WorkflowReopenMetadataLogic.resolve(fileData: embedded)
        XCTAssertFalse(resolved.outerImageIsUnsafe)
        XCTAssertNil(resolved.editorState)
        XCTAssertEqual(resolved.cleanOriginalPNG, embedded)
        XCTAssertNil(resolved.prompt)
    }

    func testOversizedLegacyOriginalChunkIsRejectedWithInjectableLimits() throws {
        let visible = try TestSupport.solidImagePNGData(width: 24, height: 16)
        let original = try TestSupport.solidImagePNGData(width: 20, height: 12)
        let embedded = try XCTUnwrap(
            PNGMetadata.embed(intoPNG: visible, originalPNG: original, prompt: "keep")
        )

        var limits = ImageSafetyLimits.runtime
        limits.maxOriginalPNGChunkBytes = 8
        XCTAssertNil(PNGMetadata.extract(fromPNG: embedded, limits: limits))

        let resolved = WorkflowReopenMetadataLogic.resolve(fileData: embedded, limits: limits)
        XCTAssertFalse(resolved.outerImageIsUnsafe)
        XCTAssertEqual(resolved.cleanOriginalPNG, embedded)
    }

    func testAnnotationsThatWouldCreateUnsafeExportBoundsAreRejected() throws {
        let visible = try TestSupport.solidImagePNGData(width: 32, height: 24, color: .systemBlue)
        let base = try TestSupport.solidImagePNGData(width: 32, height: 24, color: .systemBlue)
        var limits = ImageSafetyLimits.runtime
        limits.maxExportPixelArea = 200
        limits.maxDecodedPixels = 50_000
        limits.maxDimension = 2_000
        limits.maxAbsoluteCoordinate = 2_000

        let state = EditorCanvasState(
            baseImagePNG: base,
            items: [
                .text(.init(text: String(repeating: "W", count: 80),
                            origin: .init(NSPoint(x: 0, y: 0)),
                            color: .init(.systemRed),
                            fontSize: 20))
            ]
        )
        XCTAssertFalse(state.isSafeToRestore(limits: limits))

        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: visible, editorState: state))
        XCTAssertNil(PNGMetadata.extractEditorState(fromPNG: embedded, limits: limits))

        let resolved = WorkflowReopenMetadataLogic.resolve(fileData: embedded, limits: limits)
        XCTAssertFalse(resolved.outerImageIsUnsafe)
        XCTAssertNil(resolved.editorState)
        XCTAssertEqual(resolved.cleanOriginalPNG, embedded)
    }

    func testDefensiveBitmapGuardRejectsUnsafeAreaEvenIfCallerSkipsValidation() {
        XCTAssertNil(ImageSafety.makeBitmapRep(pixelsWide: 16_384, pixelsHigh: 16_384))
        XCTAssertNil(ImageSafety.makeBitmapRep(pixelsWide: 10_000, pixelsHigh: 10_000))
        XCTAssertNotNil(ImageSafety.makeBitmapRep(pixelsWide: 128, pixelsHigh: 64))
    }
}

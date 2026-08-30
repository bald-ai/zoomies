import XCTest
import AppKit
@testable import Zoomies

final class PNGMetadataTests: XCTestCase {
    func testEmbedThenExtractRoundTripsOriginalAndPrompt() throws {
        let burned = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemRed)
        let original = try TestSupport.solidImagePNGData(width: 30, height: 15, color: .systemBlue)
        let prompt = "Make the button bigger 🚀 with ünicode"

        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: burned, originalPNG: original, prompt: prompt))
        XCTAssertTrue(PNGMetadata.isPNG(embedded))

        // The embedded result is still a usable PNG of the burned image.
        let reloaded = try XCTUnwrap(NSImage(data: embedded))
        XCTAssertGreaterThan(reloaded.size.width, 0)

        let extracted = try XCTUnwrap(PNGMetadata.extract(fromPNG: embedded))
        XCTAssertEqual(extracted.originalPNG, original, "Embedded original bytes must round-trip exactly.")
        XCTAssertEqual(extracted.prompt, prompt, "Prompt text (incl. unicode) must round-trip exactly.")
    }

    func testEmbedThenExtractRoundTripsEditorState() throws {
        let output = try TestSupport.solidImagePNGData(width: 60, height: 30, color: .systemRed)
        let base = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemBlue)
        let state = EditorCanvasState(
            baseImagePNG: base,
            items: [
                .arrow(start: .init(NSPoint(x: 3, y: 4)),
                       end: .init(NSPoint(x: 30, y: 12)),
                       color: .init(.systemRed),
                       lineWidth: 4),
                .text(.init(text: "Editable",
                            origin: .init(NSPoint(x: 6, y: 7)),
                            color: .init(.systemBlue),
                            fontSize: 24))
            ]
        )

        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: output, editorState: state))
        let extracted = try XCTUnwrap(PNGMetadata.extractEditorState(fromPNG: embedded))

        XCTAssertEqual(extracted.baseImagePNG, base)
        XCTAssertEqual(extracted.items, state.items)
    }

    func testEmbedOriginalPromptCanAlsoCarryEditorState() throws {
        let burned = try TestSupport.solidImagePNGData(width: 60, height: 30, color: .systemRed)
        let original = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemBlue)
        let state = EditorCanvasState(baseImagePNG: original,
                                      items: [.erase(rect: .init(NSRect(x: 1, y: 2, width: 3, height: 4)))])

        let embedded = try XCTUnwrap(
            PNGMetadata.embed(intoPNG: burned, originalPNG: original, prompt: "note", editorState: state)
        )

        let note = try XCTUnwrap(PNGMetadata.extract(fromPNG: embedded))
        let extractedState = try XCTUnwrap(PNGMetadata.extractEditorState(fromPNG: embedded))
        XCTAssertEqual(note.originalPNG, original)
        XCTAssertEqual(note.prompt, "note")
        XCTAssertEqual(extractedState.items, state.items)
    }

    func testExtractReturnsNilWhenChunksMissing() throws {
        let plain = try TestSupport.solidImagePNGData(width: 20, height: 20)
        XCTAssertNil(PNGMetadata.extract(fromPNG: plain))
    }

    func testEmbedReturnsNilForNonPNGContainer() throws {
        let original = try TestSupport.solidImagePNGData(width: 10, height: 10)
        let notPNG = Data("this is not a png".utf8)
        XCTAssertNil(PNGMetadata.embed(intoPNG: notPNG, originalPNG: original, prompt: "x"))
    }

    func testEmbedReturnsNilWhenOriginalIsNotPNG() throws {
        let burned = try TestSupport.solidImagePNGData(width: 10, height: 10)
        let notPNG = Data("nope".utf8)
        XCTAssertNil(PNGMetadata.embed(intoPNG: burned, originalPNG: notPNG, prompt: "x"))
    }

    func testExtractReturnsNilForNonPNG() {
        XCTAssertNil(PNGMetadata.extract(fromPNG: Data("definitely not a png".utf8)))
    }

    func testIsPNGDetectsSignature() throws {
        let png = try TestSupport.solidImagePNGData(width: 8, height: 8)
        XCTAssertTrue(PNGMetadata.isPNG(png))
        XCTAssertFalse(PNGMetadata.isPNG(Data([0x00, 0x01, 0x02])))
        XCTAssertFalse(PNGMetadata.isPNG(Data()))
    }

    func testPixelDimensionsReadsIHDRWithoutDecodingBitmap() throws {
        let png = try TestSupport.solidImagePNGData(width: 40, height: 20)
        let dimensions = try XCTUnwrap(PNGMetadata.pixelDimensions(ofPNG: png))
        XCTAssertGreaterThan(dimensions.width, 0)
        XCTAssertGreaterThan(dimensions.height, 0)
        XCTAssertLessThanOrEqual(dimensions.width, Int(EditorCanvasState.SafetyLimits.runtime.maxDimension))
        XCTAssertLessThanOrEqual(dimensions.height, Int(EditorCanvasState.SafetyLimits.runtime.maxDimension))
    }

    func testExtractEditorStateRejectsNonFiniteAndExtremeGeometry() throws {
        let output = try TestSupport.solidImagePNGData(width: 40, height: 20)
        let base = try TestSupport.solidImagePNGData(width: 40, height: 20)

        var nanState = EditorCanvasState(
            baseImagePNG: base,
            items: [.arrow(start: .init(NSPoint(x: 1, y: 2)),
                           end: .init(NSPoint(x: 3, y: 4)),
                           color: .init(.systemRed),
                           lineWidth: 4)]
        )
        nanState.items = [.arrow(start: EditorCanvasState.Point(NSPoint(x: CGFloat.nan, y: 2)),
                                 end: .init(NSPoint(x: 3, y: 4)),
                                 color: .init(.systemRed),
                                 lineWidth: 4)]
        XCTAssertFalse(nanState.isSafeToRestore())

        let extreme = EditorCanvasState(
            baseImagePNG: base,
            items: [.arrow(start: .init(NSPoint(x: 2_000_000, y: 2)),
                           end: .init(NSPoint(x: 3, y: 4)),
                           color: .init(.systemRed),
                           lineWidth: 4)]
        )
        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: output, editorState: extreme))
        XCTAssertNil(PNGMetadata.extractEditorState(fromPNG: embedded))
    }

    func testExtractEditorStateRejectsTooManyItemsAndOversizedChunks() throws {
        let output = try TestSupport.solidImagePNGData(width: 40, height: 20)
        let base = try TestSupport.solidImagePNGData(width: 40, height: 20)
        let state = EditorCanvasState(
            baseImagePNG: base,
            items: [
                .erase(rect: .init(NSRect(x: 1, y: 2, width: 3, height: 4))),
                .erase(rect: .init(NSRect(x: 5, y: 6, width: 7, height: 8)))
            ]
        )
        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: output, editorState: state))

        var itemLimits = EditorCanvasState.SafetyLimits.runtime
        itemLimits.maxItemCount = 1
        XCTAssertFalse(state.isSafeToRestore(limits: itemLimits))
        XCTAssertNil(PNGMetadata.extractEditorState(fromPNG: embedded, limits: itemLimits))

        var chunkLimits = EditorCanvasState.SafetyLimits.runtime
        chunkLimits.maxEditorStateChunkBytes = 16
        XCTAssertNil(PNGMetadata.extractEditorState(fromPNG: embedded, limits: chunkLimits))
    }

    func testExtractEditorStateRejectsOversizedEmbeddedImages() throws {
        let output = try TestSupport.solidImagePNGData(width: 40, height: 20)
        let base = try TestSupport.solidImagePNGData(width: 40, height: 20)
        let state = EditorCanvasState(baseImagePNG: base, items: [])
        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: output, editorState: state))

        var limits = EditorCanvasState.SafetyLimits.runtime
        limits.maxEmbeddedImageBytes = 8
        XCTAssertFalse(state.isSafeToRestore(limits: limits))
        XCTAssertNil(PNGMetadata.extractEditorState(fromPNG: embedded, limits: limits))
    }

    func testInvalidEditorMetadataFallsBackToFlattenedVisibleImage() throws {
        let burned = try TestSupport.solidImagePNGData(width: 60, height: 30, color: .systemRed)
        let original = try TestSupport.solidImagePNGData(width: 40, height: 20, color: .systemBlue)
        let invalidState = EditorCanvasState(
            baseImagePNG: original,
            items: [.arrow(start: .init(NSPoint(x: 2_000_000, y: 1)),
                           end: .init(NSPoint(x: 2, y: 3)),
                           color: .init(.systemRed),
                           lineWidth: 4)]
        )
        let embedded = try XCTUnwrap(
            PNGMetadata.embed(intoPNG: burned, originalPNG: original, prompt: "keep me", editorState: invalidState)
        )

        XCTAssertNil(PNGMetadata.extractEditorState(fromPNG: embedded))
        let resolved = WorkflowReopenMetadataLogic.resolve(fileData: embedded)
        XCTAssertNil(resolved.editorState)
        XCTAssertEqual(resolved.prompt, "keep me")
        XCTAssertEqual(resolved.cleanOriginalPNG, original)
        let image = try XCTUnwrap(resolved.image)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testEditorCanvasIgnoresUnsafeInitialState() throws {
        let basePNG = try TestSupport.solidImagePNGData(width: 100, height: 80)
        let unsafe = EditorCanvasState(
            baseImagePNG: basePNG,
            items: [.arrow(start: .init(NSPoint(x: CGFloat.infinity, y: 30)),
                           end: .init(NSPoint(x: 70, y: 30)),
                           color: .init(.systemRed),
                           lineWidth: 4)]
        )
        let canvas = EditorCanvasView(
            image: TestSupport.solidImage(width: 100, height: 80),
            initialState: unsafe
        )
        XCTAssertEqual(canvas.editableState()?.items.count ?? 0, 0)
    }
}

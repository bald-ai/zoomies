import XCTest
import AppKit
@testable import Zoomies

final class WorkflowNoteRendererTests: XCTestCase {
    func testBurnRejectsMissingBitmapAndOversizedOutputBeforeAllocation() throws {
        XCTAssertNil(WorkflowNoteRenderer.burn(note: "note", into: NSImage(size: .zero)))
        // A one-row fixture is cheap to allocate but exceeds the width budget.
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 17_000, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: NSSize(width: 17_000, height: 1))
        image.addRepresentation(rep)
        XCTAssertNil(WorkflowNoteRenderer.burn(note: "note", into: image))
    }

    func testPrepareNoteTextAppliesPrefixAndTrimRules() {
        var settings = Settings.default
        settings.notePrefixEnabled = true
        settings.notePrefix = "TODO"

        let note = WorkflowNoteRenderer.prepareNoteText("  hello world  ", settings: settings)

        XCTAssertEqual(note, WorkflowPreparedNote(identity: "hello world", rendered: "TODO hello world"))
    }

    func testPrepareNoteTextReturnsNilForBlankInput() {
        XCTAssertNil(WorkflowNoteRenderer.prepareNoteText("   ", settings: .default))
    }

    func testBurnAddsBottomNoteAreaAndMinimumWidth() throws {
        let image = TestSupport.solidImage(width: 120, height: 60, color: .systemBlue)

        let rendered = try XCTUnwrap(WorkflowNoteRenderer.burn(note: "Short note", into: image))

        XCTAssertEqual(rendered.size.width, 400, accuracy: 0.5)
        XCTAssertGreaterThan(rendered.size.height, 60)
    }

    func testBurnUsesReadableNoteHeightForPhoneScreenshots() throws {
        let image = TestSupport.solidImage(width: 1080, height: 2392, color: .systemBlue)

        let rendered = try XCTUnwrap(
            WorkflowNoteRenderer.burn(note: "Prompt for AI: make this text readable", into: image)
        )

        XCTAssertGreaterThan(rendered.size.height - image.size.height, 90)
    }
}

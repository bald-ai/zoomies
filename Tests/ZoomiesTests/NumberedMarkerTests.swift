import XCTest
import AppKit
import Carbon
@testable import Zoomies

final class NumberedMarkerTests: XCTestCase {
    private func keyEvent(keyCode: UInt16,
                          modifierFlags: NSEvent.ModifierFlags = [],
                          characters: String = "") throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown,
                                       location: .zero,
                                       modifierFlags: modifierFlags,
                                       timestamp: 0,
                                       windowNumber: 0,
                                       context: nil,
                                       characters: characters,
                                       charactersIgnoringModifiers: characters.lowercased(),
                                       isARepeat: false,
                                       keyCode: keyCode))
    }

    private func mouseEvent(type: NSEvent.EventType,
                            canvas: EditorCanvasView,
                            location: NSPoint,
                            clickCount: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type,
                                        location: canvas.convert(location, to: nil),
                                        modifierFlags: [],
                                        timestamp: 0,
                                        windowNumber: 0,
                                        context: nil,
                                        eventNumber: 0,
                                        clickCount: clickCount,
                                        pressure: 0))
    }

    private func click(_ canvas: EditorCanvasView, at point: NSPoint, clickCount: Int = 1) throws {
        try canvas.mouseDown(with: mouseEvent(type: .leftMouseDown, canvas: canvas,
                                              location: point, clickCount: clickCount))
        try canvas.mouseUp(with: mouseEvent(type: .leftMouseUp, canvas: canvas,
                                            location: point, clickCount: clickCount))
    }

    private func markerNumbers(_ canvas: EditorCanvasView) -> [Int] {
        (canvas.editableState()?.items ?? []).compactMap { item -> Int? in
            guard case .marker(let marker) = item else { return nil }
            return marker.number
        }
    }

    private func markerItems(_ canvas: EditorCanvasView) throws -> [EditorCanvasState.Marker] {
        try XCTUnwrap(canvas.editableState()).items.compactMap { item -> EditorCanvasState.Marker? in
            guard case .marker(let marker) = item else { return nil }
            return marker
        }
    }

    func testMarkerToolIsSelectedByF() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        var selectedTool: EditorTool?
        canvas.onKeyCommand = { command in
            if case .selectTool(let tool) = command {
                selectedTool = tool
            }
        }

        canvas.keyDown(with: try keyEvent(keyCode: UInt16(kVK_ANSI_F), characters: "f"))

        XCTAssertEqual(selectedTool, .marker)
    }

    func testEscapeExitsMarkerToolAndPreservesPlacedMarkers() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 30, y: 25))
        try click(canvas, at: NSPoint(x: 70, y: 50))
        let before = try markerItems(canvas)
        var selectedTool: EditorTool?
        var finalActions: [ScreenshotFinalAction] = []
        var cursorInvalidations = 0
        canvas.onMarkerCursorInvalidation = { cursorInvalidations += 1 }
        canvas.onKeyCommand = { command in
            switch command {
            case .selectTool(let tool): selectedTool = tool
            case .finalAction(let action): finalActions.append(action)
            default: break
            }
        }

        canvas.keyDown(with: try keyEvent(keyCode: 53))

        XCTAssertEqual(canvas.currentTool, .pen)
        XCTAssertEqual(selectedTool, .pen, "The toolbar must follow the canvas tool")
        XCTAssertGreaterThan(cursorInvalidations, 0)
        XCTAssertEqual(try markerItems(canvas), before)
        XCTAssertTrue(finalActions.isEmpty)

        canvas.keyDown(with: try keyEvent(keyCode: 53))
        XCTAssertEqual(finalActions, [.deleteOnly], "A second Escape follows the normal exit behavior")
    }

    func testEscapeExitsMarkerToolBeforePlacement() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        canvas.onKeyCommand = { command in
            if case .finalAction = command { XCTFail("Escape should only exit the marker tool") }
        }

        canvas.keyDown(with: try keyEvent(keyCode: 53))

        XCTAssertEqual(canvas.currentTool, .pen)
        XCTAssertTrue(markerNumbers(canvas).isEmpty)
    }

    func testEscapeClosesColorPickerBeforeExitingMarkerTool() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        canvas.isColorPickerOpen = true
        var closedColorPicker = false
        canvas.onKeyCommand = { command in
            if case .colorPickerClose = command { closedColorPicker = true }
            else { XCTFail("Escape should close the color picker first") }
        }

        canvas.keyDown(with: try keyEvent(keyCode: 53))

        XCTAssertTrue(closedColorPicker)
        XCTAssertEqual(canvas.currentTool, .marker)
    }

    func testClickingPlacesSequentiallyNumberedMarkersInCurrentColor() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setColor(.systemBlue)
        canvas.setTool(.marker)

        try click(canvas, at: NSPoint(x: 30, y: 25))
        try click(canvas, at: NSPoint(x: 70, y: 50))
        try click(canvas, at: NSPoint(x: 110, y: 25))

        XCTAssertEqual(markerNumbers(canvas), [1, 2, 3])
        let markers = try markerItems(canvas)
        XCTAssertEqual(markers.map { $0.color }, Array(repeating: EditorCanvasState.Color(.systemBlue), count: 3))
        XCTAssertEqual(markers[1].center, EditorCanvasState.Point(NSPoint(x: 70, y: 50)))
    }

    func testClickingExistingMarkerDoesNotPlaceAnother() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 40, y: 40))
        XCTAssertEqual(markerNumbers(canvas), [1])

        // A single click on the marker selects it for dragging instead of
        // stacking a new marker on top.
        try click(canvas, at: NSPoint(x: 40, y: 40))
        XCTAssertEqual(markerNumbers(canvas), [1])
    }

    func testMarkerDragMovesItWithUndoSupport() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 40, y: 40))

        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, canvas: canvas,
                                              location: NSPoint(x: 40, y: 40)))
        canvas.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, canvas: canvas,
                                                 location: NSPoint(x: 60, y: 55)))
        canvas.mouseUp(with: try mouseEvent(type: .leftMouseUp, canvas: canvas,
                                            location: NSPoint(x: 60, y: 55)))

        var markers = try markerItems(canvas)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].center, EditorCanvasState.Point(NSPoint(x: 60, y: 55)))

        canvas.undo()
        markers = try markerItems(canvas)
        XCTAssertEqual(markers[0].center, EditorCanvasState.Point(NSPoint(x: 40, y: 40)))
    }

    func testSelectionToolSelectsMovesAndDeletesMarker() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 40, y: 40))

        canvas.setTool(.selection)
        XCTAssertTrue(canvas.selectEditableItem(at: NSPoint(x: 40, y: 40)))

        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, canvas: canvas,
                                              location: NSPoint(x: 40, y: 40)))
        canvas.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, canvas: canvas,
                                                 location: NSPoint(x: 60, y: 50)))
        canvas.mouseUp(with: try mouseEvent(type: .leftMouseUp, canvas: canvas,
                                            location: NSPoint(x: 60, y: 50)))
        let markers = try markerItems(canvas)
        XCTAssertEqual(markers[0].center, EditorCanvasState.Point(NSPoint(x: 60, y: 50)))

        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, canvas: canvas,
                                              location: NSPoint(x: 60, y: 50)))
        canvas.keyDown(with: try keyEvent(keyCode: 51))
        XCTAssertEqual(try markerItems(canvas).count, 0)
    }

    func testDeletingMarkerDoesNotRenumberOthers() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 20, y: 20))
        try click(canvas, at: NSPoint(x: 50, y: 20))
        try click(canvas, at: NSPoint(x: 80, y: 20))
        XCTAssertEqual(markerNumbers(canvas), [1, 2, 3])

        canvas.setTool(.selection)
        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, canvas: canvas,
                                              location: NSPoint(x: 50, y: 20)))
        canvas.keyDown(with: try keyEvent(keyCode: 51))
        XCTAssertEqual(markerNumbers(canvas), [1, 3])

        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 50, y: 60))
        XCTAssertEqual(markerNumbers(canvas), [1, 3, 4])
    }

    func testNextNumberSurvivesToolSwitching() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 20, y: 20))

        canvas.setTool(.pen)
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 60, y: 20))

        XCTAssertEqual(markerNumbers(canvas), [1, 2])
    }

    func testUndoingPlacementReusesTheNumber() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 20, y: 20))
        try click(canvas, at: NSPoint(x: 60, y: 20))
        XCTAssertEqual(markerNumbers(canvas), [1, 2])

        canvas.undo()
        XCTAssertEqual(markerNumbers(canvas), [1])

        try click(canvas, at: NSPoint(x: 80, y: 20))
        XCTAssertEqual(markerNumbers(canvas), [1, 2])
    }

    func testClearAllResetsNumbering() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 20, y: 20))
        try click(canvas, at: NSPoint(x: 60, y: 20))

        canvas.clearAll()
        try click(canvas, at: NSPoint(x: 40, y: 40))

        XCTAssertEqual(markerNumbers(canvas), [1])
    }

    func testMarkerDiameterMatchesTextFontSizeAtSameZoom() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))

        // Commit a text item through the normal inline-editor flow so its
        // fontSize records the text sizing at this zoom.
        canvas.setTool(.text)
        try click(canvas, at: NSPoint(x: 20, y: 20))
        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        editor.string = "A"
        editor.keyDown(with: try keyEvent(keyCode: 36, characters: "\r"))

        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 60, y: 20))

        let state = try XCTUnwrap(canvas.editableState())
        var textSize: CGFloat?
        var markerDiameter: CGFloat?
        for item in state.items {
            if case .text(let text) = item { textSize = text.fontSize }
            if case .marker(let marker) = item { markerDiameter = marker.diameter }
        }
        XCTAssertEqual(try XCTUnwrap(markerDiameter), try XCTUnwrap(textSize))
    }

    func testRepeatedMarkerClicksNeverEditOrDuplicateAndDoNotAddUndoSteps() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        let point = NSPoint(x: 40, y: 40)
        try click(canvas, at: point)
        for count in [1, 2, 3, 2] {
            try click(canvas, at: point, clickCount: count)
            XCTAssertFalse(canvas.subviews.contains { $0 is NSTextView })
            XCTAssertEqual(markerNumbers(canvas), [1])
        }
        canvas.undo()
        XCTAssertEqual(markerNumbers(canvas), [], "Repeated clicks must not create undo steps")
        canvas.redo()
        XCTAssertEqual(markerNumbers(canvas), [1])
    }

    func testReopenedStateContinuesBeyondExistingMax() throws {
        let basePNG = try TestSupport.solidImagePNGData(width: 100, height: 80)
        let state = EditorCanvasState(baseImagePNG: basePNG, items: [
            .marker(.init(number: 3,
                          center: .init(NSPoint(x: 30, y: 30)),
                          color: .init(.systemRed),
                          diameter: 24)),
            .marker(.init(number: 7,
                          center: .init(NSPoint(x: 70, y: 30)),
                          color: .init(.systemRed),
                          diameter: 24))
        ])
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80),
                                      initialState: state)

        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 50, y: 60))

        XCTAssertEqual(markerNumbers(canvas), [3, 7, 8])
    }

    func testMarkerMetadataRoundTripsThroughPNG() throws {
        let basePNG = try TestSupport.solidImagePNGData(width: 100, height: 80)
        let state = EditorCanvasState(baseImagePNG: basePNG, items: [
            .marker(.init(number: 12,
                          center: .init(NSPoint(x: 40, y: 40)),
                          color: .init(.systemGreen),
                          diameter: 30))
        ])

        let output = try TestSupport.solidImagePNGData(width: 120, height: 90, color: .systemRed)
        let embedded = try XCTUnwrap(PNGMetadata.embed(intoPNG: output, editorState: state))
        let extracted = try XCTUnwrap(PNGMetadata.extractEditorState(fromPNG: embedded))

        XCTAssertEqual(extracted.items, state.items)

        // Restoring into a canvas keeps the marker editable and numbered.
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80),
                                      initialState: extracted)
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 70, y: 60))
        XCTAssertEqual(markerNumbers(canvas), [12, 13])
    }

    func testMarkerSafetyRejectsNonPositiveNumbers() throws {
        let basePNG = try TestSupport.solidImagePNGData(width: 100, height: 80)
        let state = EditorCanvasState(baseImagePNG: basePNG, items: [
            .marker(.init(number: 0,
                          center: .init(NSPoint(x: 40, y: 40)),
                          color: .init(.systemRed),
                          diameter: 24))
        ])
        XCTAssertFalse(state.isSafeToRestore())

        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80),
                                      initialState: state)
        XCTAssertEqual(canvas.editableState()?.items.count ?? 0, 0)
    }

    func testMultiDigitMarkerBoundsGrowWithoutClipping() throws {
        let oneDigit = EditorDrawing.MarkerItem(number: 4,
                                                center: .zero,
                                                color: .systemRed,
                                                diameter: 40)
        let threeDigit = EditorDrawing.MarkerItem(number: 123,
                                                  center: .zero,
                                                  color: .systemRed,
                                                  diameter: 40)

        let circle = EditorImageRenderer.markerRect(for: oneDigit)
        XCTAssertEqual(circle.width, circle.height, "Single-digit markers are circles")

        let capsule = EditorImageRenderer.markerRect(for: threeDigit)
        XCTAssertGreaterThan(capsule.width, circle.width, "Multi-digit markers widen instead of clipping")
        XCTAssertEqual(capsule.height, circle.height)

        // The rendered numeral must fit inside the capsule's horizontal extent.
        let font = EditorImageRenderer.markerFont(forDiameter: 40)
        let labelWidth = ("123" as NSString).size(withAttributes: [.font: font]).width
        XCTAssertLessThanOrEqual(labelWidth, capsule.width)
    }

    // Switching to a different tool while an inline editor is open must commit
    // it; the editor is owned by the tool that spawned it, so the check is
    // owner-aware rather than a fixed tool list.
    func testSwitchingFromTextToMarkerCommitsTextEditor() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.text)
        try click(canvas, at: NSPoint(x: 30, y: 30))
        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        editor.string = "hello"

        canvas.setTool(.marker)

        XCTAssertFalse(canvas.subviews.contains { $0 is NSTextView })
        XCTAssertEqual(canvas.editableState()?.items.count, 1)
        guard case .text(let text) = canvas.editableState()?.items.first else {
            return XCTFail("Committed editor content should produce a text item")
        }
        XCTAssertEqual(text.text, "hello")
    }

    func testReselectingOwningToolKeepsInlineEditor() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.text)
        try click(canvas, at: NSPoint(x: 30, y: 30))
        XCTAssertTrue(canvas.subviews.contains { $0 is NSTextView })

        canvas.setTool(.text)
        XCTAssertTrue(canvas.subviews.contains { $0 is NSTextView },
                      "Re-selecting the owning tool must not tear down the editor")
        // Escape goes to the editor (it owns the key event while open).
        let textEditor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        textEditor.keyDown(with: try keyEvent(keyCode: 53))


    }

    func testCursorInvalidationFiresOnNumberMutationsAndColorWrites() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        var invalidations = 0
        canvas.onMarkerCursorInvalidation = { invalidations += 1 }
        invalidations = 0

        // Direct property write is what the palette shortcut path uses.
        canvas.currentColor = .systemBlue
        XCTAssertEqual(invalidations, 1, "Assigning currentColor (palette path) must refresh the preview")

        try click(canvas, at: NSPoint(x: 40, y: 40))
        XCTAssertEqual(invalidations, 2, "Placement must refresh the preview")

        canvas.undo()
        XCTAssertEqual(invalidations, 3, "Undo must refresh the preview")

        canvas.redo()
        XCTAssertEqual(invalidations, 4, "Redo must refresh the preview")

        // Selection-tool deletion of a marker also changes the next number.
        canvas.setTool(.selection)
        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, canvas: canvas,
                                              location: NSPoint(x: 40, y: 40)))
        let beforeDelete = invalidations
        canvas.keyDown(with: try keyEvent(keyCode: 51))
        XCTAssertGreaterThan(invalidations, beforeDelete, "Item deletion must refresh the preview")

        canvas.clearAll()
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 40, y: 40))
        let beforeClear = invalidations
        canvas.clearAll()
        XCTAssertGreaterThan(invalidations, beforeClear, "Clear must refresh the preview")
    }

    func testMarkerNumberCapBoundsRestoredStateAndPlacement() throws {
        let basePNG = try TestSupport.solidImagePNGData(width: 100, height: 80)
        let cap = EditorDrawing.MarkerItem.maxNumber

        // A marker at the cap restores, but placement must be refused rather
        // than overflow or wrap.
        let atCap = EditorCanvasState(baseImagePNG: basePNG, items: [
            .marker(.init(number: cap,
                          center: .init(NSPoint(x: 40, y: 40)),
                          color: .init(.systemRed),
                          diameter: 24))
        ])
        XCTAssertTrue(atCap.isSafeToRestore())
        let cappedCanvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80),
                                            initialState: atCap)
        cappedCanvas.setTool(.marker)
        try click(cappedCanvas, at: NSPoint(x: 90, y: 70))
        XCTAssertEqual(markerNumbers(cappedCanvas), [cap], "Placement past the cap must be refused")

        // One below the cap continues to exactly the cap.
        let belowCap = EditorCanvasState(baseImagePNG: basePNG, items: [
            .marker(.init(number: cap - 1,
                          center: .init(NSPoint(x: 40, y: 40)),
                          color: .init(.systemRed),
                          diameter: 24))
        ])
        let belowCanvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80),
                                           initialState: belowCap)
        belowCanvas.setTool(.marker)
        try click(belowCanvas, at: NSPoint(x: 90, y: 70))
        XCTAssertEqual(markerNumbers(belowCanvas), [cap - 1, cap])
    }

    func testMarkerNumberAboveCapIsUnsafeAndDoesNotRestore() throws {
        let basePNG = try TestSupport.solidImagePNGData(width: 100, height: 80)
        for bad in [0, -3, EditorDrawing.MarkerItem.maxNumber + 1, Int.max] {
            let state = EditorCanvasState(baseImagePNG: basePNG, items: [
                .marker(.init(number: bad,
                              center: .init(NSPoint(x: 40, y: 40)),
                              color: .init(.systemRed),
                              diameter: 24))
            ])
            XCTAssertFalse(state.isSafeToRestore(), "number \(bad) must be rejected")
            let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80),
                                          initialState: state)
            XCTAssertEqual(canvas.editableState()?.items.count ?? 0, 0)
        }
    }

    // The cursor preview must occupy exactly the screen area the placed marker
    // will occupy: canvas bounds transformed by the live scroll magnification
    // (baseScale * userZoomFactor). Regression test for the preview rendering
    // at creation-zoom size with an arbitrary 16...64 clamp.
    func testCursorPreviewMatchesPlacedMarkerScreenBoundsAcrossMagnification() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 1000, height: 600))
        canvas.setTool(.marker)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = canvas

        // Place marker 1; the preview then depicts marker 2 — same single-digit
        // capsule width, so the placed bounds are the expected preview bounds.
        try click(canvas, at: NSPoint(x: 150, y: 120))
        guard case .marker(let placed) = canvas.editableState()?.items.last else {
            return XCTFail("expected a marker item")
        }
        let previewed = EditorDrawing.MarkerItem(number: placed.number + 1,
                                               center: placed.center.nsPoint,
                                               color: placed.color.nsColor,
                                               diameter: placed.diameter)
        let canvasBounds = EditorImageRenderer.markerBounds(for: previewed)

        for magnification in [CGFloat(0.25), 0.5, 1.0, 2.0] {
            scrollView.magnification = magnification
            XCTAssertEqual(scrollView.magnification, magnification, accuracy: 0.001,
                           "headless scroll view should store magnification")
            let size = canvas.markerPreviewScreenSize()
            XCTAssertEqual(size.width, canvasBounds.width * magnification, accuracy: 0.01,
                           "width mismatch at magnification \(magnification)")
            XCTAssertEqual(size.height, canvasBounds.height * magnification, accuracy: 0.01,
                           "height mismatch at magnification \(magnification)")
        }

        // No clamp: at 2x the preview must exceed the old 64pt ceiling for a
        // 40pt marker, and at 0.25 it must shrink below the old 16pt floor.
        scrollView.magnification = 2.0
        XCTAssertGreaterThan(canvas.markerPreviewScreenSize().width, 64)
        scrollView.magnification = 0.25
        XCTAssertLessThan(canvas.markerPreviewScreenSize().width, 16)
    }

    func testCursorPreviewInvalidatesWhenScrollMagnificationChanges() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 100, height: 80))
        canvas.setTool(.marker)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = canvas

        var invalidations = 0
        canvas.onMarkerCursorInvalidation = { invalidations += 1 }
        invalidations = 0

        scrollView.magnification = 0.5
        XCTAssertGreaterThan(invalidations, 0, "magnification change must refresh the preview")
        let before = invalidations
        scrollView.magnification = 2.0
        XCTAssertGreaterThan(invalidations, before, "further magnification must refresh again")
    }

    func testMarkerRendersTransparentInteriorWithColoredOutlineAndNumeral() throws {
        let canvas = EditorCanvasView(image: TestSupport.solidImage(width: 1000, height: 100, color: .systemBlue))
        canvas.setColor(.systemRed)
        canvas.setTool(.marker)
        try click(canvas, at: NSPoint(x: 60, y: 50))

        let composite = canvas.compositeImage()
        let rep = try XCTUnwrap(composite.representations.compactMap { $0 as? NSBitmapImageRep }.first)

        // Marker center in canvas (60,50) maps into the export crop, which
        // starts at the base image origin (canvasEdgeInset = 24). Diameter is
        // 40 (the curve’s reference size at 1000 units wide), so the radius is 20pt.
        let centerX = 60 - 24
        let centerY = 50 - 24
        func isBaseBlue(_ p: NSColor) -> Bool {
            p.blueComponent > 0.5 && p.redComponent < 0.4
        }
        func isMarkerRed(_ p: NSColor) -> Bool {
            p.redComponent > 0.8 && p.greenComponent < 0.4 && p.blueComponent < 0.4
        }

        var interiorShowsImage = false
        var interiorHasNumeral = false
        var outlineRingFound = false
        for dy in -24...24 {
            for dx in -24...24 {
                guard let pixel = rep.colorAt(x: centerX + dx, y: centerY + dy)?.usingColorSpace(.deviceRGB) else { continue }
                let distance = (CGFloat(dx * dx + dy * dy)).squareRoot()
                if distance < 12 {
                    if isBaseBlue(pixel) { interiorShowsImage = true }
                    if isMarkerRed(pixel) { interiorHasNumeral = true }
                } else if distance >= 16 && distance <= 21 {
                    if isMarkerRed(pixel) { outlineRingFound = true }
                }
            }
        }
        XCTAssertTrue(interiorShowsImage, "Marker interior must stay transparent and show the underlying image")
        XCTAssertTrue(interiorHasNumeral, "Marker numeral should render in the annotation color")
        XCTAssertTrue(outlineRingFound, "Marker outline ring should render in the annotation color")

        // Far outside the marker, the base image is untouched.
        let corner = try XCTUnwrap(rep.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
        XCTAssertTrue(isBaseBlue(corner))
    }
}

import AppKit
import Carbon
import XCTest
@testable import Zoomies

final class InkNoteModelTests: XCTestCase {
    private func line(from start: CGPoint, to end: CGPoint, steps: Int = 12) -> [InkPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return InkPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t, pressure: -1)
        }
    }

    func testStrokeEncodesCompactRoundedPoints() throws {
        let stroke = InkStroke(tool: .pen, color: "#ff3b30", width: 3.2,
                               points: [InkPoint(x: 1.234, y: 5.678, pressure: -1), InkPoint(x: 10, y: 2, pressure: 0.456)])
        let json = String(decoding: try JSONEncoder().encode(stroke), as: UTF8.self)
        XCTAssertTrue(json.contains("[1.2,5.7,-1,10,2,0.5]"), json)
        let decoded = try JSONDecoder().decode(InkStroke.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.points[0], InkPoint(x: 1.2, y: 5.7, pressure: -1))
        XCTAssertThrowsError(try JSONDecoder().decode(InkStroke.self, from: Data(##"{"tool":"pen","color":"#fff","width":3,"points":[1,2]}"##.utf8)))
    }

    func testOnlySaneVersion2NotesRestore() {
        var document = InkNoteDocument(note: "hello")
        XCTAssertTrue(document.isSafeToRestore)
        document.version = 1
        XCTAssertFalse(document.isSafeToRestore, "Notes from the old text-and-ink editor are not reopened as notes")
        document.version = 2
        document.markers = [.init(number: 0, x: 1, y: 1, color: "#fff")]
        XCTAssertFalse(document.isSafeToRestore)
        document.markers = [.init(number: 1, x: .infinity, y: 1, color: "#fff")]
        XCTAssertFalse(document.isSafeToRestore)
        document.markers = []
        document.note = String(repeating: "a", count: InkNoteDocument.maximumNoteLength + 1)
        XCTAssertFalse(document.isSafeToRestore)
        XCTAssertTrue(InkNoteDocument(note: " \n").isEmpty)
    }

    func testShapesMatchTheScreenshotEditorAndHitAlongTheirSides() {
        let start = CGPoint(x: 10, y: 10), end = CGPoint(x: 70, y: 30)
        let rectangle = InkShape.rectangle.points(from: start, to: end, constrained: false)
        XCTAssertEqual(rectangle, [CGPoint(x: 10, y: 10), CGPoint(x: 70, y: 10), CGPoint(x: 70, y: 30), CGPoint(x: 10, y: 30),
                                   CGPoint(x: 10, y: 10)])
        let square = InkShape.rectangle.points(from: end, to: start, constrained: true)
        XCTAssertEqual(square, [CGPoint(x: 10, y: -30), CGPoint(x: 70, y: -30), CGPoint(x: 70, y: 30), CGPoint(x: 10, y: 30),
                                CGPoint(x: 10, y: -30)],
                       "Shift makes a square from the start corner, in any direction")
        let circle = InkShape.ellipse.points(from: start, to: end, constrained: true)
        let xs = circle.map(\.x), ys = circle.map(\.y)
        XCTAssertEqual(xs.max()! - xs.min()!, ys.max()! - ys.min()!, accuracy: 0.01)
        let arrow = InkShape.arrow.points(from: start, to: end, constrained: false)
        XCTAssertEqual(arrow.last, end, "Arrows end on the tip")
        let wings = EditorImageRenderer.arrowHeadPoints(from: start, to: end)
        XCTAssertTrue(arrow.contains(wings.0) && arrow.contains(wings.1), "Same arrowhead as the screenshot editor")
        XCTAssertEqual(InkShape.line.points(from: start, to: end, constrained: true), [start, end])

        let stroke = InkStroke(tool: .shape, color: "#fff", width: 2.5,
                               points: rectangle.map { InkPoint(x: $0.x, y: $0.y, pressure: -1) })
        XCTAssertTrue(stroke.hits(CGPoint(x: 40, y: 11)), "The middle of a side has no point but still hits")
        XCTAssertFalse(stroke.hits(CGPoint(x: 40, y: 20)), "The inside of an outline does not")
        XCTAssertEqual(InkGeometry.path(for: stroke).boundingBoxOfPath, CGRect(x: 10, y: 10, width: 60, height: 20))
    }

    func testOutlineCoversTheStrokeWithItsWidth() {
        let points = line(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 210, y: 20), steps: 40)
        let box = InkGeometry.outline(points, width: 4).boundingBoxOfPath
        XCTAssertEqual(box.minX, 10, accuracy: 3)
        XCTAssertEqual(box.maxX, 210, accuracy: 3)
        XCTAssertLessThanOrEqual(box.height, 5)
        XCTAssertGreaterThan(box.height, 1)
        XCTAssertFalse(InkGeometry.outline([InkPoint(x: 5, y: 5, pressure: -1)], width: 4).isEmpty, "A tap still leaves a dot")
    }

    func testNoteDataRoundTripsThroughPNGChunks() throws {
        let png = try XCTUnwrap(TestSupport.solidImagePNGData())
        var document = InkNoteDocument(note: "Fix 1\n\n\n1: wider")
        document.items = [.init(stroke: InkStroke(tool: .shape, color: "#3a8dff", width: 2.5,
                                                  points: [InkPoint(x: 0, y: 0, pressure: -1), InkPoint(x: 40, y: 0, pressure: -1)]),
                                x: 3, y: 5)]
        document.markers = [.init(number: 1, x: 20, y: 30, color: "#ff3b30")]
        let first = try XCTUnwrap(PNGMetadata.embed(intoPNG: png, inkNote: document))
        let again = try XCTUnwrap(PNGMetadata.embed(intoPNG: first, inkNote: document))
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: again), document)
        XCTAssertEqual(again.count, first.count, "Saving again replaces the note chunk instead of stacking another")
        XCTAssertNil(PNGMetadata.extractInkNote(fromPNG: png))
    }
}

final class InkNoteRendererTests: XCTestCase {
    private func pixel(_ image: NSImage, x: CGFloat, y: CGFloat) throws -> NSColor {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.sRGB))
    }

    func testAnEmptyNoteHasNoPictureAndATextOnlyNoteIsJustTheNoteBox() throws {
        XCTAssertNil(InkNoteRenderer.image(for: InkNoteDocument(note: "  ")))
        let image = try XCTUnwrap(InkNoteRenderer.image(for: InkNoteDocument(note: "Ship it")))
        XCTAssertEqual(image.size.width, InkNoteRenderer.minimumWidth * InkNoteRenderer.scale)
        XCTAssertGreaterThan(image.size.height, 20)
        XCTAssertLessThan(image.size.height, 200, "No empty canvas above a text-only note")
    }

    func testTheDrawingIsCroppedWithAMarginAndTheNoteBurnedBelowIt() throws {
        var document = InkNoteDocument(note: "")
        document.items = [.init(stroke: InkStroke(tool: .shape, color: "#ffffff", width: 6,
                                                  points: [InkPoint(x: 0, y: 0, pressure: -1), InkPoint(x: 800, y: 0, pressure: -1)]),
                                x: 500, y: 400)]
        document.markers = [.init(number: 1, x: 900, y: 500, color: "#ff3b30")]
        let rect = try XCTUnwrap(InkNoteRenderer.canvasRect(for: document))
        XCTAssertEqual(rect.minX, 500 - 6 - InkNoteRenderer.margin, accuracy: 1, "Empty canvas left of the drawing is cropped")
        XCTAssertEqual(rect.minY, 400 - 6 - InkNoteRenderer.margin, accuracy: 1)
        let drawing = try XCTUnwrap(InkNoteRenderer.image(for: document))
        XCTAssertEqual(drawing.size.height, rect.height * InkNoteRenderer.scale)
        let scale = InkNoteRenderer.scale
        XCTAssertGreaterThan(try pixel(drawing, x: (900 - rect.minX) * scale, y: (400 - rect.minY) * scale).redComponent, 0.8,
                             "The stroke is drawn where it sits on the canvas")
        XCTAssertLessThan(try pixel(drawing, x: (900 - rect.minX) * scale, y: (440 - rect.minY) * scale).redComponent, 0.2)

        document.note = "1: wider field"
        let withNote = try XCTUnwrap(InkNoteRenderer.image(for: document))
        XCTAssertGreaterThan(withNote.size.height, drawing.size.height, "The Note box is burned in below the drawing")
        document.note = "1: wider field\n2: taller"
        let twoLines = try XCTUnwrap(InkNoteRenderer.image(for: document))
        XCTAssertGreaterThan(twoLines.size.height, withNote.size.height, "Each marker line gets its own line")
    }
}

final class InkNoteKeymapTests: XCTestCase {
    private func command(_ key: Int, _ chars: String = "", _ flags: NSEvent.ModifierFlags = []) -> InkNoteKeymap.Command? {
        InkNoteKeymap.command(keyCode: UInt16(key), characters: chars, flags: flags)
    }

    func testToolLettersMatchTheScreenshotEditorAndOtherLettersDoNothing() {
        let keys: [(Int, InkNoteKeymap.Command)] = [(kVK_ANSI_W, .tool(.pen)), (kVK_ANSI_D, .tool(.line)),
            (kVK_ANSI_A, .tool(.arrow)), (kVK_ANSI_R, .tool(.rectangle)), (kVK_ANSI_E, .tool(.ellipse)),
            (kVK_ANSI_F, .tool(.marker)), (kVK_ANSI_H, .tool(.highlighter)), (kVK_ANSI_X, .tool(.eraser)),
            (kVK_ANSI_Q, .nextColor)]
        for (key, expected) in keys {
            XCTAssertEqual(command(key, "other layout", .capsLock), expected)
            for flag: NSEvent.ModifierFlags in [.shift, .control, .option] {
                XCTAssertNil(command(key, "", flag))
            }
        }
        for key in [kVK_ANSI_K, kVK_ANSI_T, kVK_ANSI_P, kVK_ANSI_1, kVK_Space] {
            XCTAssertNil(command(key, "k"), "Letters without a tool do nothing")
        }
    }

    func testSessionKeysMatchTheScreenshotEditor() {
        let cases: [(Int, String, NSEvent.ModifierFlags, InkNoteKeymap.Command)] = [
            (kVK_Return, "\r", [], .save), (kVK_ANSI_KeypadEnter, "\u{3}", [], .save),
            (kVK_Return, "\r", .command, .copyAndSave), (kVK_Escape, "\u{1b}", [], .close),
            (kVK_Tab, "\t", .shift, .backToNote), (kVK_ANSI_Z, "z", .command, .undo),
            (kVK_ANSI_Z, "Z", [.command, .shift], .redo), (kVK_Delete, "", .option, .clearInk)
        ]
        for (key, chars, flags, expected) in cases {
            XCTAssertEqual(command(key, chars, flags), expected, "\(key) \(flags)")
        }
        XCTAssertNil(command(kVK_ANSI_S, "s", .command), "Saving is Enter, as in the screenshot editor")
        XCTAssertNil(command(kVK_ANSI_W, "w", .command))
        XCTAssertNil(command(kVK_Tab, "\t"))
    }
}

@MainActor
final class InkNoteEditorTests: XCTestCase {
    private func editor(_ document: InkNoteDocument = InkNoteDocument(note: "")) -> InkNoteWindowController {
        _ = NSApplication.shared
        let editor = InkNoteWindowController(noteDocument: document, title: "Note")
        editor.window?.layoutIfNeeded()
        return editor
    }

    private func mouse(_ editor: InkNoteWindowController, _ type: NSEvent.EventType, _ point: CGPoint,
                       clicks: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: editor.canvas.convert(point, to: nil), modifierFlags: [],
                                         timestamp: 0, windowNumber: editor.window?.windowNumber ?? 0, context: nil,
                                         eventNumber: 0, clickCount: clicks, pressure: 1))
    }

    private func drag(_ editor: InkNoteWindowController, from start: CGPoint, to end: CGPoint) throws {
        editor.canvasMouseDown(try mouse(editor, .leftMouseDown, start))
        editor.canvasMouseDragged(try mouse(editor, .leftMouseDragged, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)))
        editor.canvasMouseDragged(try mouse(editor, .leftMouseDragged, end))
        editor.canvasMouseUp(try mouse(editor, .leftMouseUp, end))
    }

    private func click(_ editor: InkNoteWindowController, _ point: CGPoint, clicks: Int = 1) throws {
        editor.canvasMouseDown(try mouse(editor, .leftMouseDown, point, clicks: clicks))
        editor.canvasMouseUp(try mouse(editor, .leftMouseUp, point, clicks: clicks))
    }

    func testShapesDrawOnTheCanvasAndAClickDrawsNothing() throws {
        let editor = editor()
        defer { editor.window?.close() }
        editor.perform(.tool(.rectangle))
        try click(editor, CGPoint(x: 100, y: 100))
        XCTAssertTrue(editor.noteDocument.items.isEmpty, "A click with a shape tool draws nothing")

        editor.perform(.tool(.arrow))
        try drag(editor, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 60))
        let item = try XCTUnwrap(editor.noteDocument.items.first)
        XCTAssertEqual(editor.noteDocument.items.count, 1)
        XCTAssertEqual(item.stroke.tool, .shape)
        XCTAssertEqual(item.stroke.points.count, 6, "One arrow from the last drag position, not a trail")
        XCTAssertEqual(item.x + item.stroke.bounds.maxX, 300, accuracy: 1, "Drawn where the mouse was")
        editor.perform(.undo)
        XCTAssertTrue(editor.noteDocument.items.isEmpty, "A shape is one undo step")
        editor.perform(.redo)
        XCTAssertEqual(editor.noteDocument.items.count, 1)
    }

    func testMarkersStampOnTheCanvasAndTheirNotesGoInTheNoteBox() throws {
        let editor = editor(InkNoteDocument(note: "Login page"))
        defer { editor.window?.close() }
        editor.perform(.tool(.marker))
        try click(editor, CGPoint(x: 120, y: 80))
        try click(editor, CGPoint(x: 400, y: 200))
        XCTAssertEqual(editor.noteDocument.markers.map(\.number), [1, 2])
        XCTAssertEqual(editor.noteDocument.markers[1].x, 400)

        try click(editor, CGPoint(x: 400, y: 200), clicks: 2)
        XCTAssertNotNil(editor.markerNotePopover, "Double-clicking a marker opens its note, as in the screenshot editor")
        XCTAssertEqual(editor.noteDocument.markers.count, 2, "Double-clicking a marker does not add another")
        editor.markerNotePopover?.close()
        editor.setMarkerNote(2, text: "wider field")
        XCTAssertEqual(editor.noteDocument.note, "Login page\n\n\n2: wider field")
        XCTAssertEqual(editor.noteBar.text, "Login page\n\n\n2: wider field")
        XCTAssertFalse(editor.noteBar.isHidden)

        editor.perform(.tool(.eraser))
        try click(editor, CGPoint(x: 400, y: 200))
        XCTAssertEqual(editor.noteDocument.markers.map(\.number), [1])
        XCTAssertEqual(editor.noteDocument.note, "Login page", "Erasing a marker removes its line")
        editor.perform(.undo)
        XCTAssertEqual(editor.noteDocument.markers.map(\.number), [1, 2])
        XCTAssertEqual(editor.noteDocument.note, "Login page\n\n\n2: wider field")

        editor.perform(.tool(.marker))
        try click(editor, CGPoint(x: 600, y: 300))
        XCTAssertEqual(editor.noteDocument.markers.last?.number, 3, "Numbers continue past the highest marker")
    }

    func testDraggingAMarkerMovesItInOneUndoStep() throws {
        let editor = editor()
        defer { editor.window?.close() }
        editor.perform(.tool(.marker))
        try click(editor, CGPoint(x: 100, y: 100))
        try drag(editor, from: CGPoint(x: 102, y: 101), to: CGPoint(x: 302, y: 201))
        XCTAssertEqual(editor.noteDocument.markers.count, 1)
        XCTAssertEqual(editor.noteDocument.markers[0].x, 300, accuracy: 0.01)
        XCTAssertEqual(editor.noteDocument.markers[0].y, 200, accuracy: 0.01)
        editor.perform(.undo)
        XCTAssertEqual(editor.noteDocument.markers[0].x, 100, accuracy: 0.01)
    }

    func testStrayLettersNeverChangeAnything() throws {
        let editor = editor()
        defer { editor.window?.close() }
        editor.perform(.tool(.rectangle))
        let before = editor.noteDocument
        let letter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_K)))
        XCTAssertFalse(editor.handleKey(letter))
        editor.canvas.keyDown(with: letter)
        XCTAssertEqual(editor.tool, .rectangle, "A stray letter keeps the tool")
        XCTAssertEqual(editor.noteDocument, before)
    }

    func testEditorActionsCarryTheCurrentNote() throws {
        let editor = editor(InkNoteDocument(note: "Hi"))
        defer { editor.window?.close() }
        var actions: [InkNoteWindowController.Action] = []
        editor.onAction = { actions.append($0) }
        editor.perform(.tool(.pen))
        try drag(editor, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 90))
        for command: InkNoteKeymap.Command in [.save, .copyAndSave, .backToNote, .close] { editor.perform(command) }
        let note = editor.noteDocument
        XCTAssertEqual(note.items.count, 1)
        XCTAssertEqual(actions, [.save(note), .copyAndSave(note), .backToNote(note), .close(note)])
        XCTAssertFalse(editor.windowShouldClose(try XCTUnwrap(editor.window)), "The close button asks the flow instead")
        XCTAssertEqual(actions.last, .close(note))
    }

    func testClearIsOneUndoStepAndDropsMarkerLines() throws {
        var document = InkNoteDocument(note: "Text\n\n\n1: one")
        document.markers = [.init(number: 1, x: 50, y: 50, color: "#ff3b30")]
        document.items = [.init(stroke: InkStroke(tool: .pen, color: "#fff", width: 3, points: [InkPoint(x: 0, y: 0, pressure: -1)]),
                                x: 10, y: 10)]
        let editor = editor(document)
        defer { editor.window?.close() }
        editor.perform(.clearInk)
        XCTAssertTrue(editor.noteDocument.items.isEmpty && editor.noteDocument.markers.isEmpty)
        XCTAssertEqual(editor.noteDocument.note, "Text")
        editor.perform(.undo)
        XCTAssertEqual(editor.noteDocument, document)
    }

    func testTheNoteBoxShowsTheNoteAndHidesWhenEmpty() {
        let empty = editor()
        defer { empty.window?.close() }
        XCTAssertTrue(empty.noteBar.isHidden)
        let note = editor(InkNoteDocument(note: "  Check the header  "))
        defer { note.window?.close() }
        XCTAssertFalse(note.noteBar.isHidden)
        XCTAssertEqual(note.noteBar.text, "Check the header")
    }

    func testNotesUseTheSettingsPaletteWithoutColorsLostOnTheDarkBackground() throws {
        XCTAssertEqual(InkNoteWindowController.noteColors(forPaletteIDs: EditorPalette.defaultIDs).map(\.id),
                       ["red", "blue", "green", "yellow", "white"], "Black is dropped from the default palette")
        XCTAssertEqual(InkNoteWindowController.noteColors(forPaletteIDs: ["purple", "black", "orange"]).map(\.id), ["purple", "orange"])
        XCTAssertEqual(InkNoteWindowController.noteColors(forPaletteIDs: ["black"]).map(\.id), ["white"])

        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        store.update { $0.editorColorIDs = ["cyan", "pink"] }
        let editor = InkNoteWindowController(noteDocument: InkNoteDocument(note: ""), title: "Note", settingsStore: store)
        defer { editor.window?.close() }
        XCTAssertEqual(editor.palette.map(\.id), ["cyan", "pink"])
        store.update { $0.editorColorIDs = ["pink", "white"] }
        XCTAssertEqual(editor.palette.map(\.id), ["pink", "white"], "Settings changes reach an open note")
        XCTAssertEqual(editor.colorHex, EditorPalette.available.first { $0.id == "pink" }?.hex)
    }

    func testEveryToolbarControlShowsItsShortcutAndTheToolbarFits() throws {
        let editor = editor()
        defer { editor.window?.close() }
        let window = try XCTUnwrap(editor.window)
        let host = try XCTUnwrap(window.contentView)
        func buttons(in view: NSView) -> [NSButton] {
            ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap(buttons)
        }
        let hinted = Set(editor.shortcutHints.map { ObjectIdentifier($0.view) })
        let toolbarButtons = buttons(in: host)
        XCTAssertEqual(toolbarButtons.filter { !($0 is InkSwatchButton) }.count, 14)
        for button in toolbarButtons {
            let tip = try XCTUnwrap(button.toolTip)
            XCTAssertTrue(tip.contains("(") && tip.contains(")"), "Tooltip names a shortcut: \(tip)")
            if !(button is InkSwatchButton) { XCTAssertTrue(hinted.contains(ObjectIdentifier(button)), tip) }
        }
        let bar = try XCTUnwrap((host.subviews.first as? NSStackView)?.arrangedSubviews.first as? NSStackView)
        XCTAssertLessThanOrEqual(bar.fittingSize.width, window.minSize.width)
        host.layoutSubtreeIfNeeded()
        for group in bar.arrangedSubviews where !group.subviews.isEmpty {
            XCTAssertEqual(group.frame.width, group.fittingSize.width, accuracy: 1, "Toolbar groups never stretch")
        }
    }

    func testShortcutBadgesSitUnderTheToolbarInsideTheWindow() throws {
        let editor = editor()
        defer { editor.window?.close() }
        let host = try XCTUnwrap(editor.window?.contentView)
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(editor.shortcutOverlay).makeView(in: host)
        XCTAssertEqual(view.subviews.count, editor.shortcutHints.count + 1)
        let help = try XCTUnwrap(view.subviews.last)
        XCTAssertTrue(view.bounds.contains(help.frame))
        let badges = view.subviews.dropLast()
        for (i, badge) in badges.enumerated() {
            XCTAssertTrue(view.bounds.contains(badge.frame))
            XCTAssertFalse(badge.frame.intersects(help.frame))
            for other in badges.dropFirst(i + 1) { XCTAssertFalse(badge.frame.intersects(other.frame)) }
        }
    }
}

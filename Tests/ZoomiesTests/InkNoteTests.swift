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

    func testMarkdownImportTurnsFootnotesIntoMarkerCircles() {
        let document = InkNoteDocument.fromMarkdown("Fix this[^1] now.\n\n[^1]: Wider field\n")
        XCTAssertEqual(document.text, "Fix this\u{FFFC} now.\n\n\u{FFFC} Wider field")
        XCTAssertEqual(document.markers, [.init(index: 8, number: 1), .init(index: 16, number: 1)])
        XCTAssertTrue(document.isSafeToRestore)
        XCTAssertEqual(InkNoteDocument.fromMarkdown("Plain\n").text, "Plain\n")
    }

    func testUnsafeDocumentsAreRejected() {
        var document = InkNoteDocument(text: "hello")
        document.anchors = [.init(index: 5, id: "a")]
        XCTAssertFalse(document.isSafeToRestore)
        document.anchors = []
        document.markers = [.init(index: 0, number: 1)]
        XCTAssertFalse(document.isSafeToRestore, "Markers must sit on attachment characters")
    }

    func testAnchorPointFollowsTheShapeOfTheStroke() {
        let loop = (0...20).map { i -> CGPoint in
            let t = CGFloat(i) / 20 * 2 * .pi
            return CGPoint(x: 100 + cos(t) * 40, y: 50 + sin(t) * 10)
        }
        XCTAssertEqual(InkAnchorLogic.anchorPoint(for: loop).x, 100, accuracy: 1)
        XCTAssertEqual(InkAnchorLogic.anchorPoint(for: [CGPoint(x: 90, y: 10), CGPoint(x: 10, y: 12)]), CGPoint(x: 10, y: 12))
        XCTAssertEqual(InkAnchorLogic.anchorPoint(for: [CGPoint(x: 200, y: 100), CGPoint(x: 150, y: 40)]), CGPoint(x: 150, y: 40))
    }

    func testWordStartAndStrokeJoining() {
        let text = "the old date format" as NSString
        XCTAssertEqual(InkAnchorLogic.wordStart(in: text, at: 10), 8)
        XCTAssertEqual(InkAnchorLogic.wordStart(in: text, at: 8), 8)
        XCTAssertEqual(InkAnchorLogic.wordStart(in: text, at: 0), 0)
        let shaft = CGRect(x: 0, y: 0, width: 60, height: 40)
        XCTAssertTrue(InkAnchorLogic.joinsPrevious(previous: shaft, next: CGRect(x: 65, y: 10, width: 10, height: 10), elapsed: 0.4))
        XCTAssertFalse(InkAnchorLogic.joinsPrevious(previous: shaft, next: CGRect(x: 65, y: 10, width: 10, height: 10), elapsed: 2))
        XCTAssertFalse(InkAnchorLogic.joinsPrevious(previous: shaft, next: CGRect(x: 120, y: 10, width: 10, height: 10), elapsed: 0.4))
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

    func testNoteDataRoundTripsThroughPNGChunks() throws {
        let png = try XCTUnwrap(TestSupport.solidImagePNGData())
        var document = InkNoteDocument(text: "hi \u{FFFC}", markers: [.init(index: 3, number: 2)], anchors: [.init(index: 0, id: "a")])
        document.items = [.init(stroke: InkStroke(tool: .highlighter, color: "#ffcc00", width: 17, points: [InkPoint(x: 0, y: 0, pressure: -1)]),
                                anchor: "a", x: -2, y: 4),
                          .init(stroke: InkStroke(tool: .shape, color: "#3a8dff", width: 2.5,
                                                  points: [InkPoint(x: 0, y: 0, pressure: -1), InkPoint(x: 40, y: 0, pressure: -1)]),
                                anchor: nil, x: 3, y: 5)]
        let first = try XCTUnwrap(PNGMetadata.embed(intoPNG: png, inkNote: document))
        let again = try XCTUnwrap(PNGMetadata.embed(intoPNG: first, inkNote: document))
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: again), document)
        XCTAssertEqual(again.count, first.count, "Saving again replaces the note chunk instead of stacking another")
        XCTAssertNil(PNGMetadata.extractInkNote(fromPNG: png))
    }
}

final class InkNoteKeymapTests: XCTestCase {
    private func command(_ key: Int, _ chars: String = "", _ flags: NSEvent.ModifierFlags = [],
                         drawing: Bool = false) -> InkNoteKeymap.Command? {
        InkNoteKeymap.command(keyCode: UInt16(key), characters: chars, flags: flags, isDrawing: drawing)
    }

    func testDrawingLettersMatchTheScreenshotEditorAndStayTextWhileTyping() {
        let keys: [(Int, InkNoteKeymap.Command)] = [(kVK_ANSI_W, .tool(.pen)), (kVK_ANSI_D, .tool(.line)),
            (kVK_ANSI_A, .tool(.arrow)), (kVK_ANSI_R, .tool(.rectangle)), (kVK_ANSI_E, .tool(.ellipse)),
            (kVK_ANSI_H, .tool(.highlighter)), (kVK_ANSI_X, .tool(.eraser)), (kVK_ANSI_Q, .nextColor), (kVK_ANSI_F, .marker)]
        for (key, expected) in keys {
            XCTAssertEqual(command(key, "other layout", .capsLock, drawing: true), expected)
            XCTAssertNil(command(key, "w"), "While typing, letters are text")
            for flag: NSEvent.ModifierFlags in [.shift, .control, .option] {
                XCTAssertNil(command(key, "", flag, drawing: true))
            }
        }
        for key in [kVK_ANSI_P, kVK_ANSI_1, kVK_ANSI_5, kVK_ANSI_T] {
            XCTAssertNil(command(key, "", drawing: true), "The old P / 1–5 / plain T keys are gone")
        }
    }

    func testCommandShortcutsAndSessionKeysMatchTheRestOfTheApp() {
        let cases: [(Int, String, NSEvent.ModifierFlags, InkNoteKeymap.Command)] = [
            (kVK_ANSI_S, "s", .command, .save), (kVK_Return, "\r", .command, .copyAndSave),
            (kVK_ANSI_KeypadEnter, "\u{3}", .command, .copyAndSave), (kVK_ANSI_W, "w", .command, .close),
            (kVK_Escape, "\u{1b}", [], .escape), (kVK_ANSI_Z, "z", .command, .undo),
            (kVK_ANSI_Z, "Z", [.command, .shift], .redo), (kVK_ANSI_D, "d", .command, .draw), (kVK_ANSI_T, "t", .command, .type),
            (kVK_ANSI_F, "f", .command, .marker), (kVK_ANSI_A, "a", .command, .selectAll),
            (kVK_ANSI_C, "c", .command, .copy), (kVK_ANSI_X, "x", .command, .cut), (kVK_ANSI_V, "v", .command, .paste)
        ]
        for (key, chars, flags, expected) in cases {
            XCTAssertEqual(command(key, chars, flags), expected, "\(key) \(flags)")
            XCTAssertEqual(command(key, chars, flags, drawing: true), expected, "\(key) \(flags) while drawing")
        }
        XCTAssertNil(command(kVK_Return, "\r"), "Return stays a newline")
        XCTAssertEqual(command(kVK_Delete, "", .option, drawing: true), .clearInk)
        XCTAssertNil(command(kVK_Delete, "", .option), "Option+Backspace still deletes a word while typing")
        XCTAssertNil(command(kVK_ANSI_C, "c", [.command, .shift]), "Command+Shift+C no longer copies the image")
    }
}

@MainActor
final class InkNoteEditorTests: XCTestCase {
    private func editor(_ markdown: String) throws -> (InkNoteWindowController, URL) {
        _ = NSApplication.shared
        let root = try TestSupport.makeTemporaryDirectory()
        let url = root.appendingPathComponent("plan.md")
        try Data(markdown.utf8).write(to: url)
        let editor = InkNoteWindowController(opened: try InkNoteWindowController.resolve(url))
        editor.window?.layoutIfNeeded()
        return (editor, root)
    }

    /// Lets the undo manager close its per-event group, as it would between real key presses.
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }

    private func rect(of text: String, in editor: InkNoteWindowController) -> CGRect {
        let range = (editor.textView.string as NSString).range(of: text)
        let manager = editor.textView.layoutManager!, container = editor.textView.textContainer!
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = editor.textView.textContainerOrigin
        return manager.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
    }

    private func circle(around rect: CGRect) -> InkStroke {
        let points = (0...24).map { i -> InkPoint in
            let t = CGFloat(i) / 24 * 2 * .pi
            return InkPoint(x: rect.midX + cos(t) * (rect.width / 2 + 8), y: rect.midY + sin(t) * (rect.height / 2 + 4), pressure: -1)
        }
        return InkStroke(tool: .pen, color: "#ff3b30", width: 3.2, points: points)
    }

    func testMarkdownOpensNextToItsNoteAndStartsClean() throws {
        let (editor, root) = try editor("Fix this[^1]\n\n[^1]: Wider\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        XCTAssertEqual(editor.noteURL.lastPathComponent, "plan.png")
        XCTAssertEqual(editor.textView.string, "Fix this\u{FFFC}\n\n\u{FFFC} Wider")
        XCTAssertFalse(editor.hasUnsavedChanges)
    }

    func testInkRidesWithItsWordAndHidesWithIt() throws {
        let (editor, root) = try editor("The shortcut recorder clips its label.\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        let word = rect(of: "clips", in: editor)
        editor.commit(circle(around: word))
        settle()
        XCTAssertEqual(editor.currentDocument().anchors.count, 1)
        let before = try XCTUnwrap(editor.visibleInkOrigins.first)

        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.insertText("A new first line.\n", replacementRange: NSRange(location: 0, length: 0))
        settle()
        let after = try XCTUnwrap(editor.visibleInkOrigins.first)
        XCTAssertGreaterThan(after.y, before.y + 10, "Ink moves down with its word")
        XCTAssertEqual(after.x - rect(of: "clips", in: editor).minX, before.x - word.minX, accuracy: 0.5)

        let clips = (editor.textView.string as NSString).range(of: "clips ")
        editor.textView.setSelectedRange(clips)
        editor.textView.insertText("", replacementRange: clips)
        settle()
        XCTAssertTrue(editor.visibleInkOrigins.isEmpty, "Deleting the word hides its ink")
        XCTAssertTrue(editor.currentDocument().items.isEmpty)
        editor.undo()
        XCTAssertEqual(editor.visibleInkOrigins.count, 1, "Undoing the delete brings the ink back")
    }

    func testInkUndoRedoAndEraser() throws {
        let (editor, root) = try editor("Palette row is hard to see.\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        let word = rect(of: "Palette", in: editor)
        editor.commit(circle(around: word))
        settle()
        XCTAssertTrue(editor.hasUnsavedChanges)
        editor.undo()
        XCTAssertTrue(editor.items.isEmpty)
        XCTAssertFalse(editor.hasUnsavedChanges)
        settle()
        editor.redo()
        XCTAssertEqual(editor.items.count, 1)
        editor.erase(at: CGPoint(x: word.midX + word.width / 2 + 8, y: word.midY))
        XCTAssertTrue(editor.items.isEmpty)
    }

    func testArrowHeadJoinsItsShaft() throws {
        let (editor, root) = try editor("Filename preview shows the old date format.\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        let word = rect(of: "date", in: editor)
        let tip = CGPoint(x: word.midX, y: word.maxY + 2)
        let shaft = InkStroke(tool: .pen, color: "#3a8dff", width: 3.2,
                              points: [InkPoint(x: tip.x + 70, y: tip.y + 45, pressure: -1), InkPoint(x: tip.x, y: tip.y, pressure: -1)])
        let head = InkStroke(tool: .pen, color: "#3a8dff", width: 3.2,
                             points: [InkPoint(x: tip.x + 4, y: tip.y + 12, pressure: -1), InkPoint(x: tip.x, y: tip.y, pressure: -1),
                                      InkPoint(x: tip.x + 12, y: tip.y + 2, pressure: -1)])
        let now = Date()
        editor.commit(shaft, at: now)
        editor.commit(head, at: now.addingTimeInterval(0.5))
        let document = editor.currentDocument()
        XCTAssertEqual(document.anchors.count, 1)
        XCTAssertEqual(Set(document.items.map(\.anchor)).count, 1)
    }

    func testSaveWritesAPictureThatReopensAsTheSameNote() throws {
        let (editor, root) = try editor("Leave the sound toggle alone.\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.commit(circle(around: rect(of: "sound", in: editor)))
        XCTAssertTrue(editor.save())
        XCTAssertFalse(editor.hasUnsavedChanges)
        let data = try Data(contentsOf: editor.noteURL)
        XCTAssertNotNil(NSImage(data: data))
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: data), editor.currentDocument())
        XCTAssertEqual(FinderReopenLogic.resolve(.success(.single(url: editor.noteURL))), .openInkNote(editor.noteURL))

        let fromMarkdown = try InkNoteWindowController.resolve(editor.sourceURL)
        XCTAssertEqual(fromMarkdown.noteURL, editor.noteURL, "Reopening the Markdown continues the saved note")
        let reopened = InkNoteWindowController(opened: try InkNoteWindowController.resolve(editor.noteURL))
        defer { reopened.window?.close() }
        XCTAssertEqual(reopened.currentDocument(), editor.currentDocument())
        XCTAssertFalse(reopened.hasUnsavedChanges)
    }

    func testUnrelatedPictureWithTheSameNameIsNeverOverwritten() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let markdown = root.appendingPathComponent("plan.md")
        try Data("Hi\n".utf8).write(to: markdown)
        try XCTUnwrap(TestSupport.solidImagePNGData()).write(to: root.appendingPathComponent("plan.png"))
        XCTAssertNotEqual(try InkNoteWindowController.resolve(markdown).noteURL.lastPathComponent, "plan.png")
    }

    func testMarkerShortcutAddsCircleAndNoteLine() throws {
        let (editor, root) = try editor("Fix this")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        editor.insertMarker()
        settle()
        XCTAssertEqual(editor.textView.string, "Fix\u{FFFC} this\n\n\u{FFFC} ")
        XCTAssertEqual(editor.textView.selectedRange().location, (editor.textView.string as NSString).length)
        XCTAssertEqual(editor.currentDocument().markers.map(\.number), [1, 1])
        editor.undo()
        XCTAssertEqual(editor.textView.string, "Fix this")
    }

    func testKeysSwitchModeToolsAndColorsAndOtherTypingLeavesDrawing() throws {
        let (editor, root) = try editor("Note")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.perform(.draw)
        editor.perform(.draw)
        XCTAssertEqual(editor.mode, .draw, "Command+D always draws; it does not toggle")
        editor.perform(.type)
        editor.perform(.type)
        XCTAssertEqual(editor.mode, .type, "Command+T always types")
        editor.perform(.tool(.rectangle))
        XCTAssertEqual(editor.mode, .draw, "Picking a tool starts drawing")
        editor.perform(.tool(.eraser))
        XCTAssertEqual(editor.tool, .eraser)
        let first = editor.colorHex
        editor.perform(.nextColor)
        XCTAssertNotEqual(editor.colorHex, first)
        XCTAssertEqual(editor.tool, .pen, "Picking a color puts the eraser down")
        for _ in 1..<editor.palette.count { editor.perform(.nextColor) }
        XCTAssertEqual(editor.colorHex, first, "Q wraps around the palette")
        let letter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_K)))
        XCTAssertFalse(editor.handleKey(letter), "The letter still reaches the text")
        XCTAssertEqual(editor.mode, .type)
        editor.perform(.draw)
        editor.perform(.escape)
        XCTAssertEqual(editor.mode, .type, "Escape leaves drawing before it closes anything")
    }

    func testClearInkIsOneUndoStep() throws {
        let (editor, root) = try editor("Palette row is hard to see.\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        editor.commit(circle(around: rect(of: "Palette", in: editor)))
        editor.commit(circle(around: rect(of: "hard", in: editor)), at: Date().addingTimeInterval(5))
        settle()
        editor.perform(.clearInk)
        XCTAssertTrue(editor.items.isEmpty)
        settle()
        editor.undo()
        XCTAssertEqual(editor.items.count, 2)
    }

    func testNotesUseTheSettingsPaletteWithoutColorsLostOnTheDarkBackground() throws {
        XCTAssertEqual(InkNoteWindowController.noteColors(forPaletteIDs: EditorPalette.defaultIDs).map(\.id),
                       ["red", "blue", "green", "yellow", "white"], "Black is dropped from the default palette")
        XCTAssertEqual(InkNoteWindowController.noteColors(forPaletteIDs: ["purple", "black", "orange"]).map(\.id), ["purple", "orange"])
        XCTAssertEqual(InkNoteWindowController.noteColors(forPaletteIDs: ["black"]).map(\.id), ["white"])
        for color in EditorPalette.available where color.id != "black" {
            XCTAssertTrue(InkNoteWindowController.isVisibleOnBackground(color.color), color.name)
        }

        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        store.update { $0.editorColorIDs = ["cyan", "pink"] }
        let url = root.appendingPathComponent("plan.md")
        try Data("Hi".utf8).write(to: url)
        let editor = InkNoteWindowController(opened: try InkNoteWindowController.resolve(url), settingsStore: store)
        defer { editor.window?.close() }
        XCTAssertEqual(editor.palette.map(\.id), ["cyan", "pink"])
        XCTAssertEqual(editor.colorHex, EditorPalette.available.first { $0.id == "cyan" }?.hex)
        store.update { $0.editorColorIDs = ["pink", "white"] }
        XCTAssertEqual(editor.palette.map(\.id), ["pink", "white"], "Settings changes reach an open note")
        XCTAssertEqual(editor.colorHex, EditorPalette.available.first { $0.id == "pink" }?.hex)
    }

    func testCopyAndSaveWritesCopiesAndCloses() throws {
        let (editor, root) = try editor("Copy me")
        defer { TestSupport.removeIfExists(root) }
        var copied: URL?
        var closed = false
        editor.copyFile = { copied = $0; return true }
        editor.onClose = { closed = true }
        editor.textView.insertText(" now", replacementRange: NSRange(location: 7, length: 0))
        editor.perform(.copyAndSave)
        XCTAssertEqual(copied, editor.noteURL)
        XCTAssertEqual(PNGMetadata.extractInkNote(fromPNG: try Data(contentsOf: editor.noteURL))?.text, "Copy me now")
        XCTAssertTrue(closed)
    }

    func testEveryToolbarControlShowsItsShortcut() throws {
        let (editor, root) = try editor("Hi")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        let host = try XCTUnwrap(editor.window?.contentView)
        func buttons(in view: NSView) -> [NSButton] {
            ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap(buttons)
        }
        let hinted = Set(editor.shortcutHints.map { ObjectIdentifier($0.view) })
        let toolbarButtons = buttons(in: host)
        XCTAssertEqual(toolbarButtons.filter { !($0 is InkSwatchButton) }.count, 16)
        for button in toolbarButtons {
            let tip = try XCTUnwrap(button.toolTip)
            XCTAssertTrue(tip.contains("(") && tip.contains(")"), "Tooltip names a shortcut: \(tip)")
            if !(button is InkSwatchButton) { XCTAssertTrue(hinted.contains(ObjectIdentifier(button)), tip) }
        }
    }

    func testToolbarFitsTheNarrowestWindow() throws {
        let (editor, root) = try editor("Hi")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        let window = try XCTUnwrap(editor.window)
        let bar = try XCTUnwrap(window.contentView?.subviews.first as? NSStackView)
        XCTAssertLessThanOrEqual(bar.fittingSize.width, window.minSize.width)
    }

    func testDraggingAShapeToolDrawsOneShapeAndAClickDrawsNothing() throws {
        let (editor, root) = try editor("Check the arrow under this line.\n")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: editor.textView.convert(point, to: nil), modifierFlags: flags,
                                             timestamp: 0, windowNumber: editor.window?.windowNumber ?? 0, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let word = rect(of: "arrow", in: editor)
        let start = CGPoint(x: word.minX, y: word.maxY + 30), end = CGPoint(x: word.maxX, y: word.maxY + 4)
        editor.perform(.tool(.rectangle))
        XCTAssertTrue(editor.inkMouseDown(try mouse(.leftMouseDown, start)))
        XCTAssertTrue(editor.inkMouseUp(try mouse(.leftMouseUp, start)))
        XCTAssertTrue(editor.items.isEmpty, "A click with a shape tool draws nothing")

        editor.perform(.tool(.arrow))
        XCTAssertTrue(editor.inkMouseDown(try mouse(.leftMouseDown, start)))
        XCTAssertTrue(editor.inkMouseDragged(try mouse(.leftMouseDragged, CGPoint(x: start.x + 5, y: start.y - 5))))
        XCTAssertTrue(editor.inkMouseDragged(try mouse(.leftMouseDragged, end)))
        XCTAssertTrue(editor.inkMouseUp(try mouse(.leftMouseUp, end)))
        let item = try XCTUnwrap(editor.items.first?.item)
        XCTAssertEqual(editor.items.count, 1)
        XCTAssertEqual(item.stroke.tool, .shape)
        XCTAssertEqual(item.stroke.width, InkNoteWindowController.shapeWidth)
        XCTAssertEqual(item.stroke.points.count, 6, "One arrow from the last drag position, not a trail")
        XCTAssertNotNil(item.anchor, "Shapes pin to the text like drawn ink")
        editor.undo()
        XCTAssertTrue(editor.items.isEmpty, "A shape is one undo step")
    }

    func testInkInTheMarginsAroundTheTextIsDrawn() throws {
        let (editor, root) = try editor("Hi")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
        let column = editor.textView.textContainerOrigin
        let marks = [CGPoint(x: column.x + 40, y: column.y / 2), CGPoint(x: column.x / 2, y: column.y + 40)]
        for mark in marks {
            editor.commit(InkStroke(tool: .shape, color: "#ffffff", width: 6,
                                    points: [InkPoint(x: mark.x - 10, y: mark.y, pressure: -1), InkPoint(x: mark.x + 10, y: mark.y, pressure: -1)]),
                          at: Date().addingTimeInterval(Double(marks.firstIndex(of: mark)!) * 5))
        }
        let view = editor.textView
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        for mark in marks {
            let color = try XCTUnwrap(rep.colorAt(x: Int(mark.x * scale), y: Int(mark.y * scale))?.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(color.redComponent, 0.8, "Ink at \(mark) is outside the text column and must still show")
        }
    }

    func testShortcutBadgesSitUnderTheToolbarInsideTheWindow() throws {
        let (editor, root) = try editor("Hi")
        defer { editor.window?.close(); TestSupport.removeIfExists(root) }
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
        for hint in editor.shortcutHints {
            XCTAssertFalse(hint.view.convert(hint.view.bounds, to: host).intersects(help.frame), "Help never covers \(hint.label)")
        }
    }
}

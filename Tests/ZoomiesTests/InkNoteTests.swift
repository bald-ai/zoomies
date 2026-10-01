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

    func testNoteDataRoundTripsThroughPNGChunks() throws {
        let png = try XCTUnwrap(TestSupport.solidImagePNGData())
        var document = InkNoteDocument(text: "hi \u{FFFC}", markers: [.init(index: 3, number: 2)], anchors: [.init(index: 0, id: "a")])
        document.items = [.init(stroke: InkStroke(tool: .highlighter, color: "#ffcc00", width: 17, points: [InkPoint(x: 0, y: 0, pressure: -1)]),
                                anchor: "a", x: -2, y: 4)]
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
        let keys: [(Int, InkNoteKeymap.Command)] = [(kVK_ANSI_W, .tool(.pen)), (kVK_ANSI_H, .tool(.highlighter)),
            (kVK_ANSI_X, .tool(.eraser)), (kVK_ANSI_Q, .nextColor), (kVK_ANSI_F, .marker), (kVK_ANSI_T, .type)]
        for (key, expected) in keys {
            XCTAssertEqual(command(key, "other layout", .capsLock, drawing: true), expected)
            XCTAssertNil(command(key, "w"), "While typing, letters are text")
            for flag: NSEvent.ModifierFlags in [.shift, .control, .option] {
                XCTAssertNil(command(key, "", flag, drawing: true))
            }
        }
        for key in [kVK_ANSI_P, kVK_ANSI_E, kVK_ANSI_1, kVK_ANSI_5] {
            XCTAssertNil(command(key, "", drawing: true), "The old P / E / 1–5 keys are gone")
        }
    }

    func testCommandShortcutsAndSessionKeysMatchTheRestOfTheApp() {
        let cases: [(Int, String, NSEvent.ModifierFlags, InkNoteKeymap.Command)] = [
            (kVK_ANSI_S, "s", .command, .save), (kVK_Return, "\r", .command, .copyAndSave),
            (kVK_ANSI_KeypadEnter, "\u{3}", .command, .copyAndSave), (kVK_ANSI_W, "w", .command, .close),
            (kVK_Escape, "\u{1b}", [], .escape), (kVK_ANSI_Z, "z", .command, .undo),
            (kVK_ANSI_Z, "Z", [.command, .shift], .redo), (kVK_ANSI_D, "d", .command, .toggleDraw),
            (kVK_ANSI_F, "f", .command, .marker), (kVK_ANSI_A, "a", .command, .selectAll),
            (kVK_ANSI_C, "c", .command, .copy), (kVK_ANSI_X, "x", .command, .cut), (kVK_ANSI_V, "v", .command, .paste)
        ]
        for (key, chars, flags, expected) in cases {
            XCTAssertEqual(command(key, chars, flags), expected, "\(key) \(flags)")
            XCTAssertEqual(command(key, chars, flags, drawing: true), expected, "\(key) \(flags) while drawing")
        }
        XCTAssertNil(command(kVK_Return, "\r"), "Return stays a newline")
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
        editor.perform(.toggleDraw)
        XCTAssertEqual(editor.mode, .draw)
        editor.perform(.tool(.eraser))
        XCTAssertEqual(editor.tool, .eraser)
        let first = editor.colorHex
        editor.perform(.nextColor)
        XCTAssertNotEqual(editor.colorHex, first)
        XCTAssertEqual(editor.tool, .pen, "Picking a color puts the eraser down")
        for _ in 1..<InkNoteWindowController.palette.count { editor.perform(.nextColor) }
        XCTAssertEqual(editor.colorHex, first, "Q wraps around the palette")
        let letter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_K)))
        XCTAssertFalse(editor.handleKey(letter), "The letter still reaches the text")
        XCTAssertEqual(editor.mode, .type)
        editor.perform(.toggleDraw)
        editor.perform(.escape)
        XCTAssertEqual(editor.mode, .type, "Escape leaves drawing before it closes anything")
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
        XCTAssertEqual(toolbarButtons.filter { !($0 is InkSwatchButton) }.count, 11)
        for button in toolbarButtons {
            let tip = try XCTUnwrap(button.toolTip)
            XCTAssertTrue(tip.contains("(") && tip.contains(")"), "Tooltip names a shortcut: \(tip)")
            if !(button is InkSwatchButton) { XCTAssertTrue(hinted.contains(ObjectIdentifier(button)), tip) }
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

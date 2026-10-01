import AppKit
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
}

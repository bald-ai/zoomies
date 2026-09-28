import XCTest
@testable import Zoomies

final class MarkerNoteLogicTests: XCTestCase {
    func testFirstLineGetsBlankLinesAndLaterLinesFollowDirectly() {
        var note = MarkerNoteLogic.update(note: "Base", number: 1, newText: "one")
        note = MarkerNoteLogic.update(note: note, number: 2, newText: "two")
        XCTAssertEqual(note, "Base\n\n\n1: one\n2: two")
    }

    func testEditingReplacesOnlyThatMarkersLine() {
        let note = MarkerNoteLogic.update(note: "Base\n\n\n1: one\n2: two", number: 1, newText: "uno")
        XCTAssertEqual(note, "Base\n\n\n1: uno\n2: two")
    }

    func testEmptyTextRemovesLine() {
        XCTAssertEqual(MarkerNoteLogic.update(note: "Base\n\n\n1: one\n2: two", number: 2, newText: ""),
                       "Base\n\n\n1: one")
        XCTAssertEqual(MarkerNoteLogic.update(note: "Base", number: 3, newText: ""), "Base")
    }

    func testEmptyNoteStartsWithMarkerLine() {
        XCTAssertEqual(MarkerNoteLogic.update(note: "", number: 1, newText: "one"), "1: one")
        XCTAssertEqual(MarkerNoteLogic.update(note: "1: one", number: 2, newText: "two"), "1: one\n2: two")
    }

    func testExistingTextIsReadFromNoteSoReopenedNotesStayEditable() {
        let reopened = "Base\n\n\n1: one\n2: two"
        XCTAssertEqual(MarkerNoteLogic.text(for: 2, in: reopened), "two")
        XCTAssertNil(MarkerNoteLogic.text(for: 3, in: reopened))
        XCTAssertNil(MarkerNoteLogic.text(for: 1, in: "11: eleven"))
    }

    func testCapacityKeepsNoteWithinLimit() {
        // "Base" + "\n\n\n" + "1: " = 10 characters used before the text.
        XCTAssertEqual(MarkerNoteLogic.capacity(note: "Base", number: 1, limit: 20), 10)
        // Editing counts the marker's own text as available.
        XCTAssertEqual(MarkerNoteLogic.capacity(note: "Base\n\n\n1: one", number: 1, limit: 20), 10)
        XCTAssertEqual(MarkerNoteLogic.capacity(note: String(repeating: "x", count: 30), number: 1, limit: 20), 0)
    }

    func testNumberedListInTypedNoteIsNotTreatedAsMarkerLines() {
        let typed = "Steps:\n1: open app\n2: click"
        XCTAssertNil(MarkerNoteLogic.text(for: 1, in: typed))
        XCTAssertEqual(MarkerNoteLogic.update(note: typed, number: 1, newText: "marker"),
                       "Steps:\n1: open app\n2: click\n\n\n1: marker")
        let withMarkers = "Steps:\n1: open app\n\n\n1: marker"
        XCTAssertEqual(MarkerNoteLogic.text(for: 1, in: withMarkers), "marker")
        XCTAssertEqual(MarkerNoteLogic.update(note: withMarkers, number: 1, newText: ""), "Steps:\n1: open app")
        XCTAssertEqual(MarkerNoteLogic.removingLines(notIn: [], from: withMarkers), "Steps:\n1: open app")
    }

    func testRemovingLinesForDeletedMarkers() {
        let note = "Base\n\n\n1: one\n2: two\n3: three"
        XCTAssertEqual(MarkerNoteLogic.removingLines(notIn: [1, 3], from: note), "Base\n\n\n1: one\n3: three")
        XCTAssertEqual(MarkerNoteLogic.removingLines(notIn: [], from: note), "Base")
        XCTAssertEqual(MarkerNoteLogic.removingLines(notIn: [1, 2, 3], from: note), note)
        XCTAssertEqual(MarkerNoteLogic.removingLines(notIn: [], from: "1: only"), "")
    }

    func testSanitizedFlattensLineBreaks() {
        XCTAssertEqual(MarkerNoteLogic.sanitized(" a\nb\r\nc "), "a b  c")
    }
}

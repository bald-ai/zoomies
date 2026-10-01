import XCTest
@testable import Zoomies

final class MarkdownMarkerLogicTests: XCTestCase {
    private func roundTrip(_ text: String) -> String {
        let doc = MarkdownMarkerLogic.read(text)
        return MarkdownMarkerLogic.write(doc, mainText: doc.mainText, notes: doc.notes)
    }
    func testPlainTextRoundTripsExactlyIncludingLineEndingsAndWhitespace() {
        for text in ["", "hello", "hello\n", "hello\r\n", "hello\n\n  \n", "a\r\nb\n", "[^foo] text\n\n[^foo]: named\n", "1. one\n2. two\n\nend", "[^1]: middle\n\nbody\n"] {
            XCTAssertEqual(Data(roundTrip(text).utf8), Data(text.utf8))
        }
    }
    func testMarkerBlockIsSortedWithOneBlankLineAndPreservesFinalNewline() {
        for nl in ["\n", "\r\n"] {
            for final in ["", nl] {
                let text = "body[^2] [^1]" + nl + nl + "[^2]: two" + nl + nl + "[^1]: one" + final
                let doc = MarkdownMarkerLogic.read(text)
                XCTAssertEqual(doc.mainText, "body[^2] [^1]")
                XCTAssertEqual(doc.notes, [1: "one", 2: "two"])
                XCTAssertEqual(roundTrip(text), "body[^2] [^1]" + nl + nl + "[^1]: one" + nl + "[^2]: two" + final)
            }
        }
    }
    func testSavingEditedTextKeepsOriginalAbsenceOfFinalNewline() {
        let doc = MarkdownMarkerLogic.read("first\r\nsecond")
        XCTAssertEqual(MarkdownMarkerLogic.write(doc, mainText: "first\r\nsecond\n", notes: [:]), "first\r\nsecond")
    }

    func testOrphansAndUnpairedAnchorsSurvive() {
        let doc = MarkdownMarkerLogic.read("body[^1]\n\n[^9]: orphan")
        XCTAssertEqual(doc.notes, [9: "orphan"])
        XCTAssertEqual(MarkdownMarkerLogic.anchors(in: doc.mainText).map(\.number), [1])
        XCTAssertEqual(roundTrip("body[^1]"), "body[^1]")
        XCTAssertEqual(roundTrip("[^9]: orphan\n"), "[^9]: orphan\n")
        XCTAssertEqual(MarkdownMarkerLogic.nextNumber(notes: doc.notes, anchored: [1]), 10)
    }
    func testDefinitionsInBodyAndNamedFootnotesStayText() {
        let text = "1. item\n[^1]: ordinary\nbody[^2] [^foo] [^0]\n\n[^foo]: named\n\nend"
        let doc = MarkdownMarkerLogic.read(text)
        XCTAssertTrue(doc.notes.isEmpty)
        XCTAssertEqual(MarkdownMarkerLogic.anchors(in: text).map(\.number), [2])
        XCTAssertEqual(roundTrip(text), text)
        XCTAssertTrue(MarkdownMarkerLogic.read("body\n[^1]: unseparated").notes.isEmpty)
    }
    func testPastedAnchorsReconnectOnlyAvailableNotesOnce() {
        let anchors = MarkdownMarkerLogic.pastedAnchors(in: "[^1] [^2] [^2] [^3] [^foo]", notes: [1: "a", 2: "b"], anchored: [1])
        XCTAssertEqual(anchors.map(\.number), [2])
        XCTAssertEqual(anchors.map(\.range), [NSRange(location: 5, length: 4)])
        XCTAssertEqual(MarkdownMarkerLogic.nextNumber(notes: [7: "orphan"], anchored: [2]), 8)
        XCTAssertNil(MarkdownMarkerLogic.nextNumber(notes: [Int.max: ""], anchored: []))
    }
}

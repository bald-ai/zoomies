import XCTest
import AppKit
@testable import Zoomies

final class ScratchpadServiceTests: XCTestCase {
    func testWriteWritesUTF8MarkdownFile() throws {
        let desktop = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(desktop) }
        let writer = ScratchpadNoteWriter(directory: desktop)

        let url = try writer.write(text: "hello", baseName: "Note A")

        XCTAssertEqual(url.pathExtension, "md")
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent, "Note A")
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents, "hello")
    }

    func testWriteCreatesUniqueFilenameOnCollision() throws {
        let desktop = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(desktop) }
        let writer = ScratchpadNoteWriter(directory: desktop)

        let first = try writer.write(text: "a", baseName: "Dup")
        let second = try writer.write(text: "b", baseName: "Dup")

        XCTAssertEqual(first.lastPathComponent, "Dup.md")
        XCTAssertEqual(second.lastPathComponent, "Dup_2.md")
        XCTAssertNotEqual(first, second)
    }

    func testRepeatBaseNameNeverOverwritesExistingNote() throws {
        let desktop = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(desktop) }
        let writer = ScratchpadNoteWriter(directory: desktop)

        let first = try writer.write(text: "original", baseName: "Note")
        let second = try writer.write(text: "repeat", baseName: "Note")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "repeat")
    }

    func testWriteCreatesDirectoryIfMissing() throws {
        let base = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(base) }
        let missingDesktop = base.appendingPathComponent("nested/desktop", isDirectory: true)
        let writer = ScratchpadNoteWriter(directory: missingDesktop)

        let url = try writer.write(text: "x", baseName: "N")

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testWriteAllowsEmptyAndWhitespaceOnlyText() throws {
        let desktop = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(desktop) }
        let writer = ScratchpadNoteWriter(directory: desktop)

        let emptyURL = try writer.write(text: "", baseName: "Empty")
        XCTAssertEqual(try String(contentsOf: emptyURL, encoding: .utf8), "")

        let whitespaceURL = try writer.write(text: "   \n  ", baseName: "Whitespace")
        XCTAssertEqual(try String(contentsOf: whitespaceURL, encoding: .utf8), "   \n  ")
    }

    func testOpenPresentsNotePanelFirst() throws {
        let base = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(base) }
        let cache = base.appendingPathComponent("clipboard", isDirectory: true)
        let clipboard = ClipboardService(fileManager: .default, cacheDirectory: cache)
        let service = ScratchpadService(fileManager: .default,
                                        clipboardService: clipboard,
                                        desktopDirectory: base.appendingPathComponent("desktop", isDirectory: true))

        service.open()

        XCTAssertEqual(service.presentedPanel, .note, "Opening the scratchpad must land on the note panel so Enter saves immediately.")
    }
}

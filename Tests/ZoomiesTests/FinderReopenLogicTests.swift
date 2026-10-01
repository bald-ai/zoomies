import XCTest
@testable import Zoomies

final class FinderReopenLogicTests: XCTestCase {
    func testSingleSafeImageOpensExactURLWithoutChangingFile() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let file = root.appendingPathComponent("selected.png")
        let bytes = try TestSupport.solidImagePNGData()
        try bytes.write(to: file)
        XCTAssertEqual(FinderReopenLogic.resolve(.success(.single(url: file))), .open(file))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testMissingUnreadableAndOversizedImagesNeverOpen() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let file = root.appendingPathComponent("selected.png")
        for bytes in [Data(), Data("plain text".utf8)] {
            try bytes.write(to: file)
            XCTAssertEqual(FinderReopenLogic.resolve(.success(.single(url: file))),
                           .warning(title: "Not an Image", message: "The selected Finder item is not a readable image.", settingsURL: nil))
        }
        try XCTUnwrap(TestSupport.stubPNGDeclaringSize(width: 100_000, height: 100_000)).write(to: file)
        guard case .warning(let title, _, nil) = FinderReopenLogic.resolve(.success(.single(url: file))) else {
            return XCTFail("Oversized image must be rejected before opening")
        }
        XCTAssertEqual(title, "Image is too large")
    }

    func testMarkdownRoutingValidatesSizeAndEncodingBeforeImageInspection() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        for name in ["plan.md", "plan.markdown", "plan.MD"] {
            let file = root.appendingPathComponent(name)
            try Data("# Plan\n".utf8).write(to: file)
            XCTAssertEqual(FinderReopenLogic.resolve(.success(.single(url: file))), .openInkNote(file))
            try Data([0xff, 0xfe]).write(to: file)
            guard case .warning(let title, _, _) = FinderReopenLogic.resolve(.success(.single(url: file))) else { return XCTFail("Invalid encoding opened") }
            XCTAssertEqual(title, "Invalid UTF-8")
            try Data(repeating: 65, count: MarkdownMarkerLogic.maximumFileSize + 1).write(to: file)
            guard case .warning(let title, _, _) = FinderReopenLogic.resolve(.success(.single(url: file))) else { return XCTFail("Oversized file opened") }
            XCTAssertEqual(title, "Markdown file is too large")
        }
    }

    func testSelectionCountsAndErrorsHaveDistinctRecoveryMessages() {
        let cases: [(Result<FinderSelectionService.Selection, Error>, String, Bool)] = [
            (.success(.none), "No Finder Selection", false),
            (.success(.multiple(count: 3)), "Multiple Finder Items Selected", false),
            (.failure(NSError(domain: "FinderSelectionService", code: -2)), "Automation Permission Required", true),
            (.failure(FinderSelectionLookupError.timeout.asNSError), "Finder didn’t respond", false),
            (.failure(NSError(domain: "FinderSelectionService", code: -1)), "Finder Error", false),
            (.failure(NSError(domain: "other", code: -2)), "Finder Error", false)
        ]
        for (input, title, settingsLink) in cases {
            guard case .warning(let actualTitle, let message, let url) = FinderReopenLogic.resolve(input) else {
                XCTFail("Unexpected open decision"); continue
            }
            XCTAssertEqual(actualTitle, title)
            XCTAssertFalse(message.isEmpty)
            XCTAssertEqual(url != nil, settingsLink)
            if settingsLink { XCTAssertEqual(url, "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") }
        }
    }
}

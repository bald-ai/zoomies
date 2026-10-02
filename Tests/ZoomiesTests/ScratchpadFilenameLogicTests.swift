import XCTest
@testable import Zoomies

final class ScratchpadFilenameLogicTests: XCTestCase {
    func testDefaultBaseNameFormat() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        // Build the expected value with an identically-configured formatter so the
        // assertion is deterministic across machines (both use the local timezone).
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let expected = "Note \(formatter.string(from: date))"

        XCTAssertEqual(ScratchpadFilenameLogic.defaultBaseName(date: date), expected)

        // And sanity-check the shape regardless of date/timezone.
        let pattern = #"^Note \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}$"#
        XCTAssertNotNil(expected.range(of: pattern, options: .regularExpression))
    }
}

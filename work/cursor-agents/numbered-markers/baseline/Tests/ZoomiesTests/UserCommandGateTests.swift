import XCTest
@testable import Zoomies

final class UserCommandGateTests: XCTestCase {
    func testPendingScratchpadOpenBlocksScreenshotUntilRequestFinishes() {
        var gate = UserCommandGate()

        XCTAssertTrue(gate.beginScratchpadOpenRequest())
        XCTAssertFalse(gate.beginScratchpadOpenRequest())
        XCTAssertFalse(gate.canStartScreenshot(scratchpadIsBusy: false))

        gate.finishScratchpadOpenRequest()

        XCTAssertTrue(gate.canStartScreenshot(scratchpadIsBusy: false))
        XCTAssertFalse(gate.canStartScreenshot(scratchpadIsBusy: true))
    }
}

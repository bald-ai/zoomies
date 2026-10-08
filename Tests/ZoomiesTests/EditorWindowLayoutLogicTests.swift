import XCTest
import AppKit
@testable import Zoomies

final class EditorWindowLayoutLogicTests: XCTestCase {
    func testMaximumContentSizeUsesNinetyPercentOfVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 2000, height: 1000)

        let size = EditorWindowLayoutLogic.maximumContentSize(
            visibleFrame: visibleFrame,
            minContentSize: NSSize(width: 580, height: 250)
        )

        XCTAssertEqual(size.width, 1800, accuracy: 0.01)
        XCTAssertEqual(size.height, 900, accuracy: 0.01)
    }

    func testMaximumContentSizeFallsBackWhenVisibleFrameIsMissing() {
        let size = EditorWindowLayoutLogic.maximumContentSize(
            visibleFrame: nil,
            minContentSize: NSSize(width: 580, height: 250)
        )

        XCTAssertEqual(size.width, 1400, accuracy: 0.01)
        XCTAssertEqual(size.height, 900, accuracy: 0.01)
    }

    func testMaximumContentSizeNeverDropsBelowMinimum() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 400, height: 200)

        let size = EditorWindowLayoutLogic.maximumContentSize(
            visibleFrame: visibleFrame,
            minContentSize: NSSize(width: 580, height: 250)
        )

        XCTAssertEqual(size.width, 580, accuracy: 0.01)
        XCTAssertEqual(size.height, 250, accuracy: 0.01)
    }

    func testChromeGrowthKeepsTopEdgeAndAddsHeight() {
        let frame = EditorWindowLayoutLogic.frameAdjustedForChromeChange(
            NSRect(x: 100, y: 300, width: 800, height: 400),
            heightDelta: 50, minHeight: 280,
            visibleFrame: NSRect(x: 0, y: 0, width: 2000, height: 1000))

        XCTAssertEqual(frame, NSRect(x: 100, y: 250, width: 800, height: 450))
    }

    func testChromeGrowthNearScreenBottomMovesWindowUp() {
        let frame = EditorWindowLayoutLogic.frameAdjustedForChromeChange(
            NSRect(x: 0, y: 20, width: 800, height: 400),
            heightDelta: 60, minHeight: 280,
            visibleFrame: NSRect(x: 0, y: 0, width: 2000, height: 1000))

        XCTAssertEqual(frame, NSRect(x: 0, y: 0, width: 800, height: 460))
    }

    func testChromeGrowthNeverExceedsVisibleHeight() {
        let frame = EditorWindowLayoutLogic.frameAdjustedForChromeChange(
            NSRect(x: 0, y: 50, width: 800, height: 900),
            heightDelta: 200, minHeight: 280,
            visibleFrame: NSRect(x: 0, y: 0, width: 2000, height: 1000))

        XCTAssertEqual(frame, NSRect(x: 0, y: 0, width: 800, height: 1000))
    }

    func testChromeShrinkStopsAtMinimumHeight() {
        let frame = EditorWindowLayoutLogic.frameAdjustedForChromeChange(
            NSRect(x: 0, y: 300, width: 800, height: 300),
            heightDelta: -60, minHeight: 280,
            visibleFrame: NSRect(x: 0, y: 0, width: 2000, height: 1000))

        XCTAssertEqual(frame, NSRect(x: 0, y: 320, width: 800, height: 280))
    }

    func testNoteBarMaxHeightIsAQuarterOfEditorHeightWithAFloor() {
        XCTAssertEqual(EditorWindowLayoutLogic.noteBarMaxHeight(maxContentHeight: 1000), 250)
        XCTAssertEqual(EditorWindowLayoutLogic.noteBarMaxHeight(maxContentHeight: 200), 80)
    }

    func testRefittedZoomKeepsOpeningZoomUntilCanvasShrinks() {
        let opening = NSSize(width: 556, height: 160)
        XCTAssertEqual(EditorWindowLayoutLogic.refittedZoom(viewportSize: opening, openingViewportSize: opening,
                                                            openingZoom: 1.44), 1.44, accuracy: 0.0001)
        XCTAssertEqual(EditorWindowLayoutLogic.refittedZoom(viewportSize: NSSize(width: 700, height: 300),
                                                            openingViewportSize: opening,
                                                            openingZoom: 1.44), 1.44, accuracy: 0.0001)
        XCTAssertEqual(EditorWindowLayoutLogic.refittedZoom(viewportSize: NSSize(width: 556, height: 120),
                                                            openingViewportSize: opening,
                                                            openingZoom: 1.44), 1.08, accuracy: 0.0001)
        XCTAssertEqual(EditorWindowLayoutLogic.refittedZoom(viewportSize: opening, openingViewportSize: .zero,
                                                            openingZoom: 1.2), 1.2, accuracy: 0.0001)
    }

    func testMakeLayoutKeepsFitScaleAtOneWhenImageFits() {
        let layout = EditorWindowLayoutLogic.makeLayout(
            EditorWindowLayoutInput(imagePointSize: NSSize(width: 800, height: 500),
                                    maxContentSize: NSSize(width: 1400, height: 900),
                                    minContentSize: NSSize(width: 580, height: 250),
                                    chromeSize: NSSize(width: 24, height: 120),
                                    autoZoomFillRatio: 0.90,
                                    maxAutoUserZoom: 2.0)
        )

        XCTAssertEqual(layout.fitScale, 1.0, accuracy: 0.0001)
    }

    func testMakeLayoutReducesFitScaleWhenImageExceedsDynamicCap() {
        let layout = EditorWindowLayoutLogic.makeLayout(
            EditorWindowLayoutInput(imagePointSize: NSSize(width: 1700, height: 900),
                                    maxContentSize: NSSize(width: 1200, height: 700),
                                    minContentSize: NSSize(width: 580, height: 250),
                                    chromeSize: NSSize(width: 24, height: 120),
                                    autoZoomFillRatio: 0.90,
                                    maxAutoUserZoom: 2.0)
        )

        XCTAssertLessThan(layout.fitScale, 1.0)
    }

    func testFullScreenImageKeepsBlankMarginForDrawing() {
        let layout = EditorWindowLayoutLogic.makeLayout(
            EditorWindowLayoutInput(imagePointSize: NSSize(width: 1512, height: 982),
                                    maxContentSize: NSSize(width: 1360, height: 795),
                                    minContentSize: NSSize(width: 580, height: 250),
                                    chromeSize: NSSize(width: 24, height: 120),
                                    autoZoomFillRatio: 0.90,
                                    maxAutoUserZoom: 2.0)
        )

        XCTAssertEqual(layout.totalPadding, EditorWindowLayoutLogic.imagePadding, accuracy: 0.0001)
        let imageHeight = 982 * layout.fitScale
        XCTAssertLessThanOrEqual(imageHeight + layout.totalPadding + 120, layout.contentSize.height + 0.5)
        let imageWidth = 1512 * layout.fitScale
        XCTAssertLessThanOrEqual(imageWidth + layout.totalPadding + 24, layout.contentSize.width + 0.5)
    }

    func testMakeLayoutAutoZoomsSmallImagesWithoutExceedingMax() {
        let layout = EditorWindowLayoutLogic.makeLayout(
            EditorWindowLayoutInput(imagePointSize: NSSize(width: 120, height: 80),
                                    maxContentSize: NSSize(width: 1400, height: 900),
                                    minContentSize: NSSize(width: 580, height: 250),
                                    chromeSize: NSSize(width: 24, height: 120),
                                    autoZoomFillRatio: 0.90,
                                    maxAutoUserZoom: 2.0)
        )

        XCTAssertGreaterThan(layout.defaultUserZoomFactor, 1.0)
        XCTAssertLessThanOrEqual(layout.defaultUserZoomFactor, 2.0)
    }
}

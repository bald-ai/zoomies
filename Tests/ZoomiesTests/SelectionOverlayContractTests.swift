import AppKit
import XCTest
@testable import Zoomies

@MainActor
final class SelectionOverlayContractTests: XCTestCase {
    func testDefaultDisplaySelectionPreparesHiddenOverlayWithInjectedPresentation() throws {
        _ = NSApplication.shared
        var frame: CGRect?
        let overlay = SelectionOverlay(presenter: { window, view in
            XCTAssertFalse(window.isVisible)
            frame = window.frame
            XCTAssertEqual(view.frame.size, window.frame.size)
        })
        overlay.beginSelection()
        XCTAssertTrue(overlay.isActive)
        XCTAssertTrue(NSScreen.screens.contains { $0.frame == frame })
        overlay.cancelSelection()
        XCTAssertFalse(overlay.isActive)
    }

    private final class Delegate: SelectionOverlayDelegate {
        var results: [CGRect?] = []
        var screens: [NSScreen] = []
        func selectionOverlay(_ overlay: SelectionOverlay, didFinishWith rectInScreenCoordinates: CGRect?, onScreen screen: NSScreen) {
            XCTAssertFalse(overlay.isActive)
            results.append(rectInScreenCoordinates)
            screens.append(screen)
        }
    }
    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }
    private func key(_ code: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }

    func testOverlayCompletionRejectsSmallSelectionsResetsCacheAndCoalescesStarts() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var presentations = 0
        let overlay = SelectionOverlay(screenProvider: { screen }, presenter: { window, _ in
            presentations += 1
            XCTAssertFalse(window.isVisible)
        })
        let delegate = Delegate()
        overlay.delegate = delegate
        overlay.cancelSelection()
        XCTAssertTrue(delegate.results.isEmpty)
        overlay.beginSelection()
        overlay.beginSelection()
        XCTAssertEqual(presentations, 1)
        let view = try XCTUnwrap(overlay.selectionView)
        view.onComplete?(CGRect(x: 20, y: 30, width: 4, height: 20))
        XCTAssertEqual(delegate.results.count, 1)
        XCTAssertNil(delegate.results[0])
        overlay.beginSelection()
        XCTAssertTrue(overlay.selectionView === view)
        view.onComplete?(CGRect(x: 20, y: 30, width: 50, height: 60))
        XCTAssertEqual(delegate.results[1], CGRect(x: screen.frame.minX + 20, y: screen.frame.minY + 30, width: 50, height: 60))
        XCTAssertTrue(delegate.screens.allSatisfy { $0 === screen })
        overlay.beginSelection()
        overlay.cancelSelection()
        XCTAssertNil(delegate.results[2])
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertNil(overlay.selectionView)
        XCTAssertFalse(overlay.isActive)
        let missing = SelectionOverlay(screenProvider: { nil }, presenter: { _, _ in XCTFail("No screen must not present") })
        missing.beginSelection()
        XCTAssertFalse(missing.isActive)
    }

    func testSelectionViewReverseDragEnterAndCancellationHaveExactResults() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        var results: [CGRect?] = []
        view.onComplete = { results.append($0) }
        XCTAssertTrue(view.acceptsFirstResponder)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
        view.prepareForSelection(backingScaleFactor: 2)
        view.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 10, y: 20)))
        view.mouseUp(with: try mouse(.leftMouseUp, .zero))
        XCTAssertNil(results[0])
        view.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 120)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 20, y: 30)))
        view.keyDown(with: try key(36))
        XCTAssertEqual(results[1], CGRect(x: 20, y: 30, width: 80, height: 90))
        view.mouseUp(with: try mouse(.leftMouseUp, .zero))
        XCTAssertEqual(results[2], results[1])
        view.rightMouseDown(with: try mouse(.rightMouseDown, .zero))
        view.keyDown(with: try key(53))
        XCTAssertNil(results[3])
        XCTAssertNil(results[4])
        view.resetSelectionState()
        view.keyDown(with: try key(36))
        XCTAssertNil(results[5])
    }

    func testSelectionRenderingDimsOutsideAndClearsInteriorWithoutDisplayingWindow() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        func render() throws -> NSBitmapImageRep {
            let rep = try XCTUnwrap(ImageSafety.makeBitmapRep(pixelsWide: 200, pixelsHigh: 200))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
            view.draw(view.bounds)
            return rep
        }
        let instructions = try render()
        XCTAssertEqual(try XCTUnwrap(instructions.colorAt(x: 5, y: 5)).alphaComponent, 0.3, accuracy: 0.02)
        view.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 20, y: 20)))
        view.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 180, y: 180)))
        let selected = try render()
        XCTAssertEqual(try XCTUnwrap(selected.colorAt(x: 100, y: 100)).alphaComponent, 0, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(selected.colorAt(x: 5, y: 5)).alphaComponent, 0.3, accuracy: 0.02)
    }
}

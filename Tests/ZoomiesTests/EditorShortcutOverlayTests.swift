import AppKit
import XCTest
@testable import Zoomies

final class EditorShortcutOverlayTests: XCTestCase {
    private final class HoverEvent: NSEvent {
        var area: NSTrackingArea?
        override var trackingArea: NSTrackingArea? { area }
    }
    func testControllerSchedulesAndCancelsHelpInHiddenWindowWithInjectedFocusAndClock() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let host = try XCTUnwrap(window.contentView)
        let control = NSButton(frame: NSRect(x: 40, y: 40, width: 50, height: 24))
        host.addSubview(control)
        var active = true
        var now: TimeInterval = 100
        var scheduled: [(TimeInterval, DispatchWorkItem)] = []
        let overlay = EditorShortcutOverlayController(window: window, isActive: { active }, clock: { now },
            schedule: { scheduled.append(($0, $1)) }, hints: { [.init(view: control, key: "W", label: "Pen")] })
        func event(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0))
        }
        overlay.handle(try event(.flagsChanged, flags: .command))
        XCTAssertEqual(scheduled.first?.0, 0.5)
        XCTAssertNil(overlay.overlayView)
        now += 0.5
        try XCTUnwrap(scheduled.last).1.perform()
        let first = try XCTUnwrap(overlay.overlayView)
        XCTAssertTrue(first.superview === host)
        XCTAssertFalse(window.isVisible)
        first.updateTrackingAreas()
        XCTAssertEqual(first.trackingAreas.count, 1)
        let hover = HoverEvent()
        hover.area = first.trackingAreas.first
        first.mouseEntered(with: hover)
        let help = try XCTUnwrap(first.subviews.last?.subviews.first as? NSTextField)
        XCTAssertEqual(help.stringValue, "Pen: W")
        hover.area = nil
        first.mouseEntered(with: hover)
        XCTAssertEqual(help.stringValue, "Pen: W")
        first.updateTrackingAreas()
        XCTAssertEqual(first.trackingAreas.count, 1)
        overlay.refreshLabels()
        XCTAssertFalse(overlay.overlayView === first)
        overlay.handle(try event(.keyDown, flags: .command))
        XCTAssertNil(overlay.overlayView)
        overlay.handle(try event(.flagsChanged, flags: []))
        overlay.handle(try event(.flagsChanged, flags: .command))
        let pending = try XCTUnwrap(scheduled.last).1
        active = false
        now += 1
        pending.perform()
        XCTAssertNil(overlay.overlayView)
        overlay.handle(try event(.flagsChanged, flags: []))
        XCTAssertNil(overlay.overlayView)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        XCTAssertNil(overlay.overlayView)
    }

    func testHoldDelayAndImmediateRelease() {
        var state = EditorShortcutHoldState()
        state.modifiersChanged(.command, now: 10)
        state.advance(to: 10.49)
        XCTAssertFalse(state.isVisible)
        state.advance(to: 10.5)
        XCTAssertTrue(state.isVisible)
        state.modifiersChanged([], now: 11)
        XCTAssertFalse(state.isVisible)
        XCTAssertNil(state.deadline)
    }

    func testShortcutCancelsUntilCommandReleased() {
        var state = EditorShortcutHoldState()
        state.modifiersChanged(.command, now: 0)
        state.keyPressed()
        state.modifiersChanged(.command, now: 1)
        state.advance(to: 4)
        XCTAssertFalse(state.isVisible)
        XCTAssertNil(state.deadline)
        state.modifiersChanged([], now: 4)
        state.modifiersChanged(.command, now: 5)
        state.advance(to: 6)
        XCTAssertTrue(state.isVisible)
        state.keyPressed()
        XCTAssertFalse(state.isVisible)
    }

    func testOtherModifierCancelsButCapsLockDoesNot() {
        var state = EditorShortcutHoldState()
        state.modifiersChanged([.command, .capsLock], now: 0)
        state.advance(to: 1)
        XCTAssertTrue(state.isVisible)
        state.modifiersChanged([.command, .shift], now: 2)
        XCTAssertFalse(state.isVisible)
        state.modifiersChanged(.command, now: 3)
        state.advance(to: 4)
        XCTAssertFalse(state.isVisible)
    }

    func testIdleCancellationDoesNotBlockNextHold() {
        var state = EditorShortcutHoldState()
        state.cancel()
        state.modifiersChanged(.command, now: 0)
        state.advance(to: 1)
        XCTAssertTrue(state.isVisible)
    }

    func testTypingBeforeCommandDoesNotBlockHold() {
        var state = EditorShortcutHoldState()
        state.keyPressed()
        state.modifiersChanged(.command, now: 0)
        state.advance(to: 1)
        XCTAssertTrue(state.isVisible)
    }

    func testFocusLossCancelsPendingAndVisibleHold() {
        var state = EditorShortcutHoldState()
        state.modifiersChanged(.command, now: 0)
        state.cancel()
        state.advance(to: 1)
        XCTAssertFalse(state.isVisible)
        state.modifiersChanged([], now: 2)
        state.modifiersChanged(.command, now: 3)
        state.advance(to: 4)
        XCTAssertTrue(state.isVisible)
        state.cancel()
        XCTAssertFalse(state.isVisible)
    }

    func testRefocusingResetsMissedReleaseButDoesNotArmHeldCommand() {
        var state = EditorShortcutHoldState()
        state.modifiersChanged(.command, now: 0)
        state.cancel()
        state.focusGained(flags: [], now: 1)
        state.modifiersChanged(.command, now: 2)
        state.advance(to: 3)
        XCTAssertTrue(state.isVisible)
        state.cancel()
        state.focusGained(flags: .command, now: 4)
        state.advance(to: 5)
        XCTAssertFalse(state.isVisible)
        state.modifiersChanged([], now: 6)
        state.modifiersChanged(.command, now: 7)
        state.advance(to: 8)
        XCTAssertTrue(state.isVisible)
    }

    func testHintsAnchorToRealToolbarWithoutBlockingCanvasOrFocus() throws {
        _ = NSApplication.shared
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(directory) }
        let controller = EditorWindowController(
            image: TestSupport.solidImage(width: 1000, height: 600),
            settingsStore: SettingsStore(fileManager: .default, fileURL: directory.appendingPathComponent("settings.json")))
        defer { controller.dismissWithoutCompletion() }
        let window = try XCTUnwrap(controller.window)
        let host = try XCTUnwrap(window.contentView)
        let overlay = try XCTUnwrap(controller.shortcutOverlay)
        for size in [NSSize(width: 700, height: 300), NSSize(width: 1000, height: 650)] {
            window.setContentSize(size)
            host.layoutSubtreeIfNeeded()
            let previousResponder = window.firstResponder
            let view = overlay.makeView(in: host)
            host.addSubview(view)
            XCTAssertTrue(window.firstResponder === previousResponder)
            XCTAssertNil(view.hitTest(NSPoint(x: 50, y: 50)))
            let badges = Array(view.subviews.prefix(17))
            XCTAssertEqual(view.subviews.count, 18)
            let helpPanel = try XCTUnwrap(view.subviews.last)
            XCTAssertTrue(view.bounds.contains(helpPanel.frame))
            let helpText = try XCTUnwrap(helpPanel.subviews.first as? NSTextField)
            XCTAssertTrue(helpText.stringValue.contains("Hover over a shortcut"))
            let baseline = try XCTUnwrap(badges.first).frame.minY
            for (i, badge) in badges.enumerated() {
                XCTAssertEqual(badge.frame.minY, baseline, accuracy: 0.01)
                XCTAssertEqual(badge.frame.size, NSSize(width: 26, height: 16))
                XCTAssertTrue(view.bounds.contains(badge.frame), "Badge must stay in window")
                for other in badges.dropFirst(i + 1) {
                    XCTAssertFalse(badge.frame.intersects(other.frame), "Badges must not overlap")
                }
            }
            let redoPoint = view.convert(NSPoint(x: badges[10].frame.midX,
                                                  y: badges[10].frame.midY), to: nil)
            let hover = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: redoPoint,
                                                       modifierFlags: .command, timestamp: 0,
                                                       windowNumber: window.windowNumber, context: nil,
                                                       eventNumber: 0, clickCount: 0, pressure: 0))
            view.mouseExited(with: hover)
            XCTAssertEqual(helpText.stringValue, "Redo: Command + Shift + Z")
            XCTAssertNil(view.hitTest(NSPoint(x: badges[10].frame.midX, y: badges[10].frame.midY)))
            view.removeFromSuperview()
        }
    }
}

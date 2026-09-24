import AppKit
import Carbon
import XCTest
@testable import Zoomies

@MainActor
final class ShortcutRecorderContractTests: XCTestCase {
    func testDetachedRecorderCanEnterAndCancelRecordingWithoutWindowActivation() throws {
        let view = ShortcutRecorderView()
        XCTAssertNil(view.window)
        try click(view)
        XCTAssertTrue(view.isRecordingShortcut)
        view.keyDown(with: try key(UInt16(kVK_Escape)))
        XCTAssertFalse(view.isRecordingShortcut)
        XCTAssertNil(view.recordedShortcut)
    }

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                      isARepeat: false, keyCode: code))
    }
    private func click(_ view: ShortcutRecorderView) throws {
        view.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)))
    }
    private func bitmap(_ view: NSView) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 30,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        view.draw(view.bounds)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testShortcutRecordingRejectsInvalidKeysAcceptsModifiedKeyAndCancelsWithoutChange() throws {
        _ = NSApplication.shared
        let view = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        var focused = 0
        var rejected = 0
        var changes: [ShortcutRecorderView.RecordedShortcut] = []
        view.requestFocus = { control in XCTAssertTrue(control === view); focused += 1 }
        view.rejectKey = { rejected += 1 }
        view.onChange = { changes.append($0) }
        let empty = try bitmap(view)
        try click(view)
        XCTAssertEqual(focused, 1)
        XCTAssertTrue(view.isRecordingShortcut)
        XCTAssertNotEqual(try bitmap(view), empty)
        view.keyDown(with: try key(UInt16(kVK_ANSI_A)))
        view.keyDown(with: try key(255, flags: .command))
        XCTAssertEqual(rejected, 2)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertTrue(view.isRecordingShortcut)
        view.keyDown(with: try key(UInt16(kVK_ANSI_4), flags: [.option, .shift]))
        XCTAssertFalse(view.isRecordingShortcut)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.keyCode, UInt32(kVK_ANSI_4))
        XCTAssertEqual(changes.first?.carbonFlags, UInt32(optionKey | shiftKey))
        XCTAssertEqual(view.recordedShortcut?.keyCode, UInt32(kVK_ANSI_4))
        let saved = try bitmap(view)
        XCTAssertNotEqual(saved, empty)
        try click(view)
        view.keyDown(with: try key(UInt16(kVK_Escape)))
        XCTAssertFalse(view.isRecordingShortcut)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(try bitmap(view), saved)
        try click(view)
        _ = view.resignFirstResponder()
        XCTAssertFalse(view.isRecordingShortcut)
        XCTAssertEqual(changes.count, 1)
    }
}

import XCTest
import AppKit
import Carbon
@testable import Zoomies

final class PhysicalKeyLabelTests: XCTestCase {
    private func label(_ code: Int, layoutID: String, fallback: String = "?") throws -> String {
        let filter = [kTISPropertyInputSourceID as String: layoutID] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
        let source = try XCTUnwrap(sources.first, "Missing system layout: \(layoutID)")
        let property = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData))
        let data = unsafeBitCast(property, to: CFData.self)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        return PhysicalKeyLabel.translatedName(for: UInt16(code),
            layout: UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self), fallback: fallback)
    }

    func testSamePhysicalKeyHasDifferentEnglishAndCzechLabels() throws {
        XCTAssertEqual(try label(kVK_ANSI_Y, layoutID: "com.apple.keylayout.US"), "Y")
        XCTAssertEqual(try label(kVK_ANSI_Y, layoutID: "com.apple.keylayout.Czech"), "Z")
        XCTAssertEqual(try label(kVK_ANSI_2, layoutID: "com.apple.keylayout.Czech"), "Ě")
    }

    func testDeadKeyHasVisibleLabelAndControlKeyUsesFallback() throws {
        // macOS supplies an apostrophe as the display label for this accent key.
        XCTAssertEqual(try label(kVK_ANSI_Equal, layoutID: "com.apple.keylayout.Czech"), "'")
        XCTAssertEqual(try label(kVK_Return, layoutID: "com.apple.keylayout.US", fallback: "Return"), "Return")
    }

    func testLayoutNotificationRefreshesAttachedRecorder() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let recorder = ShortcutRecorderView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(recorder)
        recorder.needsDisplay = false
        DistributedNotificationCenter.default().post(name: PhysicalKeyLabel.layoutChanged, object: nil)
        XCTAssertTrue(recorder.needsDisplay)
        window.close()
    }
}

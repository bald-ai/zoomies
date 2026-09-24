import XCTest
import AppKit
import Carbon
@testable import Zoomies

final class HotKeyServiceTests: XCTestCase {
    func testCarbonCallbackParsesSyntheticEventAndRejectsMissingParameters() throws {
        var ids: [EventHotKeyID] = []
        var calls = 0
        let service = HotKeyService(registerHotKey: { _, _, id in ids.append(id); return EventHotKeyRef(bitPattern: ids.count) }, unregisterHotKey: { _ in })
        service.registerShortcuts(settings: .default, areaHandler: { calls += 1 }, fullHandler: {},
            reopenFinderSelectionHandler: {}, openScratchpadHandler: {}, toggleRecordingHandler: {})
        let context = Unmanaged.passUnretained(service).toOpaque()
        XCTAssertEqual(hotKeyEventHandler(nil, nil, context), noErr)
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
        let synthetic = try XCTUnwrap(event)
        defer { ReleaseEvent(synthetic) }
        XCTAssertEqual(hotKeyEventHandler(nil, synthetic, nil), noErr)
        XCTAssertNotEqual(hotKeyEventHandler(nil, synthetic, context), noErr)
        XCTAssertEqual(calls, 0)
        var id = try XCTUnwrap(ids.first)
        XCTAssertEqual(SetEventParameter(synthetic, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        MemoryLayout<EventHotKeyID>.size, &id), noErr)
        XCTAssertEqual(hotKeyEventHandler(nil, synthetic, context), noErr)
        XCTAssertEqual(calls, 1)
    }

    func testEveryFailedRegistrationReportsCommandNameAndCannotDispatch() {
        var failures: [String] = []
        var calls = 0
        let service = HotKeyService(registerHotKey: { _, _, _ in nil }, unregisterHotKey: { _ in XCTFail("No registrations to release") })
        service.onRegistrationFailures = { failures = $0 }
        service.registerShortcuts(settings: .default, areaHandler: { calls += 1 }, fullHandler: { calls += 1 },
            reopenFinderSelectionHandler: { calls += 1 }, openScratchpadHandler: { calls += 1 }, toggleRecordingHandler: { calls += 1 })
        XCTAssertEqual(failures.count, 5)
        for (message, name) in zip(failures, ["Screenshot Area:", "Screenshot Full:", "Reopen Finder Selection:", "Scratchpad:", "Screen Recording:"]) {
            XCTAssertTrue(message.hasPrefix(name))
        }
        XCTAssertEqual(calls, 0)
    }

    func testCarbonModifierFlagsMapsExpectedFlags() {
        let cocoa: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .capsLock]
        let carbon = HotKeyService.carbonModifierFlags(from: cocoa)

        XCTAssertNotEqual(carbon & UInt32(cmdKey), 0)
        XCTAssertNotEqual(carbon & UInt32(shiftKey), 0)
        XCTAssertNotEqual(carbon & UInt32(optionKey), 0)
        XCTAssertNotEqual(carbon & UInt32(controlKey), 0)
        XCTAssertNotEqual(carbon & UInt32(alphaLock), 0)
    }

    func testDescribeShortcutIncludesModifiersAndKeyName() {
        let desc = HotKeyService.describeShortcut(keyCode: UInt32(kVK_ANSI_6),
                                                  carbonFlags: UInt32(cmdKey | shiftKey))
        XCTAssertTrue(desc.contains("⌘"))
        XCTAssertTrue(desc.contains("⇧"))
        XCTAssertTrue(desc.hasSuffix(PhysicalKeyLabel.name(for: UInt16(kVK_ANSI_6), fallback: "6")))
    }

    func testDescribeShortcutDoesNotTrapOnOutOfRangeKeyCode() {
        let desc = HotKeyService.describeShortcut(keyCode: UInt32.max, carbonFlags: UInt32(cmdKey))
        XCTAssertTrue(desc.contains("⌘"))
        XCTAssertTrue(desc.hasSuffix("?"))
    }

    func testIsAllowedKeyCodeRecognizesKnownAndUnknown() {
        XCTAssertTrue(HotKeyService.isAllowedKeyCode(UInt16(kVK_ANSI_A)))
        XCTAssertTrue(HotKeyService.isAllowedKeyCode(UInt16(kVK_F12)))
        XCTAssertFalse(HotKeyService.isAllowedKeyCode(0xFFFF))
    }

    func testUpdateShortcutsBeforeRegistrationIsNoOp() {
        let service = HotKeyService()
        service.updateShortcuts(settings: .default)
    }

    func testRegisterAndUpdateShortcutsRoutesRegisteredHotKeys() {
        var registeredIDs: [EventHotKeyID] = []
        var unregisteredRefs: [EventHotKeyRef] = []
        let service = HotKeyService(
            registerHotKey: { _, _, id in
                registeredIDs.append(id)
                return EventHotKeyRef(bitPattern: registeredIDs.count)
            },
            unregisterHotKey: { ref in
                unregisteredRefs.append(ref)
            }
        )
        var areaCalls = 0
        var fullCalls = 0
        var reopenCalls = 0
        var scratchpadCalls = 0
        var recordingCalls = 0

        service.registerShortcuts(
            settings: .default,
            areaHandler: { areaCalls += 1 },
            fullHandler: { fullCalls += 1 },
            reopenFinderSelectionHandler: { reopenCalls += 1 },
            openScratchpadHandler: { scratchpadCalls += 1 },
            toggleRecordingHandler: { recordingCalls += 1 }
        )

        XCTAssertEqual(registeredIDs.count, 5)
        service.handleHotKey(with: registeredIDs[0])
        service.handleHotKey(with: registeredIDs[1])
        service.handleHotKey(with: registeredIDs[2])
        service.handleHotKey(with: registeredIDs[3])
        service.handleHotKey(with: registeredIDs[4])
        XCTAssertEqual(areaCalls, 1)
        XCTAssertEqual(fullCalls, 1)
        XCTAssertEqual(reopenCalls, 1)
        XCTAssertEqual(scratchpadCalls, 1)
        XCTAssertEqual(recordingCalls, 1)

        service.updateShortcuts(settings: .default)

        XCTAssertEqual(unregisteredRefs.count, 5)
        XCTAssertEqual(registeredIDs.count, 10)
        service.handleHotKey(with: registeredIDs[5])
        XCTAssertEqual(areaCalls, 2)
    }
}

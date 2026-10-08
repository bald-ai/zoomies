import XCTest
import Carbon
@testable import Zoomies

final class SettingsTests: XCTestCase {
    func testNormalizedClampsMaxWidthAndCounter() {
        var settings = Settings.default
        settings.maxWidth = -40
        settings.screenshotCounter = 0

        let normalized = settings.normalized()
        XCTAssertEqual(normalized.maxWidth, 0)
        XCTAssertEqual(normalized.screenshotCounter, 1)
    }

    func testScreenshotFilenameIsFixed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2024, month: 1, day: 30, hour: 14, minute: 23, second: 45))!
        XCTAssertEqual(ScreenshotFilename.make(date: date, counter: 7), "Screenshot_2024-01-30_14.23.45_7")
    }

    func testLegacyFilenameTemplateKeyIsIgnoredAndDropped() throws {
        let legacy = #"{ "filenameTemplate": { "blocks": [] }, "maxWidth": 800 }"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertEqual(decoded.maxWidth, 800)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
        XCTAssertFalse(encoded.contains("filenameTemplate"))
    }

    func testShortcutsBackwardCompatibleDecodingDefaultsMissingKey() throws {
        let legacy = """
        {
          "screenshotArea": { "keyCode": 20, "modifierFlags": 768 },
          "screenshotFull": { "keyCode": 21, "modifierFlags": 768 }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Shortcuts.self, from: legacy)
        XCTAssertEqual(decoded.screenshotArea.keyCode, 20)
        XCTAssertEqual(decoded.screenshotFull.keyCode, 21)
        XCTAssertEqual(decoded.reopenFinderSelection, Shortcuts.default.reopenFinderSelection)
    }

    func testDecodeWithoutOpenScratchpadFallsBackToDefault() throws {
        let legacy = """
        {
          "screenshotArea": { "keyCode": 20, "modifierFlags": 768 },
          "screenshotFull": { "keyCode": 21, "modifierFlags": 768 },
          "reopenFinderSelection": { "keyCode": 19, "modifierFlags": 768 }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Shortcuts.self, from: legacy)
        XCTAssertEqual(decoded.openScratchpad, Shortcuts.default.openScratchpad)
    }

    func testDefaultShortcutsUseOptionShiftNumbers() {
        XCTAssertEqual(Shortcuts.default.screenshotArea.keyCode, UInt32(kVK_ANSI_4))
        XCTAssertEqual(Shortcuts.default.screenshotArea.modifierFlags, UInt32(optionKey | shiftKey))
        XCTAssertEqual(Shortcuts.default.screenshotFull.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(Shortcuts.default.screenshotFull.modifierFlags, UInt32(optionKey | shiftKey))
        XCTAssertEqual(Shortcuts.default.reopenFinderSelection.keyCode, UInt32(kVK_ANSI_2))
        XCTAssertEqual(Shortcuts.default.reopenFinderSelection.modifierFlags, UInt32(optionKey | shiftKey))
        XCTAssertEqual(Shortcuts.default.openScratchpad.keyCode, UInt32(kVK_ANSI_1))
        XCTAssertEqual(Shortcuts.default.openScratchpad.modifierFlags, UInt32(optionKey | shiftKey))
    }

    func testNormalizedMigratesRetiredDefaultShortcuts() {
        var settings = Settings.default
        settings.shortcuts = Shortcuts(
            screenshotArea: Shortcut(keyCode: UInt32(kVK_ANSI_4),
                                      modifierFlags: UInt32(controlKey | shiftKey)),
            screenshotFull: Shortcut(keyCode: UInt32(kVK_ANSI_3),
                                      modifierFlags: UInt32(controlKey | shiftKey)),
            reopenFinderSelection: Shortcut(keyCode: UInt32(kVK_ANSI_2),
                                             modifierFlags: UInt32(controlKey | shiftKey)),
            openScratchpad: Shortcut(keyCode: UInt32(kVK_ANSI_5),
                                     modifierFlags: UInt32(cmdKey | shiftKey))
        )

        XCTAssertEqual(settings.normalized().shortcuts, Shortcuts.default)
    }

    func testNormalizedMigratesRetiredCommandShiftDefaultsWhenNotCustomized() {
        var settings = Settings.default
        settings.shortcuts = Shortcuts(
            screenshotArea: Shortcut(keyCode: UInt32(kVK_ANSI_4),
                                      modifierFlags: UInt32(cmdKey | shiftKey)),
            screenshotFull: Shortcut(keyCode: UInt32(kVK_ANSI_3),
                                      modifierFlags: UInt32(cmdKey | shiftKey)),
            reopenFinderSelection: Shortcut(keyCode: UInt32(kVK_ANSI_2),
                                             modifierFlags: UInt32(cmdKey | shiftKey)),
            openScratchpad: Shortcuts.default.openScratchpad
        )

        XCTAssertEqual(settings.normalized().shortcuts, Shortcuts.default)
    }

    func testNormalizedPreservesRetiredLookingShortcutsWhenCustomized() {
        var settings = Settings.default
        let customized = Shortcuts(
            screenshotArea: Shortcut(keyCode: UInt32(kVK_ANSI_4),
                                      modifierFlags: UInt32(cmdKey | shiftKey)),
            screenshotFull: Shortcut(keyCode: UInt32(kVK_ANSI_3),
                                      modifierFlags: UInt32(cmdKey | shiftKey)),
            reopenFinderSelection: Shortcut(keyCode: UInt32(kVK_ANSI_2),
                                             modifierFlags: UInt32(cmdKey | shiftKey)),
            openScratchpad: Shortcut(keyCode: UInt32(kVK_ANSI_5),
                                     modifierFlags: UInt32(cmdKey | shiftKey))
        )
        settings.shortcuts = customized
        settings.shortcutsCustomized = true

        XCTAssertEqual(settings.normalized().shortcuts, customized)
    }

    func testNormalizedMigratesOptionShift5ScratchpadUnlessCustomized() {
        var settings = Settings.default
        let oldShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_5),
                                   modifierFlags: UInt32(optionKey | shiftKey))
        settings.shortcuts.openScratchpad = oldShortcut
        XCTAssertEqual(settings.normalized().shortcuts.openScratchpad, Shortcuts.default.openScratchpad)

        settings.shortcutsCustomized = true
        XCTAssertEqual(settings.normalized().shortcuts.openScratchpad, oldShortcut)
    }

    func testNormalizedMigratesTemporaryControlShiftNScratchpadShortcut() {
        var settings = Settings.default
        settings.shortcuts.openScratchpad = Shortcut(
            keyCode: UInt32(kVK_ANSI_N),
            modifierFlags: UInt32(controlKey | shiftKey)
        )

        XCTAssertEqual(settings.normalized().shortcuts.openScratchpad, Shortcuts.default.openScratchpad)
    }

    func testEncodeIncludesOpenScratchpad() throws {
        let data = try JSONEncoder().encode(Shortcuts.default)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["openScratchpad"])
    }

    func testDecodeRoundTripPreservesCustomOpenScratchpad() throws {
        var shortcuts = Shortcuts.default
        shortcuts.openScratchpad = Shortcut(keyCode: 46, modifierFlags: 256) // arbitrary custom combo

        let data = try JSONEncoder().encode(shortcuts)
        let decoded = try JSONDecoder().decode(Shortcuts.self, from: data)

        XCTAssertEqual(decoded.openScratchpad, shortcuts.openScratchpad)
        XCTAssertEqual(decoded, shortcuts)
    }

    func testDecodeLegacySettingsDefaultsShortcutsCustomizedToFalse() throws {
        let legacy = """
        {
          "maxWidth": 0,
          "filenameTemplate": { "blocks": [] },
          "shortcuts": {
            "screenshotArea": { "keyCode": 21, "modifierFlags": 768 },
            "screenshotFull": { "keyCode": 20, "modifierFlags": 768 },
            "reopenFinderSelection": { "keyCode": 19, "modifierFlags": 768 },
            "openScratchpad": { "keyCode": 23, "modifierFlags": 2560 }
          },
          "screenshotCounter": 1
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)

        XCTAssertFalse(decoded.shortcutsCustomized)
        XCTAssertTrue(decoded.confirmBeforeClosing, "Confirmation must be enabled by default for existing installations.")
    }

    func testCloseConfirmationPreferenceRoundTrips() throws {
        var settings = Settings.default
        settings.confirmBeforeClosing = false

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: encoded)

        XCTAssertFalse(decoded.confirmBeforeClosing)
    }

    func testNextScreenshotCounterDoesNotTrapOnOverflow() {
        XCTAssertEqual(Settings.nextScreenshotCounter(after: 1), 2)
        XCTAssertEqual(Settings.nextScreenshotCounter(after: 0), 2)
        XCTAssertEqual(Settings.nextScreenshotCounter(after: -8), 2)
        XCTAssertEqual(Settings.nextScreenshotCounter(after: Int.max), Int.max)
    }

    func testNormalizedRepairsOnlyInvalidShortcutAndReportsRepair() {
        var settings = Settings.default
        settings.screenshotCounter = 9
        settings.shortcuts.screenshotArea = Shortcut(keyCode: UInt32.max, modifierFlags: 768)
        settings.shortcutsCustomized = true

        let result = settings.normalizedReportingRepairs()
        XCTAssertTrue(result.repairedInvalidFields)
        XCTAssertEqual(result.settings.screenshotCounter, 9)
        XCTAssertEqual(result.settings.shortcuts.screenshotArea, Shortcuts.default.screenshotArea)
        XCTAssertEqual(result.settings.shortcuts.screenshotFull, Shortcuts.default.screenshotFull)
        XCTAssertTrue(result.settings.shortcutsCustomized)
    }

    func testNormalizedDoesNotTreatRetiredShortcutMigrationAsRepair() {
        var settings = Settings.default
        settings.shortcuts = Shortcuts(
            screenshotArea: Shortcut(keyCode: UInt32(kVK_ANSI_4),
                                      modifierFlags: UInt32(controlKey | shiftKey)),
            screenshotFull: Shortcut(keyCode: UInt32(kVK_ANSI_3),
                                      modifierFlags: UInt32(controlKey | shiftKey)),
            reopenFinderSelection: Shortcut(keyCode: UInt32(kVK_ANSI_2),
                                             modifierFlags: UInt32(controlKey | shiftKey)),
            openScratchpad: Shortcut(keyCode: UInt32(kVK_ANSI_5),
                                     modifierFlags: UInt32(cmdKey | shiftKey))
        )

        let result = settings.normalizedReportingRepairs()
        XCTAssertFalse(result.repairedInvalidFields)
        XCTAssertEqual(result.settings.shortcuts, Shortcuts.default)
    }

}

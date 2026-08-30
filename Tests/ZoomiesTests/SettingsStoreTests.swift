import XCTest
@testable import Zoomies

final class SettingsStoreTests: XCTestCase {
    func testLoadCreatesDefaultsOnFirstLaunch() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        let store = SettingsStore(fileManager: .default, fileURL: fileURL)

        store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(store.settings.maxWidth, Settings.default.maxWidth)
    }

    func testLoadMigratesLegacySettingsBeforeCreatingDefaults() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("Application Support/Zoomies/settings.json")
        let legacyFileURL = root.appendingPathComponent(".screenshot_app_settings.json")
        var legacySettings = Settings.default
        legacySettings.screenshotCounter = 42
        legacySettings.notePrefixEnabled = true
        legacySettings.notePrefix = "TODO"
        let data = try JSONEncoder().encode(legacySettings)
        try data.write(to: legacyFileURL, options: .atomic)

        let store = SettingsStore(fileManager: .default, fileURL: fileURL, legacyFileURL: legacyFileURL)
        store.load()

        XCTAssertEqual(store.settings.screenshotCounter, 42)
        XCTAssertEqual(store.settings.notePrefix, "TODO")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFileURL.path))
    }

    func testLoadValidFileNormalizesDecodedSettings() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        var raw = Settings.default
        raw.maxWidth = -5
        raw.screenshotCounter = 0
        raw.notePrefix = String(repeating: "x", count: 200)
        let data = try JSONEncoder().encode(raw)
        try data.write(to: fileURL, options: .atomic)

        let store = SettingsStore(fileManager: .default, fileURL: fileURL)
        store.load()

        XCTAssertTrue(store.didRepairInvalidSettingsOnLastLoad)
        XCTAssertEqual(store.settings.maxWidth, 0)
        XCTAssertEqual(store.settings.screenshotCounter, 1)
        XCTAssertEqual(store.settings.notePrefix.count, 50)

        let persisted = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.maxWidth, 0)
        XCTAssertEqual(persisted.screenshotCounter, 1)
        XCTAssertEqual(persisted.notePrefix.count, 50)

        store.load()
        XCTAssertFalse(store.didRepairInvalidSettingsOnLastLoad)
    }

    func testLoadCorruptFileFallsBackToDefaultsWithoutOverwrite() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        let original = Data("{not-json".utf8)
        try original.write(to: fileURL, options: .atomic)

        let store = SettingsStore(fileManager: .default, fileURL: fileURL)
        store.load()

        XCTAssertEqual(store.settings.maxWidth, Settings.default.maxWidth)
        let onDisk = try Data(contentsOf: fileURL)
        XCTAssertEqual(onDisk, original)
    }

    func testUpdateNormalizesAndPersists() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        let store = SettingsStore(fileManager: .default, fileURL: fileURL)
        store.load()

        store.update { settings in
            settings.maxWidth = -100
            settings.screenshotCounter = 0
        }

        XCTAssertEqual(store.settings.maxWidth, 0)
        XCTAssertEqual(store.settings.screenshotCounter, 1)

        let decoded = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(decoded.maxWidth, 0)
        XCTAssertEqual(decoded.screenshotCounter, 1)
    }

    func testLoadRepairsInvalidShortcutKeyCodesWithoutTouchingValidFields() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        var raw = Settings.default
        raw.screenshotCounter = 42
        raw.notePrefixEnabled = true
        raw.notePrefix = "keep me"
        raw.shortcutsCustomized = true
        raw.shortcuts.screenshotArea = Shortcut(keyCode: UInt32.max, modifierFlags: 768)
        raw.shortcuts.openScratchpad = Shortcut(keyCode: 0xFFFF, modifierFlags: 256)
        try JSONEncoder().encode(raw).write(to: fileURL, options: .atomic)

        let store = SettingsStore(fileManager: .default, fileURL: fileURL)
        store.load()

        XCTAssertTrue(store.didRepairInvalidSettingsOnLastLoad)
        XCTAssertEqual(store.settings.screenshotCounter, 42)
        XCTAssertEqual(store.settings.notePrefix, "keep me")
        XCTAssertTrue(store.settings.notePrefixEnabled)
        XCTAssertTrue(store.settings.shortcutsCustomized)
        XCTAssertEqual(store.settings.shortcuts.screenshotArea, Shortcuts.default.screenshotArea)
        XCTAssertEqual(store.settings.shortcuts.openScratchpad, Shortcuts.default.openScratchpad)
        XCTAssertEqual(store.settings.shortcuts.screenshotFull, Shortcuts.default.screenshotFull)
        XCTAssertEqual(store.settings.shortcuts.reopenFinderSelection, Shortcuts.default.reopenFinderSelection)
    }

    func testLoadDoesNotReportRepairForValidMaximumCounter() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        var raw = Settings.default
        raw.screenshotCounter = Int.max
        try JSONEncoder().encode(raw).write(to: fileURL, options: .atomic)

        let store = SettingsStore(fileManager: .default, fileURL: fileURL)
        store.load()

        XCTAssertFalse(store.didRepairInvalidSettingsOnLastLoad)
        XCTAssertEqual(store.settings.screenshotCounter, Int.max)
    }

    func testCorruptFileFallbackDoesNotClaimARepair() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        try Data("{not-json".utf8).write(to: fileURL, options: .atomic)

        let store = SettingsStore(fileManager: .default, fileURL: fileURL)
        store.load()

        XCTAssertFalse(store.didRepairInvalidSettingsOnLastLoad)
        XCTAssertEqual(store.settings.maxWidth, Settings.default.maxWidth)
        XCTAssertEqual(store.settings.screenshotCounter, Settings.default.screenshotCounter)
    }

    func testLoadDoesNotReportRepairWhenPersistenceFails() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let fileURL = root.appendingPathComponent("settings.json")
        var raw = Settings.default
        raw.maxWidth = -5
        raw.screenshotCounter = 42
        raw.notePrefixEnabled = true
        raw.notePrefix = "keep me"
        try JSONEncoder().encode(raw).write(to: fileURL, options: .atomic)
        let originalData = try Data(contentsOf: fileURL)

        let store = SettingsStore(
            fileManager: .default,
            fileURL: fileURL,
            persistWriter: { _, _ in
                throw NSError(
                    domain: "ZoomiesTests",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "simulated persist failure"]
                )
            }
        )
        store.load()

        XCTAssertFalse(store.didRepairInvalidSettingsOnLastLoad)
        XCTAssertEqual(store.settings.maxWidth, 0)
        XCTAssertEqual(store.settings.screenshotCounter, 42)
        XCTAssertEqual(store.settings.notePrefix, "keep me")
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)

        store.load()
        XCTAssertFalse(store.didRepairInvalidSettingsOnLastLoad)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }
}

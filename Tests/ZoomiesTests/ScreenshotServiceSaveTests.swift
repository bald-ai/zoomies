import XCTest
import AppKit
@testable import Zoomies

private final class NoopSoundPlayer: ScreenshotSoundPlaying {
    func playCaptureSound() {}
}

final class ScreenshotServiceSaveTests: XCTestCase {
    func testFreshServiceAllowsCaptureEntrypointsWithoutUpfrontPermissionGate() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let settingsStore = SettingsStore(fileManager: .default, fileURL: root.appendingPathComponent("settings.json"))
        settingsStore.load()

        let backup = BackupService(fileManager: .default, backupsDirectory: root.appendingPathComponent("backups"))
        let clipboard = ClipboardService(fileManager: .default, cacheDirectory: root.appendingPathComponent("clipboard"))
        let service = ScreenshotService(settingsStore: settingsStore,
                                        backupService: backup,
                                        clipboardService: clipboard,
                                        fileManager: .default,
                                        desktopDirectory: root.appendingPathComponent("Desktop", isDirectory: true),
                                        soundPlayer: NoopSoundPlayer())

        XCTAssertTrue(service.canStartAreaCapture())
        XCTAssertTrue(service.canStartFullScreenCapture())
    }

    func testSaveImageToDesktopWritesFileAndIncrementsCounter() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let settingsFile = root.appendingPathComponent("settings.json")
        let settingsStore = SettingsStore(fileManager: .default, fileURL: settingsFile)
        settingsStore.load()
        settingsStore.update { settings in
            settings.screenshotCounter = 7
            settings.maxWidth = 0
        }

        let backup = BackupService(fileManager: .default, backupsDirectory: root.appendingPathComponent("backups"))
        let clipboard = ClipboardService(fileManager: .default, cacheDirectory: root.appendingPathComponent("clipboard"))
        let service = ScreenshotService(settingsStore: settingsStore,
                                        backupService: backup,
                                        clipboardService: clipboard,
                                        fileManager: .default,
                                        desktopDirectory: desktop,
                                        soundPlayer: NoopSoundPlayer())

        let output = try service.saveImageToDesktop(TestSupport.solidImage(width: 200, height: 100))

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(output.lastPathComponent.hasPrefix("Screenshot_"))
        XCTAssertTrue(output.lastPathComponent.hasSuffix("_7.png"))
        XCTAssertEqual(settingsStore.settings.screenshotCounter, 8)
        // The captured file must contain real PNG bytes, not JPEG-in-a-.png.
        let savedData = try Data(contentsOf: output)
        XCTAssertTrue(PNGMetadata.isPNG(savedData), "Saved capture should be a real PNG")
    }

    func testSaveImageToDesktopUsesSuffixWhenBaseNameExists() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let baseName = ScreenshotFilename.make(date: date, counter: 1)
        let existing = desktop.appendingPathComponent("\(baseName).png")
        try Data("existing".utf8).write(to: existing, options: .atomic)

        let settingsStore = SettingsStore(fileManager: .default, fileURL: root.appendingPathComponent("settings.json"))
        settingsStore.load()
        settingsStore.update { settings in
            settings.screenshotCounter = 1
        }

        let backup = BackupService(fileManager: .default, backupsDirectory: root.appendingPathComponent("backups"))
        let clipboard = ClipboardService(fileManager: .default, cacheDirectory: root.appendingPathComponent("clipboard"))
        let service = ScreenshotService(settingsStore: settingsStore,
                                        backupService: backup,
                                        clipboardService: clipboard,
                                        fileManager: .default,
                                        desktopDirectory: desktop,
                                        soundPlayer: NoopSoundPlayer(),
                                        now: { date })

        let output = try service.saveImageToDesktop(TestSupport.solidImage(width: 120, height: 60))
        XCTAssertEqual(output.lastPathComponent, "\(baseName)_2.png")
    }

    func testSaveImageToDesktopResizesWhenMaxWidthSet() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let settingsStore = SettingsStore(fileManager: .default, fileURL: root.appendingPathComponent("settings.json"))
        settingsStore.load()
        settingsStore.update { settings in
            settings.screenshotCounter = 2
            settings.maxWidth = 50
        }

        let backup = BackupService(fileManager: .default, backupsDirectory: root.appendingPathComponent("backups"))
        let clipboard = ClipboardService(fileManager: .default, cacheDirectory: root.appendingPathComponent("clipboard"))
        let service = ScreenshotService(settingsStore: settingsStore,
                                        backupService: backup,
                                        clipboardService: clipboard,
                                        fileManager: .default,
                                        desktopDirectory: desktop,
                                        soundPlayer: NoopSoundPlayer())

        let output = try service.saveImageToDesktop(TestSupport.solidImage(width: 300, height: 150))
        let saved = NSImage(contentsOf: output)
        XCTAssertNotNil(saved)
        XCTAssertLessThanOrEqual(saved?.size.width ?? 0, 50)
    }

    func testSaveImageToDesktopDoesNotTrapWhenCounterIsMax() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let settingsStore = SettingsStore(
            fileManager: .default,
            fileURL: root.appendingPathComponent("settings.json")
        )
        settingsStore.load()
        settingsStore.update { settings in
            settings.screenshotCounter = Int.max
        }

        let service = ScreenshotService(
            settingsStore: settingsStore,
            backupService: BackupService(
                fileManager: .default,
                backupsDirectory: root.appendingPathComponent("backups")
            ),
            clipboardService: ClipboardService(
                fileManager: .default,
                cacheDirectory: root.appendingPathComponent("clipboard")
            ),
            fileManager: .default,
            desktopDirectory: desktop,
            soundPlayer: NoopSoundPlayer()
        )

        let output = try service.saveImageToDesktop(TestSupport.solidImage(width: 40, height: 20))
        XCTAssertTrue(output.lastPathComponent.contains(String(Int.max)))
        XCTAssertEqual(settingsStore.settings.screenshotCounter, Int.max)
    }
}

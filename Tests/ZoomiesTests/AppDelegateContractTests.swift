import AppKit
import Carbon
import XCTest
@testable import Zoomies

@MainActor
final class AppDelegateContractTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let root: URL
        let store: SettingsStore
        let clipboard: ClipboardService
        let backup: BackupService
        let sound = ScreenshotSoundPlayer(locateResource: { nil })
        var registered: [EventHotKeyID] = []
        var areaCalls = 0
        var fullCalls = 0
        var workflows: [ScreenshotWorkflowController] = []
        var notes: [DedicatedNotePanelController] = []
        var videos: [VideoRenameWorkflowController] = []
        var settings: [SettingsWindowController] = []
        var welcome: [String] = []
        var terminationReplies: [Bool] = []
        var finderResult: Result<FinderSelectionService.Selection, Error> = .success(.none)
        var tray: TrayService?
        let trayButton = NSButton()
        lazy var hotKeys = HotKeyService(registerHotKey: { [unowned self] _, _, id in
            registered.append(id)
            return EventHotKeyRef(bitPattern: registered.count)
        }, unregisterHotKey: { _ in })
        lazy var screenshot = ScreenshotService(settingsStore: store, backupService: backup, clipboardService: clipboard,
            desktopDirectory: root.appendingPathComponent("desktop"), soundPlayer: sound,
            areaCapture: { [unowned self] in areaCalls += 1; return nil },
            captureScreen: { [unowned self] _ in fullCalls += 1; return nil },
            workflowPresenter: { [unowned self] in workflows.append($0) }, errorPresenter: { _, _ in })
        lazy var scratchpad = ScratchpadService(clipboardService: clipboard, desktopDirectory: root.appendingPathComponent("notes"),
            showNote: { [unowned self] in notes.append($0) }, showRename: { _ in }, errorPresenter: { _, _ in })
        let recording: ScreenRecordingService
        lazy var app = AppDelegate(settingsStore: store, makeServices: { [unowned self] settings in
            XCTAssertTrue(settings === store)
            return .init(backup: backup, clipboard: clipboard, screenshot: screenshot, scratchpad: scratchpad,
                         hotKeys: hotKeys, recording: recording, sound: sound)
        }, presentation: .init(tray: { [unowned self] onSettings in
            let result = TrayService(button: trayButton, onShowSettings: onSettings, onQuit: {})
            tray = result
            return result
        }, welcome: { [unowned self] in welcome.append($0.messageText) },
           video: { [unowned self] in videos.append($0) },
           settings: { [unowned self] in settings.append($0) },
           terminationReply: { [unowned self] in terminationReplies.append($0) }),
           finderSelection: { [unowned self] in try finderResult.get() })

        init() throws {
            root = try TestSupport.makeTemporaryDirectory()
            store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            backup = BackupService(backupsDirectory: root.appendingPathComponent("backups"))
            clipboard = ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { _ in true })
            if #available(macOS 15, *) {
                recording = ScreenRecordingService(recordingDirectory: root.appendingPathComponent("videos"),
                    errorPresenter: { _, _ in }) { _, _ in throw NSError(domain: "fixture recording", code: 1) }
            } else { recording = ScreenRecordingService() }
        }
        func command(_ index: Int) { hotKeys.handleHotKey(with: registered[index]) }
        deinit { TestSupport.removeIfExists(root) }
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Application fixture did not finish its queued work")
    }

    func testStartupPurgesSessionFilesAndWiresCaptureNoteVideoAndSettingsCommands() async throws {
        _ = NSApplication.shared
        let f = try Fixture()
        let stale = f.root.appendingPathComponent("cache/stale")
        try Data("old".utf8).write(to: stale)
        f.app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await f.sound.flush()
        try await waitUntil { f.welcome.count == 1 }
        XCTAssertEqual(f.welcome, ["Welcome to Zoomies"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(f.registered.count, 5)
        XCTAssertFalse(f.app.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        XCTAssertEqual(f.app.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        f.command(0)
        try await waitUntil { f.areaCalls == 1 && !f.screenshot.isBusyForUserCommands }
        f.command(1)
        XCTAssertEqual(f.fullCalls, 1)
        f.command(3)
        try await waitUntil { f.notes.count == 1 }
        XCTAssertFalse(try XCTUnwrap(f.notes[0].window).isVisible)
        f.command(0)
        XCTAssertEqual(f.areaCalls, 1)
        f.notes[0].onAction?(.close)
        f.tray?.menu.performActionForItem(at: 0)
        try await waitUntil { f.settings.count == 1 }
        f.tray?.menu.performActionForItem(at: 0)
        try await waitUntil { f.settings.count == 2 }
        XCTAssertTrue(f.settings[0] === f.settings[1])
        XCTAssertFalse(try XCTUnwrap(f.settings[0].window).isVisible)
        let video = f.root.appendingPathComponent("fixture.mp4")
        try Data("video".utf8).write(to: video)
        f.recording.onRecordingSaved?(video)
        f.recording.onRecordingSaved?(video)
        XCTAssertEqual(f.videos.count, 1)
        f.command(1)
        XCTAssertEqual(f.fullCalls, 1)
        f.videos[0].handleRenameAction(.close)
        f.command(1)
        XCTAssertEqual(f.fullCalls, 2)
        XCTAssertEqual(try Data(contentsOf: video), Data("video".utf8))
        f.command(4)
        if ScreenRecordingService.isSupported {
            XCTAssertEqual(f.app.applicationShouldTerminate(NSApplication.shared), .terminateLater)
            try await waitUntil { !f.recording.isBusyForUserCommands }
            XCTAssertEqual(f.terminationReplies, [true])
        }
    }

    func testFinderWarningsAndReopenAreDeliveredThroughApplicationWiring() async throws {
        _ = NSApplication.shared
        let activator = AlertPresenter.appActivator
        let runner = AlertPresenter.modalRunner
        let opener = AlertPresenter.urlOpener
        defer { AlertPresenter.appActivator = activator; AlertPresenter.modalRunner = runner; AlertPresenter.urlOpener = opener }
        var warnings: [String] = []
        AlertPresenter.appActivator = {}
        AlertPresenter.modalRunner = { alert in warnings.append(alert.messageText); return .alertSecondButtonReturn }
        AlertPresenter.urlOpener = { _ in XCTFail("No settings URL should be opened") }
        let f = try Fixture()
        f.app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await f.sound.flush()
        try await waitUntil { f.welcome.count == 1 }
        f.command(2)
        try await waitUntil { warnings.count == 1 }
        XCTAssertEqual(warnings[0], "No Finder Selection")
        f.finderResult = .failure(NSError(domain: "FinderSelectionService", code: -2,
                                         userInfo: [NSLocalizedDescriptionKey: "Not authorized to send Apple events to Finder. (-1743)"]))
        f.command(2)
        try await waitUntil { warnings.count == 2 }
        XCTAssertFalse(warnings[1].isEmpty)
        let url = f.root.appendingPathComponent("selected.png")
        try TestSupport.writeSolidImagePNG(to: url)
        f.finderResult = .success(.single(url: url))
        f.command(2)
        try await waitUntil { f.workflows.count == 1 }
        XCTAssertTrue(f.screenshot.isBusyForUserCommands)
        f.workflows[0].handleRenameAction(.close)
        XCTAssertFalse(f.screenshot.isBusyForUserCommands)
        XCTAssertNotNil(NSImage(contentsOf: url))
    }
}

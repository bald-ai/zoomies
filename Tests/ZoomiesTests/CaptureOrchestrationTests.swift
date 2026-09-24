import AppKit
import XCTest
@testable import Zoomies

final class CaptureOrchestrationTests: XCTestCase {
    func testNativeCaptureConfigurationAndCompletionDecisionsUseSyntheticInputs() throws {
        let screen = ScreenshotService.ScreenSnapshot(displayID: 9, frame: CGRect(x: -300, y: 50, width: 300, height: 200), scale: 2)
        let config = try ScreenshotService.captureConfiguration(rect: screen.frame, screen: screen)
        XCTAssertEqual(config.width, 600)
        XCTAssertEqual(config.height, 400)
        XCTAssertEqual(config.sourceRect, CGRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertTrue(config.showsCursor)
        XCTAssertFalse(config.scalesToFit)
        XCTAssertThrowsError(try ScreenshotService.captureConfiguration(rect: CGRect(x: 1000, y: 1000, width: 20, height: 20), screen: screen)) {
            XCTAssertEqual(($0 as NSError).code, -4)
        }
        let image = try XCTUnwrap(TestSupport.solidImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertTrue(try ScreenshotService.captureResult(image: image, error: nil) === image)
        let failure = NSError(domain: "capture fixture", code: 17)
        XCTAssertThrowsError(try ScreenshotService.captureResult(image: image, error: failure)) {
            XCTAssertEqual($0 as NSError, failure)
        }
        XCTAssertThrowsError(try ScreenshotService.captureResult(image: nil, error: nil)) {
            XCTAssertEqual(($0 as NSError).code, -5)
            XCTAssertEqual($0.localizedDescription, "No image captured.")
        }
    }

    private final class Sound: ScreenshotSoundPlaying {
        var plays = 0
        func playCaptureSound() { plays += 1 }
    }
    private final class Fixture {
        let root: URL
        let sound = Sound()
        let store: SettingsStore
        var service: ScreenshotService!
        var workflow: ScreenshotWorkflowController?
        var errors: [String] = []
        var errorMessages: [String] = []
        var screenResolutionFailure: Error?
        var areaCalls = 0
        var regionCalls = 0
        var capturedRect: CGRect?
        var result: CGImage?
        var failure: Error?
        var screen: ScreenshotService.ScreenSnapshot? = .init(displayID: 0, frame: CGRect(x: -300, y: 50, width: 300, height: 200), scale: 2)
        init() throws {
            root = try TestSupport.makeTemporaryDirectory()
            store = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
            let image = TestSupport.solidImage(width: 40, height: 20)
            result = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            service = ScreenshotService(settingsStore: store,
                backupService: BackupService(backupsDirectory: root.appendingPathComponent("backups")),
                clipboardService: ClipboardService(cacheDirectory: root.appendingPathComponent("cache"), pasteboardWriter: { _ in true }),
                desktopDirectory: root.appendingPathComponent("saved"), soundPlayer: sound,
                areaCapture: { [unowned self] in
                    areaCalls += 1
                    if let failure { throw failure }
                    return result
                }, captureScreen: { [unowned self] _ in
                    if let screenResolutionFailure { throw screenResolutionFailure }
                    return screen
                },
                regionCapture: { [unowned self] rect, _ in
                    regionCalls += 1
                    capturedRect = rect
                    if let failure { throw failure }
                    return try XCTUnwrap(result)
                }, workflowPresenter: { [unowned self] in workflow = $0 },
                errorPresenter: { [unowned self] title, message in errors.append(title); errorMessages.append(message) })
        }
        deinit { TestSupport.removeIfExists(root) }
    }
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Capture did not reach expected state")
    }

    @MainActor
    func testBackgroundCaptureRequestsReturnToMainQueueAndPersist() async throws {
        for fullScreen in [false, true] {
            let f = try Fixture()
            let service = try XCTUnwrap(f.service)
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    if fullScreen { service.captureFullScreen() } else { service.captureArea() }
                    continuation.resume()
                }
            }
            try await waitUntil { f.workflow != nil }
            XCTAssertEqual(f.areaCalls, fullScreen ? 0 : 1)
            XCTAssertEqual(f.regionCalls, fullScreen ? 1 : 0)
            XCTAssertEqual(f.sound.plays, 1)
            f.workflow?.handleRenameAction(.save(newName: "background"))
            try await waitUntil { !service.isBusyForUserCommands }
            XCTAssertNotNil(NSImage(contentsOf: f.root.appendingPathComponent("saved/background.png")))
            XCTAssertTrue(f.errors.isEmpty)
        }
    }

    @MainActor
    func testBackgroundReopenPreservesFileAndCoalescesWhileWorkflowIsOpen() async throws {
        let f = try Fixture()
        let service = try XCTUnwrap(f.service)
        let url = f.root.appendingPathComponent("existing.png")
        let bytes = try TestSupport.noiseImagePNGData(width: 16, height: 12)
        try bytes.write(to: url)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                service.beginPostCaptureFlow(forExistingFileAt: url, escapeKeyDeletesFile: false)
                continuation.resume()
            }
        }
        try await waitUntil { f.workflow != nil }
        let originalWorkflow = try XCTUnwrap(f.workflow)
        service.beginPostCaptureFlow(forExistingFileAt: url)
        XCTAssertTrue(f.workflow === originalWorkflow)
        XCTAssertEqual(f.sound.plays, 0)
        originalWorkflow.handleRenameAction(.save(newName: "existing"))
        try await waitUntil { !service.isBusyForUserCommands }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(f.errors.isEmpty)
    }

    @MainActor
    func testAreaCaptureGatesRepeatedCommandsPersistsAndHandsOffToWorkflow() async throws {
        let f = try Fixture()
        let counter = f.store.settings.screenshotCounter
        f.service.captureArea()
        f.service.captureArea()
        f.service.captureFullScreen()
        XCTAssertTrue(f.service.isBusyForUserCommands)
        try await waitUntil { f.workflow != nil }
        XCTAssertEqual(f.areaCalls, 1)
        XCTAssertEqual(f.regionCalls, 0)
        XCTAssertEqual(f.sound.plays, 1)
        XCTAssertFalse(f.service.canStartAreaCapture())
        f.workflow?.handleRenameAction(.save(newName: "fixture"))
        try await waitUntil { !f.service.isBusyForUserCommands }
        let saved = f.root.appendingPathComponent("saved/fixture.png")
        let decoded = try XCTUnwrap(NSImage(contentsOf: saved))
        XCTAssertEqual(decoded.size.width, 80)
        XCTAssertEqual(decoded.size.height, 40)
        XCTAssertEqual(f.store.settings.screenshotCounter, counter + 1)
        XCTAssertTrue(f.errors.isEmpty)
        XCTAssertTrue(f.service.canStartFullScreenCapture())
    }

    @MainActor
    func testAreaCancellationAndMissingDisplayDoNotSavePlayOrStartWorkflow() async throws {
        for missingDisplay in [false, true] {
            let f = try Fixture()
            if missingDisplay { f.screen = nil } else { f.result = nil }
            f.service.captureArea()
            try await waitUntil { f.areaCalls == 1 && !f.service.isBusyForUserCommands }
            XCTAssertNil(f.workflow)
            XCTAssertEqual(f.sound.plays, 0)
            XCTAssertTrue(f.errors.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("saved").path))
        }
    }

    @MainActor
    func testCaptureFailuresReleaseGateAndDoNotPersist() async throws {
        for fullScreen in [false, true] {
            let f = try Fixture()
            f.failure = NSError(domain: "fixture capture", code: 1)
            if fullScreen { f.service.captureFullScreen() } else { f.service.captureArea() }
            try await waitUntil { !f.errors.isEmpty }
            XCTAssertFalse(f.service.isBusyForUserCommands)
            XCTAssertNil(f.workflow)
            XCTAssertEqual(f.sound.plays, 0)
            XCTAssertEqual(f.errors, ["Screenshot failed"])
        }
    }

    @MainActor
    func testFullscreenUsesSelectedDisplayFrameAndNoScreenIsNoOp() async throws {
        let f = try Fixture()
        let expectedRect = f.screen?.frame
        f.service.captureFullScreen()
        try await waitUntil { f.workflow != nil }
        XCTAssertEqual(f.capturedRect, expectedRect)
        XCTAssertEqual(f.regionCalls, 1)
        XCTAssertEqual(f.areaCalls, 0)
        f.workflow?.handleRenameAction(.save(newName: "full"))
        try await waitUntil { !f.service.isBusyForUserCommands }
        XCTAssertNotNil(NSImage(contentsOf: f.root.appendingPathComponent("saved/full.png")))
        f.screen = nil
        f.service.captureFullScreen()
        XCTAssertFalse(f.service.isBusyForUserCommands)
        XCTAssertEqual(f.regionCalls, 1)
    }

    @MainActor
    func testFullscreenMissingDisplayIDReportsErrorWithoutStartingCapture() throws {
        let f = try Fixture()
        f.screenResolutionFailure = ScreenshotService.ScreenResolutionError.missingDisplayID
        f.service.captureFullScreen()
        XCTAssertEqual(f.errors, ["Screenshot failed"])
        XCTAssertEqual(f.errorMessages, ["Unable to determine display ID."])
        XCTAssertEqual(f.regionCalls, 0)
        XCTAssertEqual(f.sound.plays, 0)
        XCTAssertNil(f.workflow)
        XCTAssertFalse(f.service.isBusyForUserCommands)
        XCTAssertTrue(f.service.canStartFullScreenCapture())
    }

    func testDisplayResolutionPreservesMouseAndModeSpecificFallbackOrder() throws {
        let left = ScreenshotService.ScreenCandidate(displayID: 7, frame: CGRect(x: -200, y: 0, width: 200, height: 100), scale: 2)
        let right = ScreenshotService.ScreenCandidate(displayID: 8, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        let outside = CGPoint(x: 900, y: 900)
        for mode in [ScreenshotService.CaptureMode.area, .fullScreen] {
            let selected = try XCTUnwrap(ScreenshotService.resolveCaptureScreen(mode, screens: [right, left], mouse: CGPoint(x: -50, y: 20), mainDisplayID: 8, mainScreen: right))
            XCTAssertEqual(selected.displayID, 7)
            XCTAssertEqual(selected.frame, left.frame)
            XCTAssertEqual(selected.scale, 2)
            XCTAssertEqual(try ScreenshotService.resolveCaptureScreen(mode, screens: [left], mouse: outside, mainDisplayID: 99, mainScreen: nil)?.displayID, 7)
            XCTAssertNil(try ScreenshotService.resolveCaptureScreen(mode, screens: [], mouse: outside, mainDisplayID: 99, mainScreen: nil))
        }
        XCTAssertEqual(try ScreenshotService.resolveCaptureScreen(.fullScreen, screens: [left, right], mouse: outside, mainDisplayID: 8, mainScreen: left)?.displayID, 8)
        XCTAssertEqual(try ScreenshotService.resolveCaptureScreen(.area, screens: [left, right], mouse: outside, mainDisplayID: 8, mainScreen: left)?.displayID, 7)
        XCTAssertEqual(try ScreenshotService.resolveCaptureScreen(.fullScreen, screens: [left], mouse: outside, mainDisplayID: 99, mainScreen: right)?.displayID, 8)
    }

    func testMissingDisplayIDDecisionOnlyThrowsForFullscreen() throws {
        let screen = ScreenshotService.ScreenCandidate(displayID: nil, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        XCTAssertNil(try ScreenshotService.resolveCaptureScreen(.area, screens: [screen], mouse: .zero, mainDisplayID: 1, mainScreen: nil))
        XCTAssertThrowsError(try ScreenshotService.resolveCaptureScreen(.fullScreen, screens: [screen], mouse: .zero, mainDisplayID: 1, mainScreen: nil)) { error in
            XCTAssertEqual(error.localizedDescription, "Unable to determine display ID.")
        }
    }

    @MainActor
    func testDestinationFailureDoesNotAdvanceCounterOrStartWorkflow() async throws {
        let f = try Fixture()
        let counter = f.store.settings.screenshotCounter
        try Data("block directory".utf8).write(to: f.root.appendingPathComponent("saved"))
        f.service.captureArea()
        try await waitUntil { !f.errors.isEmpty }
        XCTAssertFalse(f.service.isBusyForUserCommands)
        XCTAssertNil(f.workflow)
        XCTAssertEqual(f.sound.plays, 0)
        XCTAssertEqual(f.store.settings.screenshotCounter, counter)
    }
}

import XCTest
import AppKit
import ScreenCaptureKit
@testable import Zoomies

@available(macOS 15, *)
@MainActor
private final class ControlledRecordingStream: RecordingCaptureStream {
    var startInvoked = false
    var startError: Error?
    var stopError: Error?
    var stopCount = 0
    var onStop: (() -> Void)?
    var startContinuation: CheckedContinuation<Void, Never>?
    var stopContinuation: CheckedContinuation<Void, Never>?

    func startCapture() async throws {
        startInvoked = true
        if let startError { throw startError }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func stopCapture() async throws {
        stopCount += 1
        onStop?()
        if let stopError { throw stopError }
        await withCheckedContinuation { stopContinuation = $0 }
    }

    func updateContentFilter(_ filter: SCContentFilter) async throws {}

    func completeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func completeStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

@available(macOS 15, *)
@MainActor
private final class RecordingFixture {
    let root: URL
    let stream = ControlledRecordingStream()
    var session: ScreenRecordingSession?
    var service: ScreenRecordingService!
    var saved: [URL] = []
    var errors: [String] = []
    var now: TimeInterval = 100
    var liveDisplays: Set<CGDirectDisplayID> = [1, 2]
    var pointedDisplay: CGDirectDisplayID? = 1
    var displayUpdates: [CGDirectDisplayID] = []
    var updateError: Error?
    var updateFound = true
    var updateContinuation: CheckedContinuation<Void, Never>?
    var delayUpdate = false

    init() throws {
        root = try TestSupport.makeTemporaryDirectory()
        service = ScreenRecordingService(recordingDirectory: root.appendingPathComponent("saved"),
            errorPresenter: { [unowned self] title, _ in errors.append(title) }, finalizationDelay: 0.05,
            uptime: { [unowned self] in now }, displays: { [unowned self] in (liveDisplays, pointedDisplay) },
            displayUpdater: { [unowned self] _, display in
                displayUpdates.append(display)
                if delayUpdate { await withCheckedContinuation { updateContinuation = $0 } }
                if let updateError { throw updateError }
                return updateFound
            }) { [unowned self] id, rate in
            let file = root.appendingPathComponent("pending.mp4")
            try Data("finalized recording fixture".utf8).write(to: file)
            let session = ScreenRecordingSession(id: id, stream: stream,
                                                 displayID: 1, tempURL: file,
                                                 frameRate: rate, startUptime: now)
            // These tests exercise lifecycle events, not physical monitor switching.
            session.filterUpdateInProgress = true
            self.session = session
            return session
        }
        service.onRecordingSaved = { [unowned self] in saved.append($0) }
    }

    func cleanup() {
        stream.completeStart()
        stream.completeStop()
        TestSupport.removeIfExists(root)
    }
}

final class ScreenRecordingServiceTests: XCTestCase {
    @MainActor
    func testMonitorDwellCancelsCandidatesRetriesFailureAndIgnoresLateUpdates() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let f = try RecordingFixture()
        defer { f.cleanup() }
        f.service.start()
        try await waitUntil { f.stream.startInvoked }
        let session = try XCTUnwrap(f.session)
        f.service.handleRecordingDidStart(sessionID: session.id)
        f.stream.completeStart()
        session.filterUpdateInProgress = false
        f.pointedDisplay = 2
        f.service.tick()
        XCTAssertEqual(session.candidateDisplayID, 2)
        f.now += 0.4
        f.service.tick()
        // The switch task must not even be scheduled before the dwell expires.
        // Checking the asynchronous update callback alone can race that task.
        XCTAssertFalse(session.filterUpdateInProgress)
        XCTAssertEqual(session.candidateDisplayID, 2)
        XCTAssertEqual(session.displayID, 1)
        XCTAssertTrue(f.displayUpdates.isEmpty)
        f.pointedDisplay = nil
        f.service.tick()
        XCTAssertNil(session.candidateDisplayID)
        f.pointedDisplay = 2
        f.service.tick()
        f.pointedDisplay = 1
        f.service.tick()
        XCTAssertNil(session.candidateDisplayID)
        f.pointedDisplay = 2
        f.updateError = NSError(domain: "switch fixture", code: 1)
        f.service.tick()
        f.now += 0.6
        f.service.tick()
        try await waitUntil { f.displayUpdates.count == 1 && !session.filterUpdateInProgress }
        XCTAssertEqual(session.displayID, 1)
        XCTAssertEqual(f.service.state, .recording)
        f.updateError = nil
        f.updateFound = false
        f.service.tick()
        f.now += 0.6
        f.service.tick()
        try await waitUntil { f.displayUpdates.count == 2 && !session.filterUpdateInProgress }
        XCTAssertEqual(session.displayID, 1)
        f.updateFound = true
        f.service.tick()
        f.now += 0.6
        f.service.tick()
        try await waitUntil { session.displayID == 2 }
        XCTAssertEqual(f.displayUpdates, [2, 2, 2])
        XCTAssertNil(session.candidateDisplayID)
        f.pointedDisplay = 1
        f.delayUpdate = true
        f.service.tick()
        f.now += 0.6
        f.service.tick()
        try await waitUntil { f.updateContinuation != nil }
        f.service.handleRecordingDidFail(sessionID: session.id, error: NSError(domain: "end fixture", code: 2))
        XCTAssertEqual(f.service.state, .idle)
        f.updateContinuation?.resume()
        f.updateContinuation = nil
        await Task.yield()
        XCTAssertEqual(session.displayID, 2)
        XCTAssertTrue(f.saved.isEmpty)
    }

    @MainActor
    func testAutomaticStopAtDurationLimitAndDisplayDisconnectPublishOnlyFinalizedOutput() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        for disconnect in [false, true] {
            let f = try RecordingFixture()
            defer { f.cleanup() }
            f.service.tick()
            f.service.start()
            try await waitUntil { f.stream.startInvoked }
            let session = try XCTUnwrap(f.session)
            f.service.handleRecordingDidStart(sessionID: session.id)
            f.stream.completeStart()
            session.filterUpdateInProgress = false
            if disconnect { f.liveDisplays = [] } else { f.now += ScreenRecordingService.maxDuration }
            f.service.tick()
            XCTAssertEqual(f.service.state, .stopping)
            try await waitUntil { f.stream.stopContinuation != nil }
            f.service.handleRecordingDidFinish(sessionID: session.id)
            f.stream.completeStop()
            try await waitUntil { f.service.state == .idle }
            XCTAssertEqual(f.saved.count, 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(f.saved.first)), Data("finalized recording fixture".utf8))
            XCTAssertTrue(f.errors.isEmpty)
        }
    }

    @MainActor
    func testStreamConfigurationKeepsFixedCanvasSilentAudioAndSanitizedRate() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        for (requested, expected): (Int, Int32) in [(30, 30), (60, 60), (120, 120), (0, 30), (240, 30)] {
            let config = ScreenRecordingService.makeStreamConfiguration(frameRate: requested)
            XCTAssertEqual(config.width, 1920)
            XCTAssertEqual(config.height, 1080)
            XCTAssertEqual(config.minimumFrameInterval.value, 1)
            XCTAssertEqual(config.minimumFrameInterval.timescale, expected)
            XCTAssertFalse(config.capturesAudio)
            XCTAssertTrue(config.showsCursor)
            XCTAssertTrue(config.scalesToFit)
            XCTAssertTrue(config.preservesAspectRatio)
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Recording lifecycle did not reach the expected state")
    }

    @MainActor
    func testFactoryFailureReturnsIdleAndAllowsNextAttempt() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        var attempts = 0
        var errors: [String] = []
        let service = ScreenRecordingService(recordingDirectory: root,
            errorPresenter: { title, _ in errors.append(title) }) { _, _ in
                attempts += 1
                throw NSError(domain: "factory", code: 1)
            }
        service.start()
        try await waitUntil { attempts == 1 && service.state == .idle }
        XCTAssertFalse(service.isBusyForUserCommands)
        XCTAssertFalse(service.isStopAvailable)
        service.stop()
        service.start()
        try await waitUntil { attempts == 2 && service.state == .idle }
        XCTAssertEqual(errors, ["Recording failed", "Recording failed"])
    }

    @MainActor
    func testStreamStartupFailureRemovesTemporaryFileAndResetsState() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let f = try RecordingFixture()
        defer { f.cleanup() }
        f.stream.startError = NSError(domain: "start", code: 1)
        f.service.start()
        try await waitUntil { f.stream.startInvoked && f.service.state == .idle }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(f.session).tempURL.path))
        XCTAssertEqual(f.errors, ["Recording failed"])
        XCTAssertTrue(f.saved.isEmpty)
        XCTAssertEqual(f.service.elapsed, 0)
    }

    @MainActor
    func testTimeoutNeverPublishesNonemptyUnfinalizedRecording() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let f = try RecordingFixture()
        defer { f.cleanup() }
        f.service.start()
        try await waitUntil { f.stream.startInvoked }
        let session = try XCTUnwrap(f.session)
        f.service.handleRecordingDidStart(sessionID: session.id)
        f.stream.completeStart()
        f.service.stop()
        try await waitUntil { f.stream.stopContinuation != nil }
        f.stream.completeStop()
        try await waitUntil { f.service.state == .idle }
        XCTAssertTrue(f.saved.isEmpty)
        XCTAssertEqual(f.errors, ["Recording failed"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.tempURL.path))
        f.service.handleRecordingDidFinish(sessionID: session.id)
        f.service.handleRecordingDidFail(sessionID: session.id, error: NSError(domain: "late", code: 1))
        XCTAssertTrue(f.saved.isEmpty)
        XCTAssertEqual(f.errors.count, 1)
    }

    @MainActor
    func testDelegateFailureAndStaleCallbacksCannotPublishOrRestart() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let f = try RecordingFixture()
        defer { f.cleanup() }
        f.service.start(frameRate: 120)
        f.service.start(frameRate: 60)
        try await waitUntil { f.stream.startInvoked }
        let session = try XCTUnwrap(f.session)
        XCTAssertEqual(session.frameRate, 120)
        f.service.handleRecordingDidStart(sessionID: UUID())
        f.service.handleRecordingDidFinish(sessionID: UUID())
        f.service.handleRecordingDidFail(sessionID: UUID(), error: NSError(domain: "stale", code: 1))
        XCTAssertEqual(f.service.state, .starting)
        f.service.handleRecordingDidStart(sessionID: session.id)
        f.service.handleRecordingDidStart(sessionID: session.id)
        XCTAssertEqual(f.service.state, .recording)
        f.service.handleRecordingDidFail(sessionID: session.id, error: NSError(domain: "writer", code: 1))
        f.stream.completeStart()
        XCTAssertEqual(f.service.state, .idle)
        XCTAssertEqual(f.errors, ["Recording failed"])
        XCTAssertTrue(f.saved.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.tempURL.path))
    }

    @MainActor
    func testTerminationSavesWithoutOpeningWorkflowAndCompletesOnce() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let f = try RecordingFixture()
        defer { f.cleanup() }
        var completions = 0
        f.service.stopForAppTermination { completions += 1 }
        XCTAssertEqual(completions, 1)
        f.service.start(frameRate: 17)
        try await waitUntil { f.stream.startInvoked }
        let session = try XCTUnwrap(f.session)
        XCTAssertEqual(session.frameRate, 30)
        f.service.handleRecordingDidStart(sessionID: session.id)
        f.stream.completeStart()
        f.stream.onStop = { f.service.handleRecordingDidFinish(sessionID: session.id) }
        f.service.stopForAppTermination { completions += 1 }
        try await waitUntil { f.stream.stopContinuation != nil }
        f.stream.completeStop()
        try await waitUntil { f.service.state == .idle }
        XCTAssertEqual(completions, 2)
        XCTAssertTrue(f.saved.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: f.root.appendingPathComponent("saved"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), Data("finalized recording fixture".utf8))
        XCTAssertTrue(f.errors.isEmpty)
    }

    @MainActor
    func testFinalizedMissingEmptyAndUnwritableOutputsAreNotReportedAsSaved() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        for scenario in ["missing", "empty", "unwritable"] {
            let f = try RecordingFixture()
            defer { f.cleanup() }
            f.service.start()
            try await waitUntil { f.stream.startInvoked }
            let session = try XCTUnwrap(f.session)
            if scenario == "missing" { try FileManager.default.removeItem(at: session.tempURL) }
            if scenario == "empty" { try Data().write(to: session.tempURL) }
            if scenario == "unwritable" { try Data("block directory".utf8).write(to: f.root.appendingPathComponent("saved")) }
            f.service.handleRecordingDidFinish(sessionID: session.id)
            try await waitUntil { f.stream.stopContinuation != nil }
            f.stream.completeStart()
            f.stream.completeStop()
            try await waitUntil { f.service.state == .idle }
            XCTAssertTrue(f.saved.isEmpty, scenario)
            XCTAssertEqual(f.errors, scenario == "unwritable" ? ["Couldn’t save recording"] : [])
            if scenario == "unwritable" {
                XCTAssertEqual(try Data(contentsOf: session.tempURL), Data("finalized recording fixture".utf8),
                               "A failed destination must leave the finalized recording available for recovery")
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: session.tempURL.path))
            }
        }
    }

    @MainActor
    func testUnexpectedStreamStopStillPublishesDelegateFinalizedFileEvenIfStopThrows() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let f = try RecordingFixture()
        defer { f.cleanup() }
        let error = NSError(domain: "stream", code: 1)
        f.service.start()
        try await waitUntil { f.stream.startInvoked }
        let session = try XCTUnwrap(f.session)
        f.service.handleRecordingDidStart(sessionID: session.id)
        f.stream.completeStart()
        f.service.handleStreamDidStop(sessionID: UUID(), error: error)
        XCTAssertEqual(f.service.state, .recording)
        f.stream.stopError = error
        f.stream.onStop = { f.service.handleRecordingDidFinish(sessionID: session.id) }
        f.service.handleStreamDidStop(sessionID: session.id, error: error)
        try await waitUntil { f.service.state == .idle }
        XCTAssertEqual(f.saved.count, 1)
        XCTAssertEqual(f.stream.stopCount, 1)
        XCTAssertTrue(f.errors.isEmpty)
    }

    @MainActor
    private func trackMenuBriefly() {
        // AppKit adds this common mode in a running app; XCTest doesn't run NSApplication.run().
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString))
        let until = Date().addingTimeInterval(0.25)
        while Date() < until {
            RunLoop.main.run(mode: .eventTracking, before: until)
        }
    }

    @MainActor
    func testWriterStartShowsTimerBeforeStreamStartCompletionAndDuringMenuTracking() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let fixture = try RecordingFixture()
        defer { fixture.cleanup() }
        fixture.service.start()
        try await waitUntil { fixture.stream.startInvoked }
        let session = try XCTUnwrap(fixture.session)
        fixture.service.handleRecordingDidStart(sessionID: session.id)
        XCTAssertEqual(fixture.service.state, .recording)
        session.startUptime -= 2
        trackMenuBriefly()
        XCTAssertGreaterThanOrEqual(fixture.service.elapsed, 2)

        fixture.service.handleRecordingDidFinish(sessionID: session.id)
        try await waitUntil { fixture.stream.stopContinuation != nil }
        fixture.stream.completeStart()
        fixture.stream.completeStop()
        try await waitUntil { fixture.service.state == .idle }
    }

    @MainActor
    func testSystemStopFinishesOnceAndLateStartupCannotRestartTimer() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let fixture = try RecordingFixture()
        defer { fixture.cleanup() }
        fixture.service.start()
        try await waitUntil { fixture.stream.startInvoked }
        let id = try XCTUnwrap(fixture.session).id
        fixture.service.handleRecordingDidStart(sessionID: id)
        fixture.service.handleRecordingDidFinish(sessionID: id)
        XCTAssertEqual(fixture.service.state, .stopping)
        try await waitUntil { fixture.stream.stopContinuation != nil }
        fixture.stream.completeStart()
        fixture.service.handleRecordingDidFinish(sessionID: id)
        fixture.stream.completeStop()
        try await waitUntil { fixture.service.state == .idle }
        fixture.service.handleRecordingDidStart(sessionID: id)
        XCTAssertEqual(fixture.service.state, .idle)
        XCTAssertEqual(fixture.service.elapsed, 0)
        XCTAssertEqual(fixture.stream.stopCount, 1)
        XCTAssertEqual(fixture.saved.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(fixture.saved.first).path))
    }

    @MainActor
    func testManualStopAndWriterFinishUseTheSameSingleSavePath() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let fixture = try RecordingFixture()
        defer { fixture.cleanup() }
        fixture.service.start()
        try await waitUntil { fixture.stream.startInvoked }
        let id = try XCTUnwrap(fixture.session).id
        fixture.service.handleRecordingDidStart(sessionID: id)
        fixture.stream.completeStart()
        fixture.stream.onStop = { fixture.service.handleRecordingDidFinish(sessionID: id) }
        fixture.service.stop()
        fixture.service.stop()
        try await waitUntil { fixture.stream.stopContinuation != nil }
        fixture.stream.completeStop()
        try await waitUntil { fixture.service.state == .idle }
        XCTAssertEqual(fixture.stream.stopCount, 1)
        XCTAssertEqual(fixture.saved.count, 1)
    }

    @MainActor
    func testStopDuringStartupCannotBeOverriddenByWriterStart() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Requires recording support") }
        let fixture = try RecordingFixture()
        defer { fixture.cleanup() }
        fixture.service.start()
        try await waitUntil { fixture.stream.startInvoked }
        let id = try XCTUnwrap(fixture.session).id
        fixture.service.stop()
        fixture.service.handleRecordingDidStart(sessionID: id)
        XCTAssertEqual(fixture.service.state, .stopping)
        fixture.stream.onStop = { fixture.service.handleRecordingDidFinish(sessionID: id) }
        fixture.stream.completeStart()
        try await waitUntil { fixture.stream.stopContinuation != nil }
        fixture.stream.completeStop()
        try await waitUntil { fixture.service.state == .idle }
        XCTAssertEqual(fixture.service.elapsed, 0)
        XCTAssertEqual(fixture.stream.stopCount, 1)
        XCTAssertEqual(fixture.saved.count, 1)
    }
}

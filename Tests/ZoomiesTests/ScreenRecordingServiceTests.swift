import XCTest
import AppKit
import ScreenCaptureKit
@testable import Zoomies

@available(macOS 15, *)
@MainActor
private final class ControlledRecordingStream: RecordingCaptureStream {
    var startInvoked = false
    var stopCount = 0
    var onStop: (() -> Void)?
    var startContinuation: CheckedContinuation<Void, Never>?
    var stopContinuation: CheckedContinuation<Void, Never>?

    func startCapture() async throws {
        startInvoked = true
        await withCheckedContinuation { startContinuation = $0 }
    }

    func stopCapture() async throws {
        stopCount += 1
        onStop?()
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

    init() throws {
        root = try TestSupport.makeTemporaryDirectory()
        service = ScreenRecordingService(recordingDirectory: root.appendingPathComponent("saved")) { [unowned self] id, rate in
            let file = root.appendingPathComponent("pending.mp4")
            try Data("finalized recording fixture".utf8).write(to: file)
            let session = ScreenRecordingSession(id: id, stream: stream,
                                                 displayID: CGMainDisplayID(), tempURL: file,
                                                 frameRate: rate, startUptime: ProcessInfo.processInfo.systemUptime)
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
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Recording lifecycle did not reach the expected state")
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

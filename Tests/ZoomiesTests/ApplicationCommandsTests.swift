import XCTest
@testable import Zoomies

@MainActor
final class ApplicationCommandsTests: XCTestCase {
    @MainActor
    private final class Fixture {
        var state = ApplicationCommands.State()
        var effects: [String] = []
        var pending: [@MainActor @Sendable () -> Void] = []
        lazy var commands = ApplicationCommands(state: { [unowned self] in state }, actions: .init(
            area: { [unowned self] in effects.append("area") },
            fullScreen: { [unowned self] in effects.append("full") },
            reopenFinder: { [unowned self] in effects.append("finder") },
            scratchpad: { [unowned self] in effects.append("note") },
            startRecording: { [unowned self] in effects.append("start") },
            stopRecording: { [unowned self] in effects.append("stop") }),
            schedule: { [unowned self] in pending.append($0) })
    }
    func testIdleCommandsDispatchExactlyTheirOwnEffect() {
        let f = Fixture()
        f.commands.perform(.area)
        f.commands.perform(.fullScreen)
        f.commands.perform(.reopenFinder)
        f.commands.perform(.toggleRecording)
        f.commands.perform(.scratchpad)
        XCTAssertEqual(f.effects, ["area", "full", "finder", "start"])
        XCTAssertEqual(f.pending.count, 1)
        f.pending.removeFirst()()
        XCTAssertEqual(f.effects, ["area", "full", "finder", "start", "note"])
    }
    func testCaptureAndFinderRespectEveryConflictingWorkflow() {
        for key in [\ApplicationCommands.State.recordingShortcut, \.videoRenameBusy, \.scratchpadBusy, \.recordingBusy] {
            let f = Fixture()
            f.state[keyPath: key] = true
            f.commands.perform(.area)
            f.commands.perform(.fullScreen)
            f.commands.perform(.reopenFinder)
            XCTAssertTrue(f.effects.isEmpty)
        }
        let f = Fixture()
        f.state.screenshotBusy = true
        f.commands.perform(.reopenFinder)
        XCTAssertTrue(f.effects.isEmpty)
        // ScreenshotService owns its own in-flight gate. Do not add a new
        // Finder gate to capture dispatch while a lookup is still running.
        f.state = .init(finderLookupBusy: true)
        f.commands.perform(.area)
        f.commands.perform(.fullScreen)
        XCTAssertEqual(f.effects, ["area", "full"])
    }
    func testRecordingStartGatesAndStopPrecedence() {
        for key in [\ApplicationCommands.State.recordingShortcut, \.videoRenameBusy, \.scratchpadBusy, \.screenshotBusy, \.finderLookupBusy] {
            let f = Fixture()
            f.state[keyPath: key] = true
            f.commands.perform(.toggleRecording)
            XCTAssertTrue(f.effects.isEmpty)
        }
        let f = Fixture()
        f.state = .init(videoRenameBusy: true, scratchpadBusy: true, screenshotBusy: true,
                        finderLookupBusy: true, recordingBusy: true, stopAvailable: true)
        f.commands.perform(.toggleRecording)
        XCTAssertEqual(f.effects, ["stop"])
        f.state.recordingShortcut = true
        f.commands.perform(.toggleRecording)
        XCTAssertEqual(f.effects, ["stop"])
    }
    func testPendingNoteBlocksCompetingCommandsAndCoalescesDuplicates() {
        let f = Fixture()
        f.commands.perform(.scratchpad)
        f.commands.perform(.scratchpad)
        f.commands.perform(.area)
        f.commands.perform(.fullScreen)
        f.commands.perform(.reopenFinder)
        f.commands.perform(.toggleRecording)
        XCTAssertEqual(f.pending.count, 1)
        XCTAssertTrue(f.effects.isEmpty)
        f.pending.removeFirst()()
        f.commands.perform(.area)
        XCTAssertEqual(f.effects, ["note", "area"])
    }
    func testDeferredNoteRechecksStateAndAlwaysReleasesPendingGate() {
        for key in [\ApplicationCommands.State.recordingShortcut, \.videoRenameBusy, \.recordingBusy, \.screenshotBusy] {
            let f = Fixture()
            f.commands.perform(.scratchpad)
            f.state[keyPath: key] = true
            f.pending.removeFirst()()
            XCTAssertTrue(f.effects.isEmpty)
            f.state = .init()
            f.commands.perform(.scratchpad)
            XCTAssertEqual(f.pending.count, 1)
            f.pending.removeFirst()()
            XCTAssertEqual(f.effects, ["note"])
        }
    }
    func testExistingNoteMayBeReopenedAndStopRemainsAvailableWhileNoteQueued() {
        let f = Fixture()
        f.state.scratchpadBusy = true
        f.commands.perform(.scratchpad)
        f.pending.removeFirst()()
        XCTAssertEqual(f.effects, ["note"])
        f.commands.perform(.scratchpad)
        f.state.stopAvailable = true
        f.commands.perform(.toggleRecording)
        XCTAssertEqual(f.effects, ["note", "stop"])
    }
}

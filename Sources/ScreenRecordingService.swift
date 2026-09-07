import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// Prototype display recording backed by SCStream + SCRecordingOutput.
///
/// Fixed behavior: 30/60 fps (Settings), SDR, H.264 MP4, no audio,
/// 1920x1080 canvas that fits the whole display (black margins where
/// needed), cursor included, Zoomies' own windows excluded, 60-second cap,
/// monitor following.
/// Requires macOS 15 at runtime; screenshots/notes keep working on macOS 14.
@MainActor
final class ScreenRecordingService: NSObject {
    enum State: Equatable {
        case idle
        case starting
        case recording
        case stopping
    }

    static let maxDuration: TimeInterval = 60
    static let outputWidth = 1920
    static let outputHeight = 1080
    static let monitorPollInterval: TimeInterval = 0.1
    static let monitorDwellTime: TimeInterval = 0.5
    static let finalizeTimeout: TimeInterval = 8

    /// Retained: SCStreamConfiguration.backgroundColor is unowned(unsafe).
    private static let letterboxColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    static var isSupported: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0

    /// Called on the main thread on every state/elapsed change.
    var onUpdate: (() -> Void)?

    /// Called on the main thread with the saved video URL after a recording
    /// finalizes successfully and the file has been moved to its destination.
    /// Not called for failures, timeouts without delegate finalization, or
    /// when stopping because the app is quitting.
    var onRecordingSaved: ((URL) -> Void)?

    /// Any non-idle state blocks screenshots/notes/Finder-reopen.
    var isBusyForUserCommands: Bool { state != .idle }

    /// Stop stays usable through starting/recording/stopping.
    var isStopAvailable: Bool { state != .idle }

    private var sessionID: UUID?
    private var pendingStop = false
    private var sessionBox: AnyObject?
    private var pollTimer: Timer?
    private var terminationCompletion: (() -> Void)?
    /// Set while handling app-quit shutdown so the saved file keeps its
    /// generated name and no rename panel is shown.
    private var isTerminating = false

    @available(macOS 15, *)
    private var session: ScreenRecordingSession? {
        get { sessionBox as? ScreenRecordingSession }
        set { sessionBox = newValue }
    }

    // MARK: - Public control

    /// Starts a recording, capturing the frame rate once for the whole
    /// session. Unsupported values fall back to 30. Changing Settings
    /// mid-recording applies to the next recording.
    func start(frameRate: Int = 30) {
        guard state == .idle else { return }
        guard Self.isSupported else {
            AlertPresenter.presentWarning(
                title: "Screen recording unavailable",
                message: "Screen recording requires macOS 15 or later. Screenshots and notes continue to work on this Mac."
            )
            return
        }
        if #available(macOS 15, *) {
            startOn15(frameRate: Self.sanitizedFrameRate(frameRate))
        }
    }

    /// Single entry point for manual stop, automatic stop, and shutdown.
    /// Safe to call more than once.
    func stop() {
        switch state {
        case .idle, .stopping:
            return
        case .starting:
            // Startup owns the stream; remember the request and let it
            // finish/cancel safely through the same finalize path.
            pendingStop = true
            state = .stopping
            notify()
        case .recording:
            state = .stopping
            stopPollTimer()
            notify()
            if #available(macOS 15, *) {
                let id = sessionID
                Task { await self.runFinish(sessionID: id) }
            }
        }
    }

    /// Stops and invokes completion once the service is back to idle,
    /// or after a bounded fallback so termination never waits forever.
    func stopForAppTermination(completion: @escaping () -> Void) {
        guard isBusyForUserCommands else {
            completion()
            return
        }
        terminationCompletion = completion
        isTerminating = true
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finalizeTimeout + 2) { [weak self] in
            Task { @MainActor [weak self] in
                self?.drainTerminationCompletion()
            }
        }
    }

    // MARK: - Startup (macOS 15)

    @available(macOS 15, *)
    private func startOn15(frameRate: Int) {
        state = .starting
        elapsed = 0
        pendingStop = false
        notify()
        let id = UUID()
        sessionID = id
        Task { await self.runStartup(sessionID: id, frameRate: frameRate) }
    }

    @available(macOS 15, *)
    private func runStartup(sessionID id: UUID, frameRate: Int) async {
        do {
            let screen = Self.screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first
            guard let screen, let displayID = screen.recordingDisplayID else {
                throw NSError(domain: "ScreenRecordingService", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Unable to determine which display to record."])
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw NSError(domain: "ScreenRecordingService", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "No display found for recording."])
            }
            let filter = SCContentFilter(display: display,
                                         excludingApplications: Self.excludedApplications(in: content),
                                         exceptingWindows: [])
            let configuration = Self.makeStreamConfiguration(frameRate: frameRate)
            let tempURL = Self.makeTemporaryURL()
            try? FileManager.default.removeItem(at: tempURL)

            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = tempURL
            recordingConfiguration.videoCodecType = .h264
            recordingConfiguration.outputFileType = .mp4

            let forwarder = ScreenRecordingForwarder(service: self, sessionID: id)
            let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: forwarder)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: forwarder)
            try stream.addRecordingOutput(recordingOutput)

            let session = ScreenRecordingSession(id: id,
                                                 stream: stream,
                                                 recordingOutput: recordingOutput,
                                                 forwarder: forwarder,
                                                 displayID: displayID,
                                                 tempURL: tempURL,
                                                 frameRate: frameRate,
                                                 startUptime: ProcessInfo.processInfo.systemUptime)
            self.session = session

            if self.isStale(sessionID: id) || self.pendingStop {
                await self.finalizeSession(sessionID: id, publish: true)
                return
            }

            try await stream.startCapture()

            if self.isStale(sessionID: id) || self.pendingStop {
                await self.finalizeSession(sessionID: id, publish: true)
                return
            }

            self.state = .recording
            self.startPollTimer()
            self.notify()
        } catch {
            self.fail(sessionID: id, error: error)
        }
    }

    // MARK: - Finish

    @available(macOS 15, *)
    private func runFinish(sessionID id: UUID?) async {
        guard let id, !isStale(sessionID: id) else { return }
        await finalizeSession(sessionID: id, publish: true)
    }

    /// Stops capture, waits for recording-output finalization (bounded),
    /// then publishes the MP4 and returns to idle. Same path for manual
    /// stop, automatic stop, stop-during-startup, and shutdown.
    @available(macOS 15, *)
    private func finalizeSession(sessionID id: UUID, publish: Bool) async {
        guard let session, session.id == id, !isStale(sessionID: id) else {
            goIdleIfCurrent(sessionID: id)
            return
        }
        do {
            try await session.stream.stopCapture()
        } catch {
            // Continue: the recording-output delegate still reports
            // finalization, or the timeout below bounds the wait.
        }
        await waitForFinalize(session: session)
        var savedURL: URL?
        if publish {
            savedURL = publishSession(session)
        } else {
            try? FileManager.default.removeItem(at: session.tempURL)
        }
        if sessionBox as? ScreenRecordingSession === session {
            sessionBox = nil
        }
        // Report synchronously on the main actor right after going idle, so no
        // other operation can start between saving and showing the panel.
        let shouldReport = savedURL != nil && !isTerminating
        isTerminating = false
        goIdleIfCurrent(sessionID: id)
        if shouldReport, let savedURL {
            onRecordingSaved?(savedURL)
        }
    }

    @available(macOS 15, *)
    private func waitForFinalize(session: ScreenRecordingSession) async {
        if session.finalized {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.finalizeContinuation = continuation
            let id = session.id
            Task {
                try? await Task.sleep(for: .seconds(Self.finalizeTimeout))
                await MainActor.run {
                    self.timeoutFinalize(sessionID: id)
                }
            }
        }
    }

    private func timeoutFinalize(sessionID id: UUID) {
        if #available(macOS 15, *) {
            guard let session, session.id == id, !session.finalized else { return }
            session.finalized = true
            session.finalizeContinuation?.resume()
            session.finalizeContinuation = nil
        }
    }

    /// Moves a finalized recording to the Desktop and returns its final URL.
    /// Returns nil unless the recording-output delegate confirmed successful
    /// finalization: a nonempty temp file or a finalize timeout alone is not
    /// proof of success.
    @available(macOS 15, *)
    @discardableResult
    private func publishSession(_ session: ScreenRecordingSession) -> URL? {
        defer { try? FileManager.default.removeItem(at: session.tempURL) }
        guard session.didFinishRecording else {
            try? FileManager.default.removeItem(at: session.tempURL)
            AlertPresenter.presentWarning(
                title: "Recording failed",
                message: "The recording couldn’t be finalized, so it wasn’t saved."
            )
            return nil
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: session.tempURL.path),
              let size = try? fileManager.attributesOfItem(atPath: session.tempURL.path)[.size] as? NSNumber,
              size.intValue > 0 else {
            return nil
        }
        do {
            let desktop = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
            try fileManager.createDirectory(at: desktop, withIntermediateDirectories: true)
            let baseName = Self.recordingBaseName(date: Date())
            let target = UniqueFileURLLogic.uniqueURL(forProposedName: baseName + ".mp4",
                                                      in: desktop,
                                                      fileExists: { fileManager.fileExists(atPath: $0) })
            try fileManager.moveItem(at: session.tempURL, to: target)
            return target
        } catch {
            AlertPresenter.presentWarning(title: "Couldn’t save recording", message: error.localizedDescription)
            return nil
        }
    }

    private func fail(sessionID id: UUID, error: Error) {
        guard !isStale(sessionID: id) else { return }
        isTerminating = false
        stopPollTimer()
        if #available(macOS 15, *) {
            if let session, session.id == id {
                try? FileManager.default.removeItem(at: session.tempURL)
            }
            if session?.id == id {
                sessionBox = nil
            }
        }
        goIdleIfCurrent(sessionID: id)
        AlertPresenter.presentWarning(title: "Recording failed", message: (error as NSError).localizedDescription)
    }

    private func goIdleIfCurrent(sessionID id: UUID) {
        guard !isStale(sessionID: id) else { return }
        state = .idle
        elapsed = 0
        pendingStop = false
        sessionID = nil
        stopPollTimer()
        notify()
        drainTerminationCompletion()
    }

    private func isStale(sessionID id: UUID) -> Bool {
        sessionID != id
    }

    private func drainTerminationCompletion() {
        let completion = terminationCompletion
        terminationCompletion = nil
        completion?()
    }

    private func notify() {
        onUpdate?()
    }

    // MARK: - Delegate callbacks (forwarded to main actor)

    fileprivate func handleRecordingDidStart(sessionID id: UUID) {
        // Recording-active state and elapsed tracking begin at
        // startCapture success; this confirms the file writer is live.
        guard #available(macOS 15, *),
              let session, session.id == id, !isStale(sessionID: id) else { return }
        session.writerStarted = true
    }

    fileprivate func handleRecordingDidFinish(sessionID id: UUID) {
        guard #available(macOS 15, *),
              let session, session.id == id else { return }
        session.didFinishRecording = true
        session.finalized = true
        session.finalizeContinuation?.resume()
        session.finalizeContinuation = nil
    }

    fileprivate func handleRecordingDidFail(sessionID id: UUID, error: Error) {
        guard #available(macOS 15, *) else { return }
        // A late failure after finalize timed out must not disturb idle.
        guard let session, session.id == id, !isStale(sessionID: id) else { return }
        if session.finalized && state == .idle {
            return
        }
        session.finalized = true
        session.finalizeContinuation?.resume()
        session.finalizeContinuation = nil
        // If we are still waiting in finalize, publish will find no usable
        // file and skip quietly; surface the error only when finalize is
        // not already driving the session home.
        if state == .recording || state == .starting {
            fail(sessionID: id, error: error)
        }
    }

    fileprivate func handleStreamDidStop(sessionID id: UUID, error: Error) {
        // Unexpected mid-recording stream death: stop and save what we have.
        guard state == .recording, !isStale(sessionID: id) else { return }
        stop()
    }

    // MARK: - Monitor following + duration polling

    private func startPollTimer() {
        stopPollTimer()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.monitorPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func stopPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tick() {
        guard state == .recording else { return }
        if #available(macOS 15, *) {
            guard let session, session.id == sessionID else { return }
            let now = ProcessInfo.processInfo.systemUptime
            elapsed = now - session.startUptime
            notify()
            if elapsed >= Self.maxDuration {
                stop()
                return
            }
            pollMonitor(session: session, now: now)
        }
    }

    @available(macOS 15, *)
    private func pollMonitor(session: ScreenRecordingSession, now: TimeInterval) {
        if session.filterUpdateInProgress {
            return
        }
        let liveDisplayIDs = Set(NSScreen.screens.compactMap { $0.recordingDisplayID })
        guard liveDisplayIDs.contains(session.displayID) else {
            // Recorded display disconnected: stop and save this prototype.
            stop()
            return
        }
        guard let pointed = Self.screenUnderMouse()?.recordingDisplayID else {
            session.candidateDisplayID = nil
            return
        }
        guard pointed != session.displayID else {
            session.candidateDisplayID = nil
            return
        }
        if session.candidateDisplayID != pointed {
            session.candidateDisplayID = pointed
            session.candidateSince = now
            return
        }
        guard now - session.candidateSince >= Self.monitorDwellTime else { return }
        session.candidateDisplayID = nil
        switchDisplay(session: session, to: pointed)
    }

    @available(macOS 15, *)
    private func switchDisplay(session: ScreenRecordingSession, to displayID: CGDirectDisplayID) {
        session.filterUpdateInProgress = true
        let id = session.id
        Task {
            defer {
                Task { @MainActor [weak self] in
                    self?.clearFilterUpdateFlag(sessionID: id)
                }
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
            let filter = SCContentFilter(display: display,
                                         excludingApplications: Self.excludedApplications(in: content),
                                         exceptingWindows: [])
            // Same stream, same output file, same fixed canvas: only the
            // content filter changes. Whether SCRecordingOutput keeps writing
            // one seamless file across this update is unverified at runtime.
            try await session.stream.updateContentFilter(filter)
            await MainActor.run {
                guard !self.isStale(sessionID: id),
                      let current = self.session, current.id == id else { return }
                current.displayID = displayID
                current.candidateDisplayID = nil
            }
        }
    }

    // MARK: - Stream configuration

    @available(macOS 15, *)
    private func clearFilterUpdateFlag(sessionID id: UUID) {
        guard let current = session, current.id == id else { return }
        current.filterUpdateInProgress = false
    }

    /// Only 30 and 60 fps are supported; anything else falls back to 30.
    static func sanitizedFrameRate(_ value: Int) -> Int {
        (value == 30 || value == 60) ? value : 30
    }

    @available(macOS 15, *)
    private static func makeStreamConfiguration(frameRate: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        // Fixed 1920x1080 canvas. scalesToFit + preservesAspectRatio fits the
        // entire display without cropping or stretching; the black background
        // fills the margins (letterboxing).
        configuration.width = outputWidth
        configuration.height = outputHeight
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(sanitizedFrameRate(frameRate)))
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.backgroundColor = letterboxColor
        // captureDynamicRange defaults to SDR; HDR recording is unsupported,
        // so leave the default rather than opting into HDR.
        return configuration
    }

    private static func excludedApplications(in content: SCShareableContent) -> [SCRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.applications.filter { $0.processID == ownPID }
    }

    private static func screenUnderMouse() -> NSScreen? {
        // Same AppKit coordinate system for pointer and frames; supports
        // negative coordinates and vertically arranged displays.
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    }

    private static func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomies-recording-\(UUID().uuidString).mp4")
    }

    static func recordingBaseName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Recording_\(formatter.string(from: date))"
    }
}

// MARK: - Session objects (macOS 15)

/// Strongly retained for the whole recording: stream, recording output,
/// and delegate must all stay alive or capture stops.
@available(macOS 15, *)
@MainActor
private final class ScreenRecordingSession {
    let id: UUID
    let stream: SCStream
    let recordingOutput: SCRecordingOutput
    let forwarder: ScreenRecordingForwarder
    var displayID: CGDirectDisplayID
    let tempURL: URL
    /// Frame rate captured once at recording startup.
    let frameRate: Int
    let startUptime: TimeInterval

    var candidateDisplayID: CGDirectDisplayID?
    var candidateSince: TimeInterval = 0
    var filterUpdateInProgress = false
    var writerStarted = false
    var finalized = false
    /// Set only by the recording-output delegate on successful finalization,
    /// never by the finalize timeout.
    var didFinishRecording = false
    var finalizeContinuation: CheckedContinuation<Void, Never>?

    init(id: UUID, stream: SCStream, recordingOutput: SCRecordingOutput,
         forwarder: ScreenRecordingForwarder, displayID: CGDirectDisplayID,
         tempURL: URL, frameRate: Int, startUptime: TimeInterval) {
        self.id = id
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.forwarder = forwarder
        self.displayID = displayID
        self.tempURL = tempURL
        self.frameRate = frameRate
        self.startUptime = startUptime
    }
}

/// SCRecordingOutput takes its delegate in the initializer (no writable
/// delegate property) and calls it off the main thread, so this forwarder
/// holds the session id and hops back to the main actor.
@available(macOS 15, *)
private final class ScreenRecordingForwarder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    weak var service: ScreenRecordingService?
    let sessionID: UUID

    init(service: ScreenRecordingService, sessionID: UUID) {
        self.service = service
        self.sessionID = sessionID
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let id = sessionID
        Task { [weak service] in await service?.handleRecordingDidStart(sessionID: id) }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let id = sessionID
        Task { [weak service] in await service?.handleRecordingDidFinish(sessionID: id) }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let id = sessionID
        Task { [weak service] in await service?.handleRecordingDidFail(sessionID: id, error: error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let id = sessionID
        Task { [weak service] in await service?.handleStreamDidStop(sessionID: id, error: error) }
    }
}

private extension NSScreen {
    var recordingDisplayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}

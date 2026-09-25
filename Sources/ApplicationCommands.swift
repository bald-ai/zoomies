import Foundation

/// Coordinates commands across workflows. Presentation/capture effects are
/// supplied by AppDelegate, while pending requests and precedence live here.
@MainActor
final class ApplicationCommands {
    enum Command { case area, fullScreen, reopenFinder, scratchpad, toggleRecording }
    struct State {
        var recordingShortcut = false
        var videoRenameBusy = false
        var scratchpadBusy = false
        var screenshotBusy = false
        var finderLookupBusy = false
        var recordingBusy = false
        var stopAvailable = false
    }
    struct Actions {
        var area: () -> Void
        var fullScreen: () -> Void
        var reopenFinder: () -> Void
        var scratchpad: () -> Void
        var startRecording: () -> Void
        var stopRecording: () -> Void
    }
    private let state: () -> State
    private let actions: Actions
    private let schedule: (@escaping @MainActor @Sendable () -> Void) -> Void
    private var gate = UserCommandGate()

    init(state: @escaping () -> State, actions: Actions,
         schedule: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.state = state
        self.actions = actions
        self.schedule = schedule
    }

    func perform(_ command: Command) {
        switch command {
        case .area, .fullScreen:
            guard canCapture(state()) else { return }
            if command == .area { actions.area() } else { actions.fullScreen() }
        case .reopenFinder:
            reopenFinder()
        case .scratchpad:
            requestScratchpad()
        case .toggleRecording:
            toggleRecording()
        }
    }

    private func reopenFinder() {
        let current = state()
        guard canCapture(current), !current.screenshotBusy else { return }
        actions.reopenFinder()
    }

    private func canCapture(_ current: State) -> Bool {
        !current.recordingShortcut && !current.videoRenameBusy && !current.recordingBusy
            && gate.canStartScreenshot(scratchpadIsBusy: current.scratchpadBusy)
    }

    /// Single entry point for the recording menu command and shortcut.
    /// A stop request is honored before any busy-state checks so Stop stays
    /// available while recording; startup is rejected while screenshot,
    /// note, Finder-reopen, or video-rename work is active or opening.
    private func toggleRecording() {
        let current = state()
        guard !current.recordingShortcut else { return }
        // Stop must remain available while another workflow or lookup is busy.
        if current.stopAvailable {
            actions.stopRecording()
            return
        }
        guard !current.videoRenameBusy, !current.screenshotBusy, !current.finderLookupBusy,
              gate.canStartScreenshot(scratchpadIsBusy: current.scratchpadBusy) else { return }
        actions.startRecording()
    }

    private func requestScratchpad() {
        guard gate.beginScratchpadOpenRequest() else { return }
        // A menu command must wait until menu tracking ends. Re-read state
        // when the request runs, and release the gate on every exit path.
        schedule { [weak self] in
            guard let self else { return }
            defer { self.gate.finishScratchpadOpenRequest() }
            let current = self.state()
            guard !current.recordingShortcut, !current.videoRenameBusy,
                  !current.recordingBusy, !current.screenshotBusy else { return }
            self.actions.scratchpad()
        }
    }
}

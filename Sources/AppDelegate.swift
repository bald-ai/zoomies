import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: TrayService!
    private var settingsWindowController: SettingsWindowController?

    private let settingsStore: SettingsStore
    private let makeServices: @MainActor (SettingsStore) -> Services
    private let presentation: Presentation
    private let finderSelection: FinderSelectionLookupCoordinator.SelectionRunner
    private var hotKeyService: HotKeyService!
    private var screenshotService: ScreenshotService!
    private var recordingService: ScreenRecordingService!
    private var videoRenameController: VideoRenameWorkflowController?
    private var clipboardService: ClipboardService!
    private var scratchpadService: ScratchpadService!
    private var backupService: BackupService!
    private var screenshotSoundPlayer: ScreenshotSoundPlayer!
    private let finderSelectionLookup = FinderSelectionLookupCoordinator()

    struct Services {
        let backup: BackupService
        let clipboard: ClipboardService
        let screenshot: ScreenshotService
        let scratchpad: ScratchpadService
        let hotKeys: HotKeyService
        let recording: ScreenRecordingService
        let sound: ScreenshotSoundPlayer
    }

    struct Presentation {
        var tray: @MainActor (@escaping () -> Void) -> TrayService = { TrayService(onShowSettings: $0) }
        var welcome: @MainActor (NSAlert) -> Void = { _ = $0.runModal() }
        var video: @MainActor (VideoRenameWorkflowController) -> Void = { $0.start() }
        var settings: @MainActor (SettingsWindowController) -> Void = { controller in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        var terminationReply: @MainActor (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    }

    override convenience init() {
        self.init(settingsStore: SettingsStore())
    }

    init(settingsStore: SettingsStore,
         makeServices: @escaping @MainActor (SettingsStore) -> Services = AppDelegate.makeNativeServices,
         presentation: Presentation = Presentation(),
         finderSelection: @escaping FinderSelectionLookupCoordinator.SelectionRunner = { try FinderSelectionService.selection() }) {
        self.settingsStore = settingsStore
        self.makeServices = makeServices
        self.presentation = presentation
        self.finderSelection = finderSelection
        super.init()
    }

    private static func makeNativeServices(settings: SettingsStore) -> Services {
        let backup = BackupService()
        let clipboard = ClipboardService()
        let sound = ScreenshotSoundPlayer()
        return Services(backup: backup, clipboard: clipboard,
                        screenshot: ScreenshotService(settingsStore: settings, backupService: backup,
                                                      clipboardService: clipboard, soundPlayer: sound),
                        scratchpad: ScratchpadService(clipboardService: clipboard), hotKeys: HotKeyService(),
                        recording: ScreenRecordingService(), sound: sound)
    }

    private lazy var commands = ApplicationCommands(state: { [unowned self] in
        ApplicationCommands.State(
            recordingShortcut: settingsWindowController?.isRecordingAnyShortcut == true,
            videoRenameBusy: isVideoRenameBusy,
            scratchpadBusy: scratchpadService.isBusyForUserCommands,
            screenshotBusy: screenshotService.isBusyForUserCommands,
            finderLookupBusy: finderSelectionLookup.isLookupInProgress,
            recordingBusy: recordingService.isBusyForUserCommands,
            stopAvailable: recordingService.isStopAvailable)
    }, actions: .init(
        area: { [unowned self] in screenshotService.captureArea() },
        fullScreen: { [unowned self] in screenshotService.captureFullScreen() },
        reopenFinder: { [unowned self] in
            finderSelectionLookup.requestSelection(runSelection: finderSelection) { [weak self] in self?.handleFinderSelectionResult($0) }
        },
        scratchpad: { [unowned self] in scratchpadService.open() },
        startRecording: { [unowned self] in recordingService.start(frameRate: settingsStore.settings.recordingFrameRate) },
        stopRecording: { [unowned self] in recordingService.stop() }))

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore.load()

        let services = makeServices(settingsStore)
        backupService = services.backup
        clipboardService = services.clipboard
        screenshotService = services.screenshot
        scratchpadService = services.scratchpad
        hotKeyService = services.hotKeys
        recordingService = services.recording
        screenshotSoundPlayer = services.sound

        // Cached clipboard files and backups belong to the previous session.
        backupService.purgeAllBackups()
        clipboardService.purgeAllCachedFiles()
        screenshotSoundPlayer.prewarmCaptureSound()
        recordingService.onUpdate = { [weak self] in
            self?.refreshRecordingUI()
        }
        recordingService.onRecordingSaved = { [weak self] url in
            self?.openVideoRename(for: url)
        }

        statusItemController = presentation.tray( { [weak self] in
            self?.showSettings()
        })
        refreshRecordingUI()

        registerHotKeys()
        showWelcomeInfo()
        presentSettingsRepairNoticeIfNeeded()
    }

    private func showWelcomeInfo() {
        DispatchQueue.main.async { [presentation] in
            // Keep the welcome and shortcut setup tips visible on launch.
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Welcome to Zoomies"
            alert.informativeText = """
            Hello! Please take 30 seconds to get set up and give Zoomies a proper chance.

            For the best experience, I recommend swapping your screenshot shortcuts: use Cmd+Shift for Zoomies and Option+Shift for macOS screenshots.

            First, move the macOS shortcuts to Option+Shift in System Settings → Keyboard → Keyboard Shortcuts → Screenshots. Then set Zoomies to Cmd+Shift from the Zoomies menu-bar icon → Settings → Shortcuts.

            Default shortcuts:
            • Option+Shift+4 → Area capture
            • Option+Shift+3 → Full-screen capture
            • Option+Shift+2 → Edit or rename an image selected in Finder
            • Option+Shift+1 → Create a scratchpad note
            • Option+Shift+5 → Start/stop screen recording (macOS 15+)

            On your first capture, allow Screen Recording when macOS asks. You can also enable it later in System Settings → Privacy & Security → Screen Recording.
            """
            alert.addButton(withTitle: "OK")
            presentation.welcome(alert)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recordingService.isBusyForUserCommands else {
            return .terminateNow
        }
        // Request stop and let the recording finalize before quitting.
        // The service bounds the wait so termination never hangs forever.
        recordingService.stopForAppTermination { [presentation] in
            presentation.terminationReply(true)
        }
        return .terminateLater
    }

    private func presentSettingsRepairNoticeIfNeeded() {
        guard settingsStore.didRepairInvalidSettingsOnLastLoad else { return }
        DispatchQueue.main.async {
            AlertPresenter.presentWarning(
                title: "Some settings were repaired",
                message: "Zoomies found invalid values in its saved settings and restored those to their defaults. Your other settings were left unchanged."
            )
        }
    }

    private func registerHotKeys() {
        hotKeyService.onRegistrationFailures = { failures in
            DispatchQueue.main.async {
                AlertPresenter.presentWarning(
                    title: "Some shortcuts couldn't be registered",
                    message: """
                    These combos are already taken by macOS or another app, so they won't work:

                    \(failures.joined(separator: "\n"))

                    Free them up in System Settings → Keyboard → Keyboard Shortcuts, or pick a different combo in Zoomies Settings. You can always open the Scratchpad from the menu-bar icon.
                    """
                )
            }
        }
        hotKeyService.registerShortcuts(settings: settingsStore.settings,
                                        areaHandler: { [weak self] in self?.triggerAreaScreenshot() },
                                        fullHandler: { [weak self] in self?.triggerFullScreenshot() },
                                        reopenFinderSelectionHandler: { [weak self] in self?.triggerReopenFinderSelection() },
                                        openScratchpadHandler: { [weak self] in self?.triggerOpenScratchpad() },
                                        toggleRecordingHandler: { [weak self] in self?.toggleRecording() })
    }

    private func refreshRecordingUI() {
        statusItemController.updateRecording(state: recordingService.state,
                                             elapsed: recordingService.elapsed)
    }

    /// Single entry point for the recording menu command and shortcut.
    /// A stop request is honored before any busy-state checks so Stop stays
    /// available while recording; startup is rejected while screenshot,
    /// note, Finder-reopen, or video-rename work is active or opening.
    private func toggleRecording() {
        commands.perform(.toggleRecording)
    }

    /// Opens the rename panel for a successfully saved recording. The
    /// controller is retained until the flow finishes, keeping Zoomies busy
    /// for other operations meanwhile.
    private func openVideoRename(for url: URL) {
        guard videoRenameController == nil else { return }
        let controller = VideoRenameWorkflowController(
            fileURL: url,
            settingsStore: settingsStore,
            clipboardService: clipboardService
        )
        controller.onFinish = { [weak self] in
            self?.videoRenameController = nil
        }
        videoRenameController = controller
        presentation.video(controller)
    }

    private var isVideoRenameBusy: Bool {
        videoRenameController?.isBusyForUserCommands == true
    }

    private func triggerAreaScreenshot() { commands.perform(.area) }

    private func triggerFullScreenshot() { commands.perform(.fullScreen) }

    private func triggerReopenFinderSelection() { commands.perform(.reopenFinder) }

    private func handleFinderSelectionResult(_ result: Result<FinderSelectionService.Selection, Error>) {
        switch FinderReopenLogic.resolve(result) {
        case .open(let url):
            screenshotService.beginPostCaptureFlow(forExistingFileAt: url, on: nil, escapeKeyDeletesFile: false)
        case .warning(let title, let message, let settingsURL):
            if let settingsURL {
                AlertPresenter.presentWarningWithSettingsButton(title: title, message: message, settingsURL: settingsURL)
            } else {
                presentError(title: title, message: message)
            }
        }
    }

    private func triggerOpenScratchpad() { commands.perform(.scratchpad) }

    private func showSettings() {
        // Menu-item actions run while NSMenu is tracking; defer opening the window
        // to the next runloop turn so the menu can dismiss first.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let settingsWindowController = self.settingsWindowControllerOrCreate()
            self.presentation.settings(settingsWindowController)
        }
    }

    private func settingsWindowControllerOrCreate() -> SettingsWindowController {
        if let existing = settingsWindowController {
            return existing
        }
        let created = SettingsWindowController(settingsStore: settingsStore, hotKeyService: hotKeyService)
        settingsWindowController = created
        return created
    }

    private func presentError(title: String, message: String) {
        AlertPresenter.presentWarning(title: title, message: message)
    }
}

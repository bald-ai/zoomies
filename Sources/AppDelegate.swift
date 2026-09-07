import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: TrayService!
    private var settingsWindowController: SettingsWindowController?

    private let settingsStore = SettingsStore()
    private var hotKeyService: HotKeyService!
    private var screenshotService: ScreenshotService!
    private var clipboardService: ClipboardService!
    private var scratchpadService: ScratchpadService!
    private var backupService: BackupService!
    private let screenshotSoundPlayer = ScreenshotSoundPlayer()
    private var userCommandGate = UserCommandGate()
    private let finderSelectionLookup = FinderSelectionLookupCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore.load()

        backupService = BackupService()
        clipboardService = ClipboardService()
        
        // Intentional: clipboard cache is only needed to keep Cmd+Delete paste working
        // within the current app session. Purging on launch prevents stale cached files
        // from accumulating indefinitely across launches.
        backupService.purgeAllBackups()
        clipboardService.purgeAllCachedFiles()

        screenshotService = ScreenshotService(settingsStore: settingsStore,
                                             backupService: backupService,
                                             clipboardService: clipboardService,
                                             soundPlayer: screenshotSoundPlayer)
        screenshotSoundPlayer.prewarmCaptureSound()
        scratchpadService = ScratchpadService(clipboardService: clipboardService)
        hotKeyService = HotKeyService()

        statusItemController = TrayService(
            onOpenScratchpad: { [weak self] in
                self?.triggerOpenScratchpad()
            },
            onShowSettings: { [weak self] in
                self?.showSettings()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        registerHotKeys()
        showWelcomeInfo()
        presentSettingsRepairNoticeIfNeeded()
    }

    private func showWelcomeInfo() {
        DispatchQueue.main.async {
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

            On your first capture, allow Screen Recording when macOS asks. You can also enable it later in System Settings → Privacy & Security → Screen Recording.
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
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
                                        openScratchpadHandler: { [weak self] in self?.triggerOpenScratchpad() })
    }

    private func triggerAreaScreenshot() {
        if settingsWindowController?.isRecordingAnyShortcut == true {
            return
        }
        if isScratchpadBusyOrOpening {
            return
        }
        screenshotService.captureArea()
    }

    private func triggerFullScreenshot() {
        if settingsWindowController?.isRecordingAnyShortcut == true {
            return
        }
        if isScratchpadBusyOrOpening {
            return
        }
        screenshotService.captureFullScreen()
    }

    private func triggerReopenFinderSelection() {
        if settingsWindowController?.isRecordingAnyShortcut == true {
            return
        }
        if isScratchpadBusyOrOpening {
            return
        }
        if screenshotService.isBusyForUserCommands {
            return
        }

        finderSelectionLookup.requestSelection { [weak self] result in
            self?.handleFinderSelectionResult(result)
        }
    }

    private func handleFinderSelectionResult(_ result: Result<FinderSelectionService.Selection, Error>) {
        switch result {
        case .success(let selection):
            let url: URL
            switch selection {
            case .none:
                presentError(title: "No Finder Selection", message: "Select an image file in Finder, then press the shortcut again.")
                return
            case .multiple(let count):
                presentError(title: "Multiple Finder Items Selected", message: "Select exactly 1 image file in Finder (you selected \(count)), then press the shortcut again.")
                return
            case .single(let selectedURL):
                url = selectedURL
            }
            switch ImageSafety.inspectFile(at: url) {
            case .tooLarge:
                presentError(
                    title: "Image is too large",
                    message: "This image is too large to open safely. Choose a smaller screenshot and try again."
                )
                return
            case .notAnImage:
                presentError(title: "Not an Image", message: "The selected Finder item is not a readable image.")
                return
            case .safe:
                break
            }

            screenshotService.beginPostCaptureFlow(forExistingFileAt: url, on: nil, escapeKeyDeletesFile: false)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == "FinderSelectionService" && nsError.code == -2 {
                AlertPresenter.presentWarningWithSettingsButton(
                    title: "Automation Permission Required",
                    message: "Zoomies needs permission to communicate with Finder.\n\nOpen System Settings → Privacy & Security → Automation, and enable Finder under Zoomies.",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )
            } else if nsError.domain == "FinderSelectionService" && nsError.code == -3 {
                presentError(title: "Finder didn’t respond", message: nsError.localizedDescription)
            } else {
                presentError(title: "Finder Error", message: error.localizedDescription)
            }
        }
    }

    private func triggerOpenScratchpad() {
        guard userCommandGate.beginScratchpadOpenRequest() else { return }

        // Menu-item actions run while NSMenu is tracking; defer opening the
        // scratchpad to the next runloop turn so the menu can dismiss first.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            defer { self.userCommandGate.finishScratchpadOpenRequest() }
            if self.settingsWindowController?.isRecordingAnyShortcut == true {
                return
            }
            if self.screenshotService.isBusyForUserCommands {
                return
            }
            self.scratchpadService.open()
        }
    }

    private var isScratchpadBusyOrOpening: Bool {
        !userCommandGate.canStartScreenshot(
            scratchpadIsBusy: scratchpadService.isBusyForUserCommands
        )
    }

    private func showSettings() {
        // Menu-item actions run while NSMenu is tracking; defer opening the window
        // to the next runloop turn so the menu can dismiss first.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let settingsWindowController = self.settingsWindowControllerOrCreate()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
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

import AppKit
import CoreGraphics
import ScreenCaptureKit

protocol ScreenshotSoundPlaying {
    func playCaptureSound()
}

extension ScreenshotSoundPlayer: ScreenshotSoundPlaying {}

/// Handles screenshot capture, resizing, encoding and filename generation,
/// and then kicks off the rename/note workflow.
final class ScreenshotService: NSObject {
    enum CaptureMode { case area, fullScreen }
    enum ScreenResolutionError: LocalizedError {
        case missingDisplayID
        var errorDescription: String? { "Unable to determine display ID." }
    }

    struct ScreenSnapshot: Sendable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let scale: CGFloat
    }

    struct ScreenCandidate {
        let displayID: CGDirectDisplayID?
        let frame: CGRect
        let scale: CGFloat
    }

    private struct PreparedCaptureSave {
        let image: NSImage
        let targetURL: URL
        let currentCounter: Int
    }

    private let settingsStore: SettingsStore
    private let backupService: BackupService
    private let clipboardService: ClipboardService
    private let soundPlayer: ScreenshotSoundPlaying
    private let areaCapture: () async throws -> CGImage?
    private let workflowPresenter: (ScreenshotWorkflowController) -> Void
    private let errorPresenter: (String, String) -> Void
    private let captureScreen: (CaptureMode) throws -> ScreenSnapshot?
    private let regionCapture: ((CGRect, ScreenSnapshot) async throws -> CGImage)?

    private let fileManager: FileManager
    private let desktopDirectory: URL
    private let capturePersistenceQueue = DispatchQueue(label: "Zoomies.CapturePersistence", qos: .userInitiated)

    private var activeWorkflow: ScreenshotWorkflowController?
    private var isCaptureInProgress = false
    @MainActor private var contentCache: CaptureContentCache<SCShareableContent>?

    init(settingsStore: SettingsStore,
         backupService: BackupService,
         clipboardService: ClipboardService,
         fileManager: FileManager = .default,
         desktopDirectory: URL? = nil,
         soundPlayer: ScreenshotSoundPlaying = ScreenshotSoundPlayer(),
         areaCapture: @escaping () async throws -> CGImage? = { try await NativeAreaCapture.capture() },
         captureScreen: @escaping (CaptureMode) throws -> ScreenSnapshot? = ScreenshotService.currentCaptureScreen,
         regionCapture: ((CGRect, ScreenSnapshot) async throws -> CGImage)? = nil,
         workflowPresenter: @escaping (ScreenshotWorkflowController) -> Void = { $0.start() },
         errorPresenter: @escaping (String, String) -> Void = { AlertPresenter.presentWarning(title: $0, message: $1) }) {
        self.settingsStore = settingsStore
        self.backupService = backupService
        self.clipboardService = clipboardService
        self.soundPlayer = soundPlayer
        self.areaCapture = areaCapture
        self.captureScreen = captureScreen
        self.regionCapture = regionCapture
        self.workflowPresenter = workflowPresenter
        self.errorPresenter = errorPresenter
        self.fileManager = fileManager

        if let desktopDirectory {
            self.desktopDirectory = desktopDirectory
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            self.desktopDirectory = home.appendingPathComponent("Desktop", isDirectory: true)
        }

        super.init()
    }

    // MARK: - Public API

    func captureArea() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.captureArea()
            }
            return
        }

        guard canStartAreaCapture() else {
            return
        }

        performCapture { [self] in
            guard let image = try await areaCapture() else { return nil }
            guard let screen = try await MainActor.run(body: { try self.captureScreen(.area) }) else { return nil }
            return (image, screen.displayID)
        }
    }

    /// Captures the full contents of the display under the mouse.
    func captureFullScreen() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.captureFullScreen()
            }
            return
        }

        guard canStartFullScreenCapture() else {
            return
        }
        do {
            guard let screen = try captureScreen(.fullScreen) else { return }
            captureRegion(in: screen.frame, on: screen)
        } catch {
            handleCaptureFailure(error)
        }
    }

    /// Starts the rename/note flow for an already-saved image.
    func beginPostCaptureFlow(forExistingFileAt url: URL, on screen: NSScreen? = nil, escapeKeyDeletesFile: Bool = true) {
        beginPostCaptureFlow(forExistingFileAt: url,
                             initialImage: nil,
                             initialFilePersistence: nil,
                             initialScreenshotCounter: nil,
                             on: screen,
                             escapeKeyDeletesFile: escapeKeyDeletesFile)
    }

    func beginPostCaptureFlow(forExistingFileAt url: URL,
                              initialImage: NSImage? = nil,
                              initialFilePersistence: Task<URL, Error>? = nil,
                              initialScreenshotCounter: Int? = nil,
                              on screen: NSScreen? = nil,
                              escapeKeyDeletesFile: Bool = true) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.beginPostCaptureFlow(forExistingFileAt: url,
                                           initialImage: initialImage,
                                           initialFilePersistence: initialFilePersistence,
                                           initialScreenshotCounter: initialScreenshotCounter,
                                           on: screen,
                                           escapeKeyDeletesFile: escapeKeyDeletesFile)
            }
            return
        }

        guard activeWorkflow == nil else { return }

        if initialImage == nil {
            switch ImageSafety.inspectFile(at: url) {
            case .tooLarge:
                presentError(
                    title: "Image is too large",
                    message: "This image is too large to open safely."
                )
                return
            case .notAnImage, .safe:
                break
            }
        }

        let workflow = ScreenshotWorkflowController(
            fileURL: url,
            initialImage: initialImage,
            initialFilePersistence: initialFilePersistence,
            initialScreenshotCounter: initialScreenshotCounter,
            settingsStore: settingsStore,
            clipboardService: clipboardService,
            backupService: backupService,
            sourceScreen: screen,
            escapeKeyDeletesFile: escapeKeyDeletesFile
        )

        workflow.onFinish = { [weak self] in
            self?.activeWorkflow = nil
        }

        activeWorkflow = workflow
        workflowPresenter(workflow)
    }

    var isBusyForUserCommands: Bool {
        isCaptureInProgress || activeWorkflow != nil
    }

    /// Saves an arbitrary image to the Desktop using the current settings
    /// (maxWidth, filename template) and returns the resulting URL.
    func saveImageToDesktop(_ image: NSImage) throws -> URL {
        let prepared = try prepareCaptureSave(for: image)
        return try persistPreparedCapture(prepared)
    }

    // MARK: - Capture pipeline

    private func canStartNewCapture() -> Bool {
        if isCaptureInProgress {
            return false
        }
        if activeWorkflow != nil {
            return false
        }
        return true
    }

    func canStartAreaCapture() -> Bool {
        return canStartNewCapture()
    }

    func canStartFullScreenCapture() -> Bool {
        canStartNewCapture()
    }

    private func captureRegion(in rect: CGRect, on screen: ScreenSnapshot) {
        performCapture { [self] in
            let image: CGImage
            if let regionCapture {
                image = try await regionCapture(rect, screen)
            } else {
                image = try await captureCGImage(rect: rect, on: screen)
            }
            return (image, screen.displayID)
        }
    }

    /// Both capture adapters share command gating, cancellation, failure and
    /// the handoff to persistence. A nil result is user cancellation.
    private func performCapture(_ operation: @escaping () async throws -> (CGImage, CGDirectDisplayID)?) {
        guard canStartNewCapture() else { return }
        isCaptureInProgress = true
        Task { [self] in
            do {
                let result = try await operation()
                try await MainActor.run {
                    defer { self.isCaptureInProgress = false }
                    guard let (image, displayID) = result else { return }
                    try self.finishCapture(with: image, onDisplayID: displayID)
                }
            } catch {
                await MainActor.run {
                    self.isCaptureInProgress = false
                    self.handleCaptureFailure(error)
                }
            }
        }
    }

    private func finishCapture(with cgImage: CGImage, onDisplayID displayID: CGDirectDisplayID) throws {
        let imageSize = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let image = NSImage(cgImage: cgImage, size: imageSize)
        let preparedSave = try prepareCaptureSave(for: image)
        let initialFilePersistence = makeInitialFilePersistenceTask(for: preparedSave)
        beginPostCaptureFlow(forExistingFileAt: preparedSave.targetURL,
                             initialImage: preparedSave.image,
                             initialFilePersistence: initialFilePersistence,
                             initialScreenshotCounter: preparedSave.currentCounter,
                             on: screenForDisplayID(displayID))
        soundPlayer.playCaptureSound()
    }

    private func captureCGImage(rect: CGRect, on screen: ScreenSnapshot) async throws -> CGImage {
        let contentTask = await shareableContentTask()
        let content = try await contentTask.value
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw NSError(domain: "ScreenshotService",
                          code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "No display found for capture."])
        }
        let configuration = try Self.captureConfiguration(rect: rect, screen: screen)

        let excludedApplications = content.applications.filter { application in
            application.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: excludedApplications,
                                     exceptingWindows: [])

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                continuation.resume(with: Result { try Self.captureResult(image: image, error: error) })
            }
        }
    }

    static func captureConfiguration(rect: CGRect, screen: ScreenSnapshot) throws -> SCStreamConfiguration {
        guard let captureRect = ScreenshotServiceCoreLogic.screenCaptureRect(rectInScreenPoints: rect,
                                                                             screenFrame: screen.frame,
                                                                             scale: screen.scale) else {
            throw NSError(domain: "ScreenshotService",
                          code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Selected area is outside the display bounds."])
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = captureRect.pointRect
        configuration.width = Int(captureRect.pixelRect.width)
        configuration.height = Int(captureRect.pixelRect.height)
        configuration.showsCursor = true
        configuration.scalesToFit = false

        return configuration
    }

    static func captureResult(image: CGImage?, error: Error?) throws -> CGImage {
        if let error { throw error }
        guard let image else {
            throw NSError(domain: "ScreenshotService", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "No image captured."])
        }
        return image
    }

    // MARK: - Error handling

    private func handleCaptureFailure(_ error: Error) {
        let nsError = error as NSError
        // macOS already owns the native Screen Recording permission flow.
        // When the user declines capture authorization, avoid stacking our own alert on top.
        if ScreenshotServiceCoreLogic.shouldSuppressCaptureFailureAlert(nsError) {
            return
        }
        presentError(title: "Screenshot failed", message: nsError.localizedDescription)
    }

    // MARK: - Helpers

    static func currentCaptureScreen(_ mode: CaptureMode) throws -> ScreenSnapshot? {
        let screens = NSScreen.screens.map(screenCandidate)
        return try resolveCaptureScreen(mode, screens: screens, mouse: NSEvent.mouseLocation,
                                        mainDisplayID: CGMainDisplayID(), mainScreen: NSScreen.main.map(screenCandidate))
    }

    private static func screenCandidate(_ screen: NSScreen) -> ScreenCandidate {
        ScreenCandidate(displayID: screen.displayID, frame: screen.frame, scale: screen.backingScaleFactor)
    }

    static func resolveCaptureScreen(_ mode: CaptureMode, screens: [ScreenCandidate], mouse: CGPoint,
                                     mainDisplayID: CGDirectDisplayID, mainScreen: ScreenCandidate?) throws -> ScreenSnapshot? {
        guard let screen = preferredScreen(mode, screens: screens, mouse: mouse,
                                           mainDisplayID: mainDisplayID, mainScreen: mainScreen) else { return nil }
        guard let displayID = screen.displayID else {
            if mode == .fullScreen { throw ScreenResolutionError.missingDisplayID }
            return nil
        }
        return ScreenSnapshot(displayID: displayID, frame: screen.frame, scale: screen.scale)
    }

    private static func preferredScreen(_ mode: CaptureMode, screens: [ScreenCandidate], mouse: CGPoint,
                                        mainDisplayID: CGDirectDisplayID, mainScreen: ScreenCandidate?) -> ScreenCandidate? {
        let menuBarScreen = mode == .fullScreen
            ? screens.first(where: { $0.displayID == mainDisplayID }) : nil
        return screens.first(where: { $0.frame.contains(mouse) })
            ?? menuBarScreen
            ?? mainScreen ?? screens.first
    }

    private func screenForDisplayID(_ displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else {
            return nil
        }
        return NSScreen.screens.first(where: { $0.displayID == displayID })
    }

    private func resizedImageIfNeeded(_ image: NSImage, maxWidth: Int) -> NSImage {
        ScreenshotServiceCoreLogic.resizedImageIfNeeded(image, maxWidth: maxWidth)
    }

    private func uniqueScreenshotURL(in directory: URL, baseName: String) -> URL {
        ScreenshotServiceCoreLogic.uniqueScreenshotURL(
            in: directory,
            baseName: baseName,
            fileExists: { [fileManager] path in fileManager.fileExists(atPath: path) }
        )
    }

    private func prepareCaptureSave(for image: NSImage) throws -> PreparedCaptureSave {
        let settings = settingsStore.settings

        let finalImage: NSImage
        if settings.maxWidth > 0 {
            finalImage = resizedImageIfNeeded(image, maxWidth: settings.maxWidth)
        } else {
            finalImage = image
        }

        let date = Date()
        let currentCounter = settings.screenshotCounter
        let rawBaseName = settings.filenameTemplate.makeFilename(date: date, counter: currentCounter)
        let baseName = WorkflowFilenameLogic.sanitizeBaseName(rawBaseName)

        try fileManager.createDirectory(at: desktopDirectory, withIntermediateDirectories: true)
        let targetURL = uniqueScreenshotURL(in: desktopDirectory, baseName: baseName)
        return PreparedCaptureSave(image: finalImage,
                                   targetURL: targetURL,
                                   currentCounter: currentCounter)
    }

    private func makeInitialFilePersistenceTask(for preparedSave: PreparedCaptureSave) -> Task<URL, Error> {
        return Task { [weak self] in
            try await withCheckedThrowingContinuation { continuation in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "ScreenshotService",
                                                          code: -10,
                                                          userInfo: [NSLocalizedDescriptionKey: "Screenshot service was released before save completed."]))
                    return
                }

                self.capturePersistenceQueue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: NSError(domain: "ScreenshotService",
                                                              code: -10,
                                                              userInfo: [NSLocalizedDescriptionKey: "Screenshot service was released before save completed."]))
                        return
                    }

                    do {
                        let writtenURL = try self.persistPreparedCapture(preparedSave)
                        continuation.resume(returning: writtenURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func persistPreparedCapture(_ preparedSave: PreparedCaptureSave) throws -> URL {
        guard let data = ImageEncoding.pngData(from: preparedSave.image) else {
            throw NSError(domain: "ScreenshotService",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG data."])
        }

        try data.write(to: preparedSave.targetURL, options: .atomic)
        advanceScreenshotCounter(afterWritingCounter: preparedSave.currentCounter)
        return preparedSave.targetURL
    }

    private func advanceScreenshotCounter(afterWritingCounter currentCounter: Int) {
        let applyUpdate = { [settingsStore] in
            settingsStore.update { settings in
                settings.screenshotCounter = max(
                    settings.screenshotCounter,
                    Settings.nextScreenshotCounter(after: currentCounter)
                )
            }
        }

        if Thread.isMainThread {
            applyUpdate()
        } else {
            DispatchQueue.main.sync(execute: applyUpdate)
        }
    }

    private func shareableContentTask() async -> Task<SCShareableContent, Error> {
        await MainActor.run {
            let cache = contentCache ?? CaptureContentCache(lifetime: 2)
            contentCache = cache
            return cache.task {
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            }
        }
    }

    private func presentError(title: String, message: String) {
        errorPresenter(title, message)
    }
}

extension ScreenshotService: @unchecked Sendable {}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

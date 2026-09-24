import Foundation
import AVFoundation

protocol CaptureAudioPlaying: AnyObject {
    var currentTime: TimeInterval { get set }
    func stop()
    @discardableResult func play() -> Bool
    @discardableResult func prepareToPlay() -> Bool
}

extension AVAudioPlayer: CaptureAudioPlaying {}

/// Plays the bundled screenshot sound effect (single default sound).
///
/// The file lives at `Sources/Resources/screenshot-sound.mp3`.
final class ScreenshotSoundPlayer {
    private var player: CaptureAudioPlaying?
    private var playerURL: URL?
    private let locateResource: () -> URL?
    private let makePlayer: (URL) throws -> CaptureAudioPlaying
    private let playerQueue = DispatchQueue(label: "Zoomies.ScreenshotSoundPlayer", qos: .userInitiated)

    init(fileManager: FileManager = .default,
         locateResource: (() -> URL?)? = nil,
         makePlayer: @escaping (URL) throws -> CaptureAudioPlaying = { try AVAudioPlayer(contentsOf: $0) }) {
        self.locateResource = locateResource ?? {
            BundledResourceLocator.resourceURL(named: "screenshot-sound", withExtension: "mp3", fileManager: fileManager)
        }
        self.makePlayer = makePlayer
    }

    /// Waits for queued audio work, including preparation, before releasing resources.
    func flush() async {
        await withCheckedContinuation { continuation in
            playerQueue.async { continuation.resume() }
        }
    }

    func prewarmCaptureSound() {
        playerQueue.async { [weak self] in
            _ = self?.preparePlayerIfNeeded()
        }
    }

    func playCaptureSound() {
        playerQueue.async { [weak self] in
            self?.playCaptureSoundOnQueue()
        }
    }

    private func playCaptureSoundOnQueue() {
        guard let player = preparePlayerIfNeeded() else {
            return
        }

        // Restart from the beginning for each capture.
        player.stop()
        player.currentTime = 0
        _ = player.play()
    }

    private func preparePlayerIfNeeded() -> CaptureAudioPlaying? {
        guard let url = locateResource() else {
            return nil
        }

        do {
            if player == nil || playerURL != url {
                player = try makePlayer(url)
                player?.prepareToPlay()
                playerURL = url
            }
            return player
        } catch {
            player = nil
            playerURL = nil
            return nil
        }
    }
}

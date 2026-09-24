import XCTest
@testable import Zoomies

final class ScreenshotSoundPlayerTests: XCTestCase {
    private final class Audio: CaptureAudioPlaying {
        var events: [String] = []
        var currentTime: TimeInterval = 17 { didSet { events.append("seek:\(currentTime)") } }
        func stop() { events.append("stop") }
        func play() -> Bool { events.append("play"); return true }
        func prepareToPlay() -> Bool { events.append("prepare"); return true }
    }

    func testPrewarmReusesPlayerAndEachCaptureRestartsAtZero() async {
        let audio = Audio()
        var creations = 0
        let player = ScreenshotSoundPlayer(locateResource: { URL(fileURLWithPath: "/fixture.mp3") }, makePlayer: { _ in
            creations += 1
            return audio
        })
        player.prewarmCaptureSound()
        player.prewarmCaptureSound()
        player.playCaptureSound()
        player.playCaptureSound()
        await player.flush()
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(audio.events, ["prepare", "stop", "seek:0.0", "play", "stop", "seek:0.0", "play"])
    }

    func testMissingResourceAndCreationFailureAreRecoverableAndChangedURLRebuildsPlayer() async {
        let audio = Audio()
        var url: URL?
        var fail = true
        var attempts: [URL] = []
        let player = ScreenshotSoundPlayer(locateResource: { url }, makePlayer: { url in
            attempts.append(url)
            if fail { throw NSError(domain: "fixture", code: 1) }
            return audio
        })
        player.playCaptureSound()
        await player.flush()
        XCTAssertTrue(attempts.isEmpty)
        let first = URL(fileURLWithPath: "/one.mp3")
        url = first
        player.playCaptureSound()
        await player.flush()
        XCTAssertEqual(attempts, [first])
        XCTAssertTrue(audio.events.isEmpty)
        fail = false
        player.playCaptureSound()
        await player.flush()
        XCTAssertEqual(attempts, [first, first])
        XCTAssertEqual(audio.events, ["prepare", "stop", "seek:0.0", "play"])
        let second = URL(fileURLWithPath: "/two.mp3")
        url = second
        player.playCaptureSound()
        await player.flush()
        XCTAssertEqual(attempts, [first, first, second])
        XCTAssertEqual(audio.events.filter { $0 == "prepare" }.count, 2)
    }
}

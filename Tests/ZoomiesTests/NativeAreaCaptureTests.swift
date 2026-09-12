import XCTest
import AppKit
@testable import Zoomies

final class NativeAreaCaptureTests: XCTestCase {
    func testCancellationCleansTemporaryFiles() async throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let result = try await NativeAreaCapture.capture(executableURL: URL(fileURLWithPath: "/usr/bin/false"), temporaryRoot: root)
        XCTAssertNil(result)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testLaunchFailureCleansTemporaryFiles() async throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        do {
            _ = try await NativeAreaCapture.capture(executableURL: root.appendingPathComponent("missing"), temporaryRoot: root)
            XCTFail("Expected launch failure")
        } catch {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testCaptureLoadsImageBeforeCleaningTemporaryFiles() async throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let fixture = root.appendingPathComponent("fixture.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 18,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 128, bitsPerPixel: 32))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: fixture)
        let script = root.appendingPathComponent("capture")
        try "#!/bin/sh\ncp \"$(dirname \"$0\")/fixture.png\" \"$5\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let result = try await NativeAreaCapture.capture(executableURL: script, temporaryRoot: root)
        let image = try XCTUnwrap(result)
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 18)
        XCTAssertNotNil(ScreenshotServiceCoreLogic.pngData(from: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["capture", "fixture.png"])
    }

    func testCaptureFailureReportsDiagnosticAndCleansFiles() async throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let script = root.appendingPathComponent("capture")
        try "#!/bin/sh\necho 'capture permission denied' >&2\nexit 1\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        do {
            _ = try await NativeAreaCapture.capture(executableURL: script, temporaryRoot: root, hasScreenCaptureAccess: { true })
            XCTFail("Expected capture failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("capture permission denied"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["capture"])
    }

    func testMissingPermissionDoesNotAddAnErrorToTheSystemPrompt() async throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let script = root.appendingPathComponent("capture")
        try "#!/bin/sh\necho 'could not create image from rect' >&2\nexit 1\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let image = try await NativeAreaCapture.capture(executableURL: script, temporaryRoot: root, hasScreenCaptureAccess: { false })
        XCTAssertNil(image)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["capture"])
    }
}

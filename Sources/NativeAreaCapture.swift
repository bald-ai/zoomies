import Foundation
import CoreGraphics
import ImageIO

/// Runs Apple's selector without activating a Zoomies window first.
enum NativeAreaCapture {
    static func capture(executableURL: URL = URL(fileURLWithPath: "/usr/sbin/screencapture"),
                        temporaryRoot: URL = FileManager.default.temporaryDirectory,
                        hasScreenCaptureAccess: () -> Bool = { CGPreflightScreenCaptureAccess() }) async throws -> CGImage? {
        let directory = temporaryRoot.appendingPathComponent("Zoomies-Capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("capture.png")
        let errorURL = directory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorOutput = try FileHandle(forWritingTo: errorURL)
        defer { try? errorOutput.close() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-i", "-x", "-t", "png", imageURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }

        return try readCaptureResult(imageURL: imageURL, errorURL: errorURL, status: status,
                                     hasScreenCaptureAccess: hasScreenCaptureAccess)
    }

    private static func readCaptureResult(imageURL: URL, errorURL: URL, status: Int32,
                                          hasScreenCaptureAccess: () -> Bool) throws -> CGImage? {
        let diagnostic = (try? String(contentsOf: errorURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasImage = FileManager.default.fileExists(atPath: imageURL.path)
        // Escape exits without an image. Control may send the image straight to the clipboard.
        if !hasImage && diagnostic.isEmpty && (status == 0 || status == 1) {
            return nil
        }
        guard status == 0, hasImage else {
            return try handleCaptureFailure(status: status, diagnostic: diagnostic, hasImage: hasImage,
                                            hasScreenCaptureAccess: hasScreenCaptureAccess)
        }
        return try decodeCapture(at: imageURL)
    }

    private static func handleCaptureFailure(status: Int32, diagnostic: String, hasImage: Bool,
                                              hasScreenCaptureAccess: () -> Bool) throws -> CGImage? {
        // macOS owns permission prompting; a first request may exit before access is granted.
        if !hasImage && !hasScreenCaptureAccess() { return nil }
        throw NSError(domain: "NativeAreaCapture", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: diagnostic.isEmpty ? "macOS could not complete the screenshot." : diagnostic
        ])
    }

    private static func decodeCapture(at imageURL: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw NSError(domain: "NativeAreaCapture", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to read the screenshot returned by macOS."
            ])
        }
        return image
    }
}

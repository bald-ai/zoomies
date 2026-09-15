import XCTest
import AppKit
@testable import Zoomies

final class ClipboardServiceTests: XCTestCase {
    func testPurgeAllCachedFilesRemovesExistingFiles() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)

        let service = ClipboardService(fileManager: .default, cacheDirectory: cache)
        try Data("a".utf8).write(to: cache.appendingPathComponent("a.txt"), options: .atomic)
        try Data("b".utf8).write(to: cache.appendingPathComponent("b.txt"), options: .atomic)

        service.purgeAllCachedFiles()
        let remaining = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCopyFileWithCacheCreatesCachedCopy() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)
        let source = root.appendingPathComponent("image.png")
        try TestSupport.writeSolidImagePNG(to: source)

        let service = ClipboardService(fileManager: .default, cacheDirectory: cache)
        service.copyFile(at: source, useCache: true)

        let cached = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertEqual(cached.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cached[0].path))
    }

    func testCopyFileWithoutCacheDoesNotWriteCacheFile() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)
        let source = root.appendingPathComponent("image.png")
        try TestSupport.writeSolidImagePNG(to: source)

        let service = ClipboardService(fileManager: .default, cacheDirectory: cache)
        service.copyFile(at: source, useCache: false)

        let cached = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertTrue(cached.isEmpty)
    }

    func testCopyFileWithCacheUsesUniqueNameOnCollision() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)
        let source = root.appendingPathComponent("image.png")
        try TestSupport.writeSolidImagePNG(to: source)

        let service = ClipboardService(fileManager: .default, cacheDirectory: cache)
        service.copyFile(at: source, useCache: true)
        service.copyFile(at: source, useCache: true)

        let cached = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertEqual(cached.count, 2)
        XCTAssertTrue(cached.contains(where: { $0.lastPathComponent == "image.png" }))
        XCTAssertTrue(cached.contains(where: { $0.lastPathComponent == "image_2.png" }))
    }

    func testCopyFileWithCacheMissingSourceDoesNotCreateCacheEntry() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)
        let source = root.appendingPathComponent("missing.png")

        let service = ClipboardService(fileManager: .default, cacheDirectory: cache)
        service.copyFile(at: source, useCache: true)

        let cached = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertTrue(cached.isEmpty)
    }

    func testCopyFileWithCacheReturnsFalseWhenCacheCopyFailsAndDoesNotFallBack() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cacheAsFile = root.appendingPathComponent("clipboard")
        try Data("not-a-directory".utf8).write(to: cacheAsFile, options: .atomic)
        let source = root.appendingPathComponent("image.png")
        try TestSupport.writeSolidImagePNG(to: source)

        var pasteboardWrites = 0
        let service = ClipboardService(
            fileManager: .default,
            cacheDirectory: cacheAsFile,
            pasteboardWriter: { _ in
                pasteboardWrites += 1
                return true
            }
        )

        XCTAssertNil(service.copyFile(at: source, useCache: true))
        XCTAssertEqual(pasteboardWrites, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyFileWithCacheReturnsFalseWhenPasteboardPublicationFails() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)
        let source = root.appendingPathComponent("image.png")
        try TestSupport.writeSolidImagePNG(to: source)

        let service = ClipboardService(
            fileManager: .default,
            cacheDirectory: cache,
            pasteboardWriter: { _ in false }
        )

        XCTAssertNil(service.copyFile(at: source, useCache: true))
        let cached = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertEqual(cached.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyImageAsFileReturnsFalseWhenPasteboardPublicationFails() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)
        let service = ClipboardService(
            fileManager: .default,
            cacheDirectory: cache,
            pasteboardWriter: { _ in false }
        )

        XCTAssertNil(service.copyImageAsFile(TestSupport.solidImage(), fileName: "shot.png"))
        let cached = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertEqual(cached.count, 1)
    }

    func testCopyFileWithCacheMissingSourceReturnsFalse() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }
        let cache = root.appendingPathComponent("clipboard", isDirectory: true)
        let source = root.appendingPathComponent("missing.png")

        var pasteboardWrites = 0
        let service = ClipboardService(
            fileManager: .default,
            cacheDirectory: cache,
            pasteboardWriter: { _ in
                pasteboardWrites += 1
                return true
            }
        )
        XCTAssertNil(service.copyFile(at: source, useCache: true))
        XCTAssertEqual(pasteboardWrites, 0)

        let cached = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        XCTAssertTrue(cached.isEmpty)
    }
}

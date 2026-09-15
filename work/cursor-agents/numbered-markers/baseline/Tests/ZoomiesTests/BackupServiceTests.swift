import XCTest
@testable import Zoomies

final class BackupServiceTests: XCTestCase {
    func testCreateBackupCopiesAndReplacesExisting() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let originals = root.appendingPathComponent("originals", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)

        let service = BackupService(fileManager: .default, backupsDirectory: backups)
        let original = originals.appendingPathComponent("shot.png")
        try Data("v1".utf8).write(to: original, options: .atomic)

        service.createBackup(forOriginalURL: original)
        let backup = service.backupURL(forOriginalURL: original)
        XCTAssertEqual(try Data(contentsOf: backup), Data("v1".utf8))

        try Data("v2".utf8).write(to: original, options: .atomic)
        service.createBackup(forOriginalURL: original)
        XCTAssertEqual(try Data(contentsOf: backup), Data("v2".utf8))
    }

    func testRemoveBackupDeletesExistingFile() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let originals = root.appendingPathComponent("originals", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)

        let service = BackupService(fileManager: .default, backupsDirectory: backups)
        let original = originals.appendingPathComponent("shot.png")
        try Data("v1".utf8).write(to: original, options: .atomic)
        service.createBackup(forOriginalURL: original)

        service.removeBackup(forOriginalURL: original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.backupURL(forOriginalURL: original).path))
    }

    func testSameNameInDifferentFoldersGetsDifferentBackups() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let folderA = root.appendingPathComponent("a", isDirectory: true)
        let folderB = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

        let service = BackupService(fileManager: .default, backupsDirectory: backups)
        let first = folderA.appendingPathComponent("shot.png")
        let second = folderB.appendingPathComponent("shot.png")
        try Data("from-a".utf8).write(to: first, options: .atomic)
        try Data("from-b".utf8).write(to: second, options: .atomic)

        XCTAssertTrue(service.createBackup(forOriginalURL: first))
        XCTAssertTrue(service.createBackup(forOriginalURL: second))

        let backupA = service.backupURL(forOriginalURL: first)
        let backupB = service.backupURL(forOriginalURL: second)
        XCTAssertNotEqual(backupA, backupB)
        XCTAssertEqual(try Data(contentsOf: backupA), Data("from-a".utf8))
        XCTAssertEqual(try Data(contentsOf: backupB), Data("from-b".utf8))

        // Removing one backup leaves the other intact.
        service.removeBackup(forOriginalURL: first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupA.path))
        XCTAssertEqual(try Data(contentsOf: backupB), Data("from-b".utf8))
    }

    func testCreateBackupReturnsFalseWhenSourceIsMissing() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let service = BackupService(fileManager: .default, backupsDirectory: backups)
        let missing = root.appendingPathComponent("nope.png")

        XCTAssertFalse(service.createBackup(forOriginalURL: missing))
    }

    func testPurgeAllBackupsClearsDirectory() throws {
        let root = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.removeIfExists(root) }

        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let service = BackupService(fileManager: .default, backupsDirectory: backups)
        try Data("a".utf8).write(to: backups.appendingPathComponent("1.bin"), options: .atomic)
        try Data("b".utf8).write(to: backups.appendingPathComponent("2.bin"), options: .atomic)

        service.purgeAllBackups()

        let remaining = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty)
    }
}

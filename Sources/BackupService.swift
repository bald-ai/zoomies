import Foundation

/// Manages on-disk backups of original screenshots prior to editing.
///
/// Backups live under `~/Library/Caches/zoomies/backups` and are
/// addressed deterministically by the original file's name plus a stable
/// hash of its full path, so same-named files in different folders never
/// share a backup. This keeps the implementation simple while still
/// satisfying the "delete also removes any backups" requirement.
final class BackupService {
    let backupsDirectory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, backupsDirectory: URL? = nil) {
        self.fileManager = fileManager

        if let backupsDirectory {
            self.backupsDirectory = backupsDirectory
        } else {
            let base = fileManager.homeDirectoryForCurrentUser
            self.backupsDirectory = base
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent("zoomies", isDirectory: true)
                .appendingPathComponent("backups", isDirectory: true)
        }

        try? fileManager.createDirectory(at: self.backupsDirectory, withIntermediateDirectories: true)
    }
    
    /// Removes all files under `~/Library/Caches/zoomies/backups`.
    /// Mirrors the legacy app behavior to avoid orphaned backups across dev sessions.
    func purgeAllBackups() {
        DirectoryPurgeLogic.purgeContents(of: backupsDirectory, fileManager: fileManager, label: "backup cache")
    }

    /// Returns the backup URL corresponding to a given original screenshot
    /// file URL. The name carries a stable hash of the full original path so
    /// same-named files in different folders map to different backups.
    func backupURL(forOriginalURL url: URL) -> URL {
        let name = url.lastPathComponent
        let hash = Self.stableHashHex(for: url.path)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let backupName = ext.isEmpty ? "\(stem)-\(hash)" : "\(stem)-\(hash).\(ext)"
        return backupsDirectory.appendingPathComponent(backupName)
    }

    /// Creates or replaces a backup for the given original screenshot.
    /// Returns false when the backup could not be written; callers warn
    /// instead of treating the save as fully protected.
    @discardableResult
    func createBackup(forOriginalURL url: URL) -> Bool {
        let backupURL = backupURL(forOriginalURL: url)
        do {
            // Best-effort replacement to avoid fileExists/remove TOCTOU windows.
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: url, to: backupURL)
            return true
        } catch {
            return false
        }
    }

    /// FNV-1a 64-bit hex. Swift's `Hashable` hash is randomized per launch,
    /// so backups need an explicitly stable hash to round-trip across runs.
    private static func stableHashHex(for string: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    /// Removes the backup associated with the given original screenshot, if it
    /// exists. Called when the user deletes a screenshot (with or without
    /// copy+delete).
    func removeBackup(forOriginalURL url: URL) {
        let backupURL = backupURL(forOriginalURL: url)
        do {
            try fileManager.removeItem(at: backupURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
        }
    }
}

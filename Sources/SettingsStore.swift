import Foundation

/// Simple in-memory settings store backed by a JSON file on disk.
///
/// New settings live at `~/Library/Application Support/Zoomies/settings.json`.
/// On first launch after upgrading, the old `~/.screenshot_app_settings.json`
/// file is read and copied to the new location.
final class SettingsStore {
    private(set) var settings: Settings

    private let fileURL: URL
    private let legacyFileURL: URL?
    private let fileManager: FileManager

    init(fileManager: FileManager = .default, fileURL: URL? = nil, legacyFileURL: URL? = nil) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
            self.legacyFileURL = legacyFileURL
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            self.fileURL = home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Zoomies", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
            self.legacyFileURL = legacyFileURL
                ?? home.appendingPathComponent(".screenshot_app_settings.json", isDirectory: false)
        }

        self.settings = .default
    }

    /// Loads settings from disk if possible, otherwise keeps defaults.
    ///
    /// On any decoding error, the file is ignored and defaults are used.
    func load() {
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                settings = try loadSettings(from: fileURL).normalized()
                do {
                    try persist(settings)
                } catch {
                    AppLog.event("settings normalization persist failed: \(error.localizedDescription)")
                }
                return
            }

            if let legacyFileURL, fileManager.fileExists(atPath: legacyFileURL.path) {
                settings = try loadSettings(from: legacyFileURL).normalized()
                do {
                    try persist(settings)
                } catch {
                    AppLog.event("settings migration persist failed: \(error.localizedDescription)")
                }
                return
            }

            // First launch – write out defaults so future loads succeed.
            do {
                settings = .default
                try persist(settings)
            } catch {
                AppLog.event("settings defaults persist failed: \(error.localizedDescription)")
            }
        } catch {
            // Fall back to defaults but do not overwrite the possibly-bad file.
            // This mirrors many macOS apps' behavior.
            settings = .default
            AppLog.event("settings load failed: \(error.localizedDescription)")
        }
    }

    /// Saves the current settings to disk.
    private func save() {
        do {
            try persist(settings)
        } catch {
            AppLog.event("settings save failed: \(error.localizedDescription)")
        }
    }

    /// Applies a mutation to settings and persists the result.
    func update(_ block: (inout Settings) -> Void) {
        block(&settings)
        settings = settings.normalized()
        save()
    }

    // MARK: - Private

    private func loadSettings(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(Settings.self, from: data)
    }

    private func persist(_ settings: Settings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings.normalized())

        // Ensure parent directory exists (it should, but be defensive).
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        try data.write(to: fileURL, options: [.atomic])
    }
}

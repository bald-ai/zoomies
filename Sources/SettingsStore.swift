import Foundation

/// Simple in-memory settings store backed by a JSON file on disk.
///
/// New settings live at `~/Library/Application Support/Zoomies/settings.json`.
/// On first launch after upgrading, the old `~/.screenshot_app_settings.json`
/// file is read and copied to the new location.
final class SettingsStore {
    typealias PersistWriter = (_ data: Data, _ url: URL) throws -> Void

    private(set) var settings: Settings

    /// True when the most recent `load()` reset one or more semantically invalid
    /// fields *and* those repairs were written durably. An unwritable file must
    /// not claim a repair, or the launch notice would repeat forever.
    private(set) var didRepairInvalidSettingsOnLastLoad = false

    private let fileURL: URL
    private let legacyFileURL: URL?
    private let fileManager: FileManager
    private let persistWriter: PersistWriter?

    init(fileManager: FileManager = .default,
         fileURL: URL? = nil,
         legacyFileURL: URL? = nil,
         persistWriter: PersistWriter? = nil) {
        self.fileManager = fileManager
        self.persistWriter = persistWriter

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
        didRepairInvalidSettingsOnLastLoad = false
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                let repaired = applyLoadedSettings(try loadSettings(from: fileURL))
                persistLoadedSettings(repaired: repaired)
                return
            }

            if let legacyFileURL, fileManager.fileExists(atPath: legacyFileURL.path) {
                let repaired = applyLoadedSettings(try loadSettings(from: legacyFileURL))
                persistLoadedSettings(repaired: repaired)
                return
            }

            // First launch – write out defaults so future loads succeed.
            settings = .default
            persistLoadedSettings(repaired: false)
        } catch {
            // Fall back to defaults but do not overwrite the possibly-bad file.
            // This mirrors many macOS apps' behavior.
            settings = .default
        }
    }

    private func applyLoadedSettings(_ loaded: Settings) -> Bool {
        let normalized = loaded.normalizedReportingRepairs()
        settings = normalized.settings
        return normalized.repairedInvalidFields
    }

    private func persistLoadedSettings(repaired: Bool) {
        do {
            try persist(settings)
            didRepairInvalidSettingsOnLastLoad = repaired
        } catch {
            didRepairInvalidSettingsOnLastLoad = false
        }
    }

    /// Saves the current settings to disk.
    private func save() {
        try? persist(settings)
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

        if let persistWriter {
            try persistWriter(data, fileURL)
        } else {
            try data.write(to: fileURL, options: [.atomic])
        }
    }
}

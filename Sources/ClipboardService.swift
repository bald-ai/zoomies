import AppKit

/// Manages interactions with the NSPasteboard and on-disk clipboard cache.
///
/// Responsibilities:
/// - Copy images to the pasteboard for editor actions.
/// - Copy files to the pasteboard for rename/note/editor flows.
/// - For "Copy+Delete", cache a copy of the file under
///   `~/Library/Caches/zoomies/clipboard` so paste still works after
///   the original file is removed.
final class ClipboardService {
    typealias PasteboardWriter = (_ objects: [any NSPasteboardWriting]) -> Bool

    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let pasteboardWriter: PasteboardWriter

    init(fileManager: FileManager = .default,
         cacheDirectory: URL? = nil,
         pasteboardWriter: PasteboardWriter? = nil) {
        self.fileManager = fileManager
        self.pasteboardWriter = pasteboardWriter ?? ClipboardService.writeToGeneralPasteboard

        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = fileManager.homeDirectoryForCurrentUser
            self.cacheDirectory = base
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent("zoomies", isDirectory: true)
                .appendingPathComponent("clipboard", isDirectory: true)
        }

        // Best-effort directory creation.
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Removes all cached files under `~/Library/Caches/zoomies/clipboard`.
    /// This keeps paste behavior correct while preventing unbounded growth during frequent use.
    func purgeAllCachedFiles() {
        DirectoryPurgeLogic.purgeContents(of: cacheDirectory, fileManager: fileManager, label: "clipboard cache")
    }

    /// Places an image on the general pasteboard. Used by the editor's Copy
    /// action where only image data (not a file URL) is required.
    func writeImage(_ image: NSImage) {
        if pasteboardWriter([image]) {
            return
        }

        // Fallback for targets that expect explicit TIFF data.
        if let tiffData = image.tiffRepresentation {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(tiffData, forType: .tiff)
        }
    }

    /// Copies a file to the pasteboard.
    ///
    /// - Parameters:
    ///   - url: The source file URL.
    ///   - useCache: When true, the method copies the file into the
    ///     clipboard cache directory and publishes that cached URL on the
    ///     pasteboard. This is used for "Copy+Delete" so that paste continues
    ///     to work after the original file is deleted.
    /// - Returns: The published file URL when cache (if requested) and pasteboard
    ///   publication both succeeded; otherwise `nil`. Copy+Delete must not delete
    ///   the source on `nil`.
    @discardableResult
    func copyFile(at url: URL, useCache: Bool) -> URL? {
        let sourceURL: URL

        if useCache {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                let cachedURL = uniqueCachedURL(for: url.lastPathComponent)
                // Best-effort replacement to avoid fileExists/remove TOCTOU windows.
                try? fileManager.removeItem(at: cachedURL)
                try fileManager.copyItem(at: url, to: cachedURL)
                sourceURL = cachedURL
            } catch {
                return nil
            }
        } else {
            sourceURL = url
        }

        guard let image = NSImage(contentsOf: sourceURL) else {
            // Even if we can't build an NSImage, still publish the file URL so
            // Finder-style pastes work.
            return pasteboardWriter([sourceURL as NSURL]) ? sourceURL : nil
        }

        return pasteboardWriter([sourceURL as NSURL, image]) ? sourceURL : nil
    }

    /// Writes an in-memory image to the clipboard cache as a file and publishes
    /// the cached file URL on the pasteboard. Used for "Copy+Delete" from the
    /// editor where the edited image was never saved to disk.
    ///
    /// - Returns: The cached file URL when the cache file was written and the
    ///   pasteboard accepted it; otherwise `nil`. Callers must keep the source
    ///   file if this returns `nil`.
    @discardableResult
    func copyImageAsFile(_ image: NSImage, fileName: String) -> URL? {
        // PNG-only: always cache the clipboard file as PNG.
        let pngFileName = (fileName as NSString).deletingPathExtension + ".png"
        let cachedURL = uniqueCachedURL(for: pngFileName)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cachedURL, options: .atomic)
        } catch {
            return nil
        }

        return pasteboardWriter([cachedURL as NSURL, image]) ? cachedURL : nil
    }

    // MARK: - Helpers

    private func uniqueCachedURL(for fileName: String) -> URL {
        UniqueFileURLLogic.uniqueURL(
            forProposedName: fileName,
            in: cacheDirectory,
            fileExists: { [fileManager] path in fileManager.fileExists(atPath: path) }
        )
    }

    private static func writeToGeneralPasteboard(_ objects: [any NSPasteboardWriting]) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }
}

import AppKit

struct WorkflowEncodedImageResult {
    let data: Data
    let outputURL: URL
}

enum WorkflowImagePersistenceLogic {
    typealias UniqueURLResolver = (_ proposedName: String, _ directory: URL) -> URL

    /// Originals larger than this are not embedded, to avoid bloating saved files.
    /// Generous enough that real screenshots (incl. full-screen Retina PNGs)
    /// always round-trip; only pathologically large originals are skipped.
    static let maxEmbeddedOriginalBytes = 50 * 1024 * 1024

    static func encodedImageData(from image: NSImage,
                                 originalURL: URL,
                                 cleanOriginalPNG: Data? = nil,
                                 prompt: String? = nil,
                                 editorState: EditorCanvasState? = nil,
                                 uniqueURL: UniqueURLResolver) -> WorkflowEncodedImageResult? {
        guard let data = ImageEncoding.pngData(from: image) else { return nil }
        let annotated = embedMetadata(in: data, cleanOriginalPNG: cleanOriginalPNG, prompt: prompt, editorState: editorState)
        return WorkflowEncodedImageResult(data: annotated, outputURL: pngOutputURL(originalURL, uniqueURL: uniqueURL))
    }

    private static func embedMetadata(in data: Data, cleanOriginalPNG: Data?, prompt: String?,
                                      editorState: EditorCanvasState?) -> Data {
        if let prompt, !prompt.isEmpty,
           let cleanOriginalPNG, cleanOriginalPNG.count < maxEmbeddedOriginalBytes,
           let embedded = PNGMetadata.embed(intoPNG: data, originalPNG: cleanOriginalPNG,
                                            prompt: prompt, editorState: editorState) {
            return embedded
        }
        return embedEditorState(in: data, editorState: editorState)
    }

    private static func embedEditorState(in data: Data, editorState: EditorCanvasState?) -> Data {
        guard let editorState, editorState.baseImagePNG.count < maxEmbeddedOriginalBytes,
              let embedded = PNGMetadata.embed(intoPNG: data, editorState: editorState) else { return data }
        return embedded
    }

    private static func pngOutputURL(_ originalURL: URL, uniqueURL: UniqueURLResolver) -> URL {
        let ext = originalURL.pathExtension.lowercased()
        guard ext != "png", !ext.isEmpty else { return originalURL }
        let proposedName = originalURL.deletingPathExtension().lastPathComponent + ".png"
        return uniqueURL(proposedName, originalURL.deletingLastPathComponent())
    }

    static func writeEncodedImageData(_ data: Data,
                                      to outputURL: URL,
                                      originalURL: URL,
                                      fileManager: FileManager = .default) throws -> URL {
        try data.write(to: outputURL, options: .atomic)

        if outputURL != originalURL, fileManager.fileExists(atPath: originalURL.path) {
            try? fileManager.removeItem(at: originalURL)
        }

        return outputURL
    }
}

import AppKit

struct WorkflowReopenMetadata {
    var cleanOriginalPNG: Data?
    var image: NSImage?
    var prompt: String?
    var editorState: EditorCanvasState?
    var outerImageIsUnsafe: Bool = false
}

enum WorkflowReopenMetadataLogic {
    /// Resolves the clean baseline image, in-memory image, and pre-filled prompt
    /// for a workflow, recovering embedded round-trip metadata on reopen.
    ///
    /// Invalid editor metadata is ignored so the flattened visible image still
    /// opens instead of crashing or rejecting a usable PNG. An unsafe outer
    /// image is rejected without decoding.
    static func resolve(fileURL: URL,
                        initialImage: NSImage?,
                        limits: ImageSafetyLimits = .runtime) -> WorkflowReopenMetadata {
        // Fresh capture: the in-memory image is already the clean original.
        // Snapshot it as PNG so it can be embedded as the round-trip baseline.
        if let initialImage {
            return WorkflowReopenMetadata(
                cleanOriginalPNG: ScreenshotServiceCoreLogic.pngData(from: initialImage),
                image: nil,
                prompt: nil,
                editorState: nil
            )
        }

        switch ImageSafety.inspectFile(at: fileURL, limits: limits) {
        case .tooLarge:
            return WorkflowReopenMetadata(outerImageIsUnsafe: true)
        case .notAnImage:
            return WorkflowReopenMetadata()
        case .safe:
            break
        }

        guard let fileData = ImageSafety.boundedFileData(at: fileURL, limits: limits) else {
            return WorkflowReopenMetadata(outerImageIsUnsafe: true)
        }
        return resolve(fileData: fileData, limits: limits)
    }

    static func resolve(fileData: Data,
                        limits: ImageSafetyLimits = .runtime) -> WorkflowReopenMetadata {
        switch ImageSafety.inspectData(fileData, limits: limits) {
        case .tooLarge:
            return WorkflowReopenMetadata(outerImageIsUnsafe: true)
        case .notAnImage:
            return WorkflowReopenMetadata()
        case .safe:
            break
        }

        let editorState = PNGMetadata.extractEditorState(fromPNG: fileData, limits: limits)
        if let extracted = PNGMetadata.extract(fromPNG: fileData, limits: limits) {
            let image = editorState.flatMap { ImageSafety.loadImageIfSafe($0.baseImagePNG, limits: limits) }
                ?? ImageSafety.loadImageIfSafe(extracted.originalPNG, limits: limits)
            return WorkflowReopenMetadata(
                cleanOriginalPNG: extracted.originalPNG,
                image: image,
                prompt: extracted.prompt,
                editorState: editorState
            )
        }
        if let editorState {
            return WorkflowReopenMetadata(
                cleanOriginalPNG: nil,
                image: ImageSafety.loadImageIfSafe(editorState.baseImagePNG, limits: limits),
                prompt: nil,
                editorState: editorState
            )
        }
        // Plain PNG with no (or unusable) metadata: the file itself is the
        // clean baseline. The outer image was already inspected as safe.
        if PNGMetadata.isPNG(fileData) {
            return WorkflowReopenMetadata(
                cleanOriginalPNG: fileData,
                image: nil,
                prompt: nil,
                editorState: nil
            )
        }
        return WorkflowReopenMetadata()
    }
}

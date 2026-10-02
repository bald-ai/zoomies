import Foundation

/// Resolves the selected file before AppDelegate performs any presentation.
/// File inspection is shared with normal reopening; Finder itself is never
/// needed to evaluate a selection result.
enum FinderReopenDecision: Equatable {
    case open(URL)
    /// A note PNG, reopened in the note flow with its text and drawing.
    case openNote(URL, InkNoteDocument)
    case warning(title: String, message: String, settingsURL: String?)
}

enum FinderReopenLogic {
    static func resolve(_ result: Result<FinderSelectionService.Selection, Error>) -> FinderReopenDecision {
        switch result {
        case .success(let selection): return resolve(selection)
        case .failure(let error): return resolve(error)
        }
    }

    private static func resolve(_ selection: FinderSelectionService.Selection) -> FinderReopenDecision {
        switch selection {
        case .none:
            return .warning(title: "No Finder Selection", message: "Select an image in Finder, then press the shortcut again.", settingsURL: nil)
        case .multiple(let count):
            return .warning(title: "Multiple Finder Items Selected", message: "Select exactly 1 image in Finder (you selected \(count)), then press the shortcut again.", settingsURL: nil)
        case .single(let url):
            return inspect(url)
        }
    }

    private static func inspect(_ url: URL) -> FinderReopenDecision {
        switch ImageSafety.inspectFile(at: url) {
        case .tooLarge:
            return .warning(title: "Image is too large", message: "This image is too large to open safely. Choose a smaller screenshot and try again.", settingsURL: nil)
        case .notAnImage:
            return .warning(title: "Not an Image", message: "The selected Finder item is not a readable image.", settingsURL: nil)
        case .safe:
            return note(at: url).map { .openNote(url, $0) } ?? .open(url)
        }
    }

    private static func note(at url: URL) -> InkNoteDocument? {
        guard url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return PNGMetadata.extractInkNote(fromPNG: data)
    }

    private static func resolve(_ error: Error) -> FinderReopenDecision {
        let error = error as NSError
        guard error.domain == "FinderSelectionService" else {
            return .warning(title: "Finder Error", message: error.localizedDescription, settingsURL: nil)
        }
        switch error.code {
        case -2:
            return .warning(title: "Automation Permission Required",
                message: "Zoomies needs permission to communicate with Finder.\n\nOpen System Settings → Privacy & Security → Automation, and enable Finder under Zoomies.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case -3:
            return .warning(title: "Finder didn’t respond", message: error.localizedDescription, settingsURL: nil)
        default:
            return .warning(title: "Finder Error", message: error.localizedDescription, settingsURL: nil)
        }
    }
}

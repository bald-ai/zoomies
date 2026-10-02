import Foundation

/// Pure filename logic for new notes.
///
/// Standalone `*Logic` enum following the codebase convention
/// (`UniqueFileURLLogic`, `WorkflowFilenameLogic`, …). No UIKit/AppKit coupling
/// so it stays testable.
enum ScratchpadFilenameLogic {
    /// Auto-generated base name (without extension), mirroring the macOS
    /// screenshot naming style: `Note 2026-05-29 at 14.32.15`.
    static func defaultBaseName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Note \(formatter.string(from: date))"
    }

    /// The name typed in the rename panel, cleaned like a screenshot name and
    /// without its extension; notes always save as `.png`.
    static func resolveBaseName(userInput: String?, fallback: String) -> String {
        let raw = (userInput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return fallback }
        let sanitized = WorkflowFilenameLogic.sanitizeFilename(raw, preservingExtensionOf: URL(fileURLWithPath: "/tmp/note.png"))
        let withoutExtension = (sanitized as NSString).deletingPathExtension
        return withoutExtension.isEmpty ? fallback : withoutExtension
    }
}

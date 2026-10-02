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
}

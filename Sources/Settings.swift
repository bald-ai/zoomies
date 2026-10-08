import Foundation
import Carbon

/// Top-level settings model persisted by `SettingsStore`.
struct Settings: Codable {
    /// Maximum width in pixels (0 = original size).
    var maxWidth: Int

    /// Whether cancelling an editing session asks before deleting or closing.
    var confirmBeforeClosing: Bool

    /// Global shortcut configuration.
    var shortcuts: Shortcuts

    /// Whether shortcuts were explicitly changed by the user in Settings.
    var shortcutsCustomized: Bool

    /// Global screenshot counter for filename generation.
    var screenshotCounter: Int

    /// Screen-recording frame rate. Only 30, 60, and 120 are supported.
    var recordingFrameRate: Int = 30

    /// Ordered active palette, from one to six catalog color IDs.
    var editorColorIDs: [String] = EditorPalette.defaultIDs

    /// Experimental: Tab on the note window opens the drawing editor. Read
    /// once at launch, so changing it takes a restart.
    var experimentalNoteEditor: Bool = false
}

extension Settings {
    /// Default settings used on first launch or when decoding fails.
    static let `default` = Settings(
        maxWidth: 0,
        confirmBeforeClosing: true,
        shortcuts: .default,
        shortcutsCustomized: false,
        screenshotCounter: 1,
        recordingFrameRate: 30
    )

    /// Returns a copy normalized to all invariants/constraints.
    func normalized() -> Settings {
        normalizedReportingRepairs().settings
    }

    /// Normalizes settings and reports whether any semantically invalid fields
    /// were reset. Retired-shortcut migration is not treated as a repair.
    func normalizedReportingRepairs() -> (settings: Settings, repairedInvalidFields: Bool) {
        var copy = self
        var repairedInvalidFields = false

        // Ensure maxWidth is never negative; 0 means "Original".
        if maxWidth < 0 {
            copy.maxWidth = 0
            repairedInvalidFields = true
        }

        // Ensure screenshot counter is always >= 1.
        if screenshotCounter < 1 {
            copy.screenshotCounter = 1
            repairedInvalidFields = true
        }

        // Only 30, 60, and 120 fps are supported; invalid values fall back to 30.
        if ![30, 60, 120].contains(copy.recordingFrameRate) {
            copy.recordingFrameRate = 30
            repairedInvalidFields = true
        }

        let palette = EditorPalette.normalized(copy.editorColorIDs)
        if palette != copy.editorColorIDs {
            copy.editorColorIDs = palette
            repairedInvalidFields = true
        }

        copy.shortcuts = copy.shortcuts.repairingUnsupportedKeyCodes {
            repairedInvalidFields = true
        }

        // Move older shipped defaults to current defaults, unless the user has
        // explicitly changed shortcuts in Settings.
        if !copy.shortcutsCustomized {
            copy.shortcuts.replaceRetiredDefaultShortcutsIfNeeded()
        }

        return (copy, repairedInvalidFields)
    }

    /// Non-trapping increment used after a screenshot is written.
    /// Values below 1 start at 2; `Int.max` stays at `Int.max`.
    static func nextScreenshotCounter(after current: Int) -> Int {
        let start = current < 1 ? 1 : current
        let (next, overflowed) = start.addingReportingOverflow(1)
        return overflowed ? start : next
    }
}

extension Settings {
    private enum CodingKeys: String, CodingKey {
        case maxWidth
        // Preserve the existing on-disk preference while correcting its behavior.
        case confirmBeforeClosing = "enterConfirmsDelete"
        case shortcuts
        case shortcutsCustomized
        case screenshotCounter
        case recordingFrameRate
        case editorColorIDs
        case experimentalNoteEditor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<T: Decodable>(_ type: T.Type, key: CodingKeys, fallback: T) throws -> T {
            try container.decodeIfPresent(type, forKey: key) ?? fallback
        }
        self.maxWidth = try decode(Int.self, key: .maxWidth, fallback: Settings.default.maxWidth)
        self.confirmBeforeClosing = try decode(Bool.self, key: .confirmBeforeClosing, fallback: Settings.default.confirmBeforeClosing)
        self.shortcuts = try decode(Shortcuts.self, key: .shortcuts, fallback: Settings.default.shortcuts)
        self.shortcutsCustomized = try decode(Bool.self, key: .shortcutsCustomized, fallback: false)
        self.screenshotCounter = try decode(Int.self, key: .screenshotCounter, fallback: Settings.default.screenshotCounter)
        self.editorColorIDs = try decode([String].self, key: .editorColorIDs, fallback: EditorPalette.defaultIDs)
        self.experimentalNoteEditor = try decode(Bool.self, key: .experimentalNoteEditor, fallback: false)
        let rawFrameRate = try decode(Int.self, key: .recordingFrameRate, fallback: Settings.default.recordingFrameRate)
        self.recordingFrameRate = [30, 60, 120].contains(rawFrameRate)
            ? rawFrameRate
            : Settings.default.recordingFrameRate
    }
}

// MARK: - Shortcuts

/// A single global shortcut (Carbon keyCode + modifiers).
struct Shortcut: Codable, Equatable, Hashable {
    /// Carbon virtual key code (kVK_* constants).
    var keyCode: UInt32

    /// Carbon modifier flags (cmd/alt/ctrl/shift).
    var modifierFlags: UInt32

    init(keyCode: UInt32, modifierFlags: UInt32) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    /// True when `keyCode` can be formatted and registered without trapping.
    var hasSupportedKeyCode: Bool {
        guard keyCode <= UInt32(UInt16.max) else { return false }
        return HotKeyService.isAllowedKeyCode(UInt16(keyCode))
    }
}

/// Grouping of all shortcuts used by the app.
struct Shortcuts: Codable, Equatable {
    var screenshotArea: Shortcut
    var screenshotFull: Shortcut
    var reopenFinderSelection: Shortcut
    var openScratchpad: Shortcut
    // Defaulted so previously persisted settings and existing call sites
    // without this field keep working; old files decode to the default.
    var toggleRecording: Shortcut = Shortcuts.defaultToggleRecording
}

extension Shortcuts {
    /// Option + Shift + 5. Chosen because 1-4 are taken by existing
    /// defaults and the retired Option+Shift+5 scratchpad combo was
    /// migrated away to Option+Shift+1.
    static let defaultToggleRecording = Shortcut(
        keyCode: UInt32(kVK_ANSI_5),
        modifierFlags: UInt32(optionKey | shiftKey)
    )

    /// Reasonable, non-conflicting defaults.
    /// These can later be changed via the shortcut recorder UI.
    static let `default` = Shortcuts(
        // Option + Shift + 4
        screenshotArea: Shortcut(
            keyCode: UInt32(kVK_ANSI_4),
            modifierFlags: UInt32(optionKey | shiftKey)
        ),
        // Option + Shift + 3
        screenshotFull: Shortcut(
            keyCode: UInt32(kVK_ANSI_3),
            modifierFlags: UInt32(optionKey | shiftKey)
        ),
        // Option + Shift + 2
        reopenFinderSelection: Shortcut(
            keyCode: UInt32(kVK_ANSI_2),
            modifierFlags: UInt32(optionKey | shiftKey)
        ),
        // Option + Shift + 1
        openScratchpad: Shortcut(
            keyCode: UInt32(kVK_ANSI_1),
            modifierFlags: UInt32(optionKey | shiftKey)
        ),
        toggleRecording: defaultToggleRecording
    )
}

extension Shortcuts {
    func repairingUnsupportedKeyCodes(onRepair: () -> Void) -> Shortcuts {
        var copy = self
        if !copy.screenshotArea.hasSupportedKeyCode {
            copy.screenshotArea = Shortcuts.default.screenshotArea
            onRepair()
        }
        if !copy.screenshotFull.hasSupportedKeyCode {
            copy.screenshotFull = Shortcuts.default.screenshotFull
            onRepair()
        }
        if !copy.reopenFinderSelection.hasSupportedKeyCode {
            copy.reopenFinderSelection = Shortcuts.default.reopenFinderSelection
            onRepair()
        }
        if !copy.openScratchpad.hasSupportedKeyCode {
            copy.openScratchpad = Shortcuts.default.openScratchpad
            onRepair()
        }
        if !copy.toggleRecording.hasSupportedKeyCode {
            copy.toggleRecording = Shortcuts.default.toggleRecording
            onRepair()
        }
        return copy
    }

    mutating func replaceRetiredDefaultShortcutsIfNeeded() {
        let retiredArea = Shortcut(
            keyCode: UInt32(kVK_ANSI_4),
            modifierFlags: UInt32(controlKey | shiftKey)
        )
        let retiredFull = Shortcut(
            keyCode: UInt32(kVK_ANSI_3),
            modifierFlags: UInt32(controlKey | shiftKey)
        )
        let retiredReopenFinderSelection = Shortcut(
            keyCode: UInt32(kVK_ANSI_2),
            modifierFlags: UInt32(controlKey | shiftKey)
        )
        let retiredCommandShiftArea = Shortcut(
            keyCode: UInt32(kVK_ANSI_4),
            modifierFlags: UInt32(cmdKey | shiftKey)
        )
        let retiredCommandShiftFull = Shortcut(
            keyCode: UInt32(kVK_ANSI_3),
            modifierFlags: UInt32(cmdKey | shiftKey)
        )
        let retiredCommandShiftReopenFinderSelection = Shortcut(
            keyCode: UInt32(kVK_ANSI_2),
            modifierFlags: UInt32(cmdKey | shiftKey)
        )
        let retiredOpenScratchpad = Shortcut(
            keyCode: UInt32(kVK_ANSI_5),
            modifierFlags: UInt32(cmdKey | shiftKey)
        )
        let retiredOptionShiftScratchpad = Shortcut(
            keyCode: UInt32(kVK_ANSI_5),
            modifierFlags: UInt32(optionKey | shiftKey)
        )
        let temporaryOpenScratchpad = Shortcut(
            keyCode: UInt32(kVK_ANSI_N),
            modifierFlags: UInt32(controlKey | shiftKey)
        )

        if [retiredArea, retiredCommandShiftArea].contains(screenshotArea) {
            screenshotArea = Shortcuts.default.screenshotArea
        }
        if [retiredFull, retiredCommandShiftFull].contains(screenshotFull) {
            screenshotFull = Shortcuts.default.screenshotFull
        }
        if [retiredReopenFinderSelection, retiredCommandShiftReopenFinderSelection].contains(reopenFinderSelection) {
            reopenFinderSelection = Shortcuts.default.reopenFinderSelection
        }
        if [retiredOpenScratchpad, retiredOptionShiftScratchpad].contains(openScratchpad) {
            openScratchpad = Shortcuts.default.openScratchpad
        }
        if openScratchpad == temporaryOpenScratchpad {
            openScratchpad = Shortcuts.default.openScratchpad
        }
    }
}

extension Shortcuts {
    // Backward-compatible decoding: older settings files won't have the new key.
    private enum CodingKeys: String, CodingKey {
        case screenshotArea
        case screenshotFull
        case reopenFinderSelection
        case openScratchpad
        case toggleRecording
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.screenshotArea = try container.decodeIfPresent(Shortcut.self, forKey: .screenshotArea)
            ?? Shortcuts.default.screenshotArea
        self.screenshotFull = try container.decodeIfPresent(Shortcut.self, forKey: .screenshotFull)
            ?? Shortcuts.default.screenshotFull
        self.reopenFinderSelection = try container.decodeIfPresent(Shortcut.self, forKey: .reopenFinderSelection)
            ?? Shortcuts.default.reopenFinderSelection
        self.openScratchpad = try container.decodeIfPresent(Shortcut.self, forKey: .openScratchpad)
            ?? Shortcuts.default.openScratchpad
        self.toggleRecording = try container.decodeIfPresent(Shortcut.self, forKey: .toggleRecording)
            ?? Shortcuts.default.toggleRecording
    }
}

// MARK: - Screenshot Filename

/// Screenshots are always named "Screenshot_2024-01-30_14.23.45_2". The
/// counter is the logical value; collision suffixes are `ScreenshotService`'s.
enum ScreenshotFilename {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        return formatter
    }()

    static func make(date: Date, counter: Int) -> String {
        "Screenshot_\(formatter.string(from: date))_\(counter)"
    }
}

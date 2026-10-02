import AppKit
import Carbon

/// The note editor's keys: the screenshot editor's, plus highlighter and
/// eraser. The note editor only draws, so tool letters always pick tools and
/// letters without a tool do nothing. Command shortcuts follow the typed
/// character and single-letter tool keys follow the physical key, exactly as
/// in the screenshot editor.
enum InkNoteKeymap {
    enum Command: Equatable {
        case tool(InkNoteWindowController.Tool)
        case nextColor, clearInk, undo, redo
        case save, copyAndSave, close, backToNote
    }

    /// The screenshot editor's letters where the meaning is the same
    /// (W pen, D line, A arrow, R rectangle, E ellipse, F marker, Q color).
    static let toolKeys: [UInt16: Command] = [
        UInt16(kVK_ANSI_W): .tool(.pen),
        UInt16(kVK_ANSI_D): .tool(.line),
        UInt16(kVK_ANSI_A): .tool(.arrow),
        UInt16(kVK_ANSI_R): .tool(.rectangle),
        UInt16(kVK_ANSI_E): .tool(.ellipse),
        UInt16(kVK_ANSI_F): .tool(.marker),
        UInt16(kVK_ANSI_H): .tool(.highlighter),
        UInt16(kVK_ANSI_X): .tool(.eraser),
        UInt16(kVK_ANSI_Q): .nextColor
    ]

    static func command(keyCode: UInt16, characters: String, flags rawFlags: NSEvent.ModifierFlags) -> Command? {
        let flags = rawFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let isReturn = keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter)
        if isReturn { return flags.contains(.command) ? .copyAndSave : (flags.isEmpty ? .save : nil) }
        if flags == [.command] { return characters.lowercased() == "z" ? .undo : nil }
        if flags == [.command, .shift] { return characters.lowercased() == "z" ? .redo : nil }
        if flags == [.option], keyCode == UInt16(kVK_Delete) { return .clearInk }
        if flags == [.shift], keyCode == UInt16(kVK_Tab) { return .backToNote }
        guard flags.isEmpty else { return nil }
        if keyCode == UInt16(kVK_Escape) { return .close }
        return toolKeys[keyCode]
    }
}

import AppKit
import Carbon

/// The note editor's keys, kept in step with the screenshot editor. Plain
/// letters pick tools only while drawing, because while typing they are text.
/// Command shortcuts follow the typed character and single-letter tool keys
/// follow the physical key, exactly as in the screenshot editor.
enum InkNoteKeymap {
    enum Command: Equatable {
        case selectAll, copy, cut, paste, undo, redo
        case save, copyAndSave, close
        case toggleDraw, type, escape
        case marker, nextColor, clearInk
        case tool(InkNoteWindowController.Tool)
    }

    /// Letters that act while drawing; the same letters as the screenshot
    /// editor where the meaning is the same (W pen, Q color, F marker, T text).
    static let drawingKeys: [UInt16: Command] = [
        UInt16(kVK_ANSI_W): .tool(.pen),
        UInt16(kVK_ANSI_H): .tool(.highlighter),
        UInt16(kVK_ANSI_X): .tool(.eraser),
        UInt16(kVK_ANSI_Q): .nextColor,
        UInt16(kVK_ANSI_F): .marker,
        UInt16(kVK_ANSI_T): .type
    ]

    private static let commandKeys: [String: Command] = [
        "a": .selectAll, "c": .copy, "x": .cut, "v": .paste, "z": .undo,
        "s": .save, "w": .close, "d": .toggleDraw, "f": .marker
    ]

    static func command(keyCode: UInt16, characters: String, flags rawFlags: NSEvent.ModifierFlags,
                        isDrawing: Bool) -> Command? {
        let flags = rawFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = characters.lowercased()
        // Return stays a newline; Command+Return copies and saves, as everywhere else.
        if flags.contains(.command), keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            return .copyAndSave
        }
        if flags == [.command] { return commandKeys[key] }
        if flags == [.command, .shift] { return key == "z" ? .redo : nil }
        // Option+Backspace deletes a word while typing and clears all ink while drawing.
        if flags == [.option], keyCode == UInt16(kVK_Delete) { return isDrawing ? .clearInk : nil }
        guard flags.isEmpty else { return nil }
        if keyCode == UInt16(kVK_Escape) { return .escape }
        return isDrawing ? drawingKeys[keyCode] : nil
    }
}

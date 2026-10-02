import AppKit
import Carbon

/// The note editor's keys. Command+T types and Command+D draws, from either
/// mode. While drawing, the keys are the screenshot editor's (plus
/// highlighter and eraser) and a letter without a tool does nothing; while
/// typing, letters, Return and Option+Backspace are text. Command shortcuts
/// follow the typed character and single-letter tool keys follow the
/// physical key, exactly as in the screenshot editor.
enum InkNoteKeymap {
    enum Command: Equatable {
        case type, draw
        case tool(InkNoteWindowController.Tool)
        case nextColor, clearInk, undo, redo, deleteSelection
        case selectAll, copy, cut, paste
        case save, copyAndSave, close, backToNote
    }

    /// The screenshot editor's letters where the meaning is the same
    /// (W pen, D line, A arrow, R rectangle, E ellipse, F marker, S select,
    /// Q color).
    static let toolKeys: [UInt16: Command] = [
        UInt16(kVK_ANSI_W): .tool(.pen),
        UInt16(kVK_ANSI_D): .tool(.line),
        UInt16(kVK_ANSI_A): .tool(.arrow),
        UInt16(kVK_ANSI_R): .tool(.rectangle),
        UInt16(kVK_ANSI_E): .tool(.ellipse),
        UInt16(kVK_ANSI_F): .tool(.marker),
        UInt16(kVK_ANSI_S): .tool(.select),
        UInt16(kVK_ANSI_H): .tool(.highlighter),
        UInt16(kVK_ANSI_X): .tool(.eraser),
        UInt16(kVK_ANSI_Q): .nextColor
    ]

    private static let commandKeys: [String: Command] = [
        "t": .type, "d": .draw, "z": .undo, "a": .selectAll, "c": .copy, "x": .cut, "v": .paste
    ]

    static func command(keyCode: UInt16, characters: String, flags rawFlags: NSEvent.ModifierFlags,
                        isDrawing: Bool) -> Command? {
        let flags = rawFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let isReturn = keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter)
        if isReturn, flags.contains(.command) { return .copyAndSave }
        if flags == [.command] { return commandKeys[characters.lowercased()] }
        if flags == [.command, .shift] { return characters.lowercased() == "z" ? .redo : nil }
        if flags == [.shift], keyCode == UInt16(kVK_Tab) { return .backToNote }
        // While typing, Esc leaves for drawing and everything else is text.
        guard isDrawing else { return flags.isEmpty && keyCode == UInt16(kVK_Escape) ? .draw : nil }
        if flags == [.option], keyCode == UInt16(kVK_Delete) { return .clearInk }
        guard flags.isEmpty else { return nil }
        if isReturn { return .save }
        if keyCode == UInt16(kVK_Escape) { return .close }
        if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) { return .deleteSelection }
        return toolKeys[keyCode]
    }
}

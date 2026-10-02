import Foundation

/// Keeps one "N: text" line per numbered marker in a block at the end of the
/// note, two blank lines below the typed text (or the whole note when nothing
/// was typed). Lines are found in the note text itself, so reopened files stay
/// in sync, and numbered lists elsewhere in the note are never touched.
enum MarkerNoteLogic {
    static func line(number: Int, text: String) -> String { "\(number): \(text)" }

    /// Text of marker `number`'s line in the marker block, if any.
    static func text(for number: Int, in note: String) -> String? {
        let lines = self.lines(of: note)
        guard let index = lineIndex(for: number, in: lines) else { return nil }
        return String(lines[index].dropFirst(line(number: number, text: "").count))
    }

    /// Returns the note after setting marker `number` to `newText`; empty text
    /// removes its line.
    static func update(note: String, number: Int, newText: String) -> String {
        var lines = self.lines(of: note)
        if let index = lineIndex(for: number, in: lines) {
            if newText.isEmpty {
                lines.remove(at: index)
            } else {
                lines[index] = line(number: number, text: newText)
            }
            return trimmingTrailingWhitespace(lines.joined(separator: "\n"))
        }
        guard !newText.isEmpty else { return note }
        let existing = trimmingTrailingWhitespace(note)
        guard !existing.isEmpty else { return line(number: number, text: newText) }
        let separator = markerBlock(in: lines).isEmpty ? "\n\n\n" : "\n"
        return existing + separator + line(number: number, text: newText)
    }

    /// Drops marker block lines whose marker no longer exists on the canvas.
    static func removingLines(notIn numbers: Set<Int>, from note: String) -> String {
        var lines = self.lines(of: note)
        let block = markerBlock(in: lines)
        let stale = block.filter { markerNumber(of: lines[$0]).map { !numbers.contains($0) } ?? false }
        guard !stale.isEmpty else { return note }
        for index in stale.reversed() { lines.remove(at: index) }
        return trimmingTrailingWhitespace(lines.joined(separator: "\n"))
    }

    /// Characters available for marker `number`'s text within `limit`.
    static func capacity(note: String, number: Int, limit: Int) -> Int {
        let used: Int
        if let old = text(for: number, in: note) {
            used = trimmingTrailingWhitespace(note).count - old.count
        } else {
            used = update(note: note, number: number, newText: "x").count - 1
        }
        return max(0, limit - used)
    }

    /// The typed text and the marker block, apart. Notes show the text on
    /// the page and the marker lines in the Note box.
    static func split(_ note: String) -> (text: String, markerLines: String) {
        let lines = self.lines(of: note)
        let block = markerBlock(in: lines)
        guard !block.isEmpty else { return (trimmingTrailingWhitespace(note), "") }
        return (trimmingTrailingWhitespace(lines[..<block.lowerBound].joined(separator: "\n")),
                lines[block].joined(separator: "\n"))
    }

    /// Pasted line breaks would split the marker's line; flatten them.
    static func sanitized(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Marker block

    private static func lines(of note: String) -> [String] {
        let trimmed = trimmingTrailingWhitespace(note)
        return trimmed.isEmpty ? [] : trimmed.components(separatedBy: "\n")
    }

    /// Trailing run of "N: " lines that starts the note or sits below two blank lines.
    private static func markerBlock(in lines: [String]) -> Range<Int> {
        var start = lines.count
        while start > 0, markerNumber(of: lines[start - 1]) != nil { start -= 1 }
        guard start < lines.count else { return lines.count..<lines.count }
        if start == 0 { return 0..<lines.count }
        if start >= 2, lines[start - 1].isEmpty, lines[start - 2].isEmpty { return start..<lines.count }
        return lines.count..<lines.count
    }

    private static func lineIndex(for number: Int, in lines: [String]) -> Int? {
        markerBlock(in: lines).last { markerNumber(of: lines[$0]) == number }
    }

    private static func markerNumber(of line: String) -> Int? {
        guard let colon = line.range(of: ": ") else { return nil }
        let digits = line[line.startIndex..<colon.lowerBound]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        var result = text
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }
}

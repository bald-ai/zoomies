import Foundation

/// Portable footnote storage. Only a separated, trailing block of numeric
/// definitions belongs to the editor; definitions elsewhere are ordinary text.
enum MarkdownMarkerLogic {
    private static let anchorRegex = try! NSRegularExpression(pattern: #"\[\^([0-9]+)\]"#)
    private static let definitionRegex = try! NSRegularExpression(pattern: #"^\[\^([0-9]+)\]:[ \t]?(.*)$"#)
    static let maximumFileSize = 1_048_576

    struct Document {
        var mainText: String
        var notes: [Int: String]
        let newline: String
        let endsWithNewline: Bool
        let originalText: String
        let originalMainText: String
    }

    struct Anchor: Equatable {
        let number: Int
        let range: NSRange
    }

    static func read(_ text: String) -> Document {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let ends = text.utf8.last == 10
        var lines = text.components(separatedBy: newline)
        var end = lines.count
        while end > 0, lines[end - 1].isEmpty { end -= 1 }
        var start = end
        while start > 0, lines[start - 1].isEmpty || definition(lines[start - 1]) != nil { start -= 1 }
        var notes: [Int: String] = [:]
        // A block at the beginning is valid too (orphan-only documents).
        let separated = start == 0 || (start < end && lines[start].isEmpty)
        if separated, start < end {
            for line in lines[start..<end] {
                if let (number, note) = definition(line) { notes[number] = note }
            }
            if !notes.isEmpty { lines.removeSubrange(start...) }
        }
        let main = notes.isEmpty ? text : lines.joined(separator: newline)
        return Document(mainText: main, notes: notes, newline: newline,
                        endsWithNewline: ends, originalText: text, originalMainText: main)
    }

    static func write(_ document: Document, mainText: String, notes: [Int: String]) -> String {
        // With no markers, preserve even mixed line endings and trailing whitespace.
        if notes.isEmpty, anchors(in: mainText).isEmpty,
           mainText == document.originalMainText, document.notes.isEmpty {
            return document.originalText
        }
        var text = mainText
        if !notes.isEmpty {
            while text.hasSuffix("\n") || text.hasSuffix("\r") || text.hasSuffix("\r\n") { text.removeLast() }
            if !text.isEmpty { text += document.newline + document.newline }
            text += notes.keys.sorted().map { "[^\($0)]: \(notes[$0] ?? "")" }.joined(separator: document.newline)
        }
        if document.endsWithNewline {
            if text.utf8.last != 10 { text += document.newline }
        } else {
            while text.hasSuffix("\n") || text.hasSuffix("\r") || text.hasSuffix("\r\n") { text.removeLast() }
        }
        return text
    }

    static func anchors(in text: String) -> [Anchor] {
        let ns = text as NSString
        return anchorRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let number = Int(ns.substring(with: match.range(at: 1))), number > 0 else { return nil }
            // Entire numeric definition lines in the body remain editable text.
            let line = ns.substring(with: ns.lineRange(for: match.range)).trimmingCharacters(in: .newlines)
            guard definition(line) == nil else { return nil }
            return Anchor(number: number, range: match.range)
        }
    }

    static func pastedAnchors(in text: String, notes: [Int: String], anchored: Set<Int>) -> [Anchor] {
        var used = anchored
        return anchors(in: text).filter { anchor in
            guard notes[anchor.number] != nil, !used.contains(anchor.number) else { return false }
            used.insert(anchor.number)
            return true
        }
    }

    static func nextNumber(notes: [Int: String], anchored: Set<Int>) -> Int? {
        let highest = max(notes.keys.max() ?? 0, anchored.max() ?? 0)
        return highest < Int.max ? highest + 1 : nil
    }

    private static func definition(_ line: String) -> (Int, String)? {
        let ns = line as NSString
        guard let match = definitionRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let number = Int(ns.substring(with: match.range(at: 1))), number > 0 else { return nil }
        return (number, ns.substring(with: match.range(at: 2)))
    }
}

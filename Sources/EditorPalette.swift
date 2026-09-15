import AppKit

struct EditorPaletteColor {
    let id: String
    let name: String
    let hex: String
    var color: NSColor { NSColor(hex: hex) }
}

enum EditorPalette {
    static let maximumCount = 6
    static let defaultIDs = ["red", "blue", "green", "black", "yellow", "white"]
    static let available: [EditorPaletteColor] = [
        .init(id: "red", name: "Red", hex: "#ff3b30"),
        .init(id: "orange", name: "Orange", hex: "#ff9500"),
        .init(id: "yellow", name: "Yellow", hex: "#ffcc00"),
        .init(id: "lime", name: "Lime", hex: "#b4e83a"),
        .init(id: "green", name: "Green", hex: "#34c759"),
        .init(id: "teal", name: "Teal", hex: "#30b0a8"),
        .init(id: "cyan", name: "Cyan", hex: "#32d7ee"),
        .init(id: "blue", name: "Blue", hex: "#007aff"),
        .init(id: "indigo", name: "Indigo", hex: "#5856d6"),
        .init(id: "purple", name: "Purple", hex: "#af52de"),
        .init(id: "pink", name: "Pink", hex: "#ff2d85"),
        .init(id: "brown", name: "Brown", hex: "#a2845e"),
        .init(id: "gray", name: "Gray", hex: "#8e8e93"),
        .init(id: "black", name: "Black", hex: "#000000"),
        .init(id: "white", name: "White", hex: "#ffffff")
    ]

    static func normalized(_ ids: [String]) -> [String] {
        let valid = Set(available.map(\.id))
        var result: [String] = []
        for id in ids where valid.contains(id) && !result.contains(id) {
            result.append(id)
            if result.count == maximumCount { break }
        }
        return result.isEmpty ? defaultIDs : result
    }

    static func colors(for ids: [String]) -> [EditorPaletteColor] {
        normalized(ids).compactMap { id in available.first { $0.id == id } }
    }
}

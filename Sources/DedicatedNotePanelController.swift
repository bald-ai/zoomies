import AppKit

/// The note flow's text window: a roomier version of the screenshot note
/// panel. Its text is what the editor shows in the Note box.
final class DedicatedNotePanelController: NotePanelController {
    static let layout = NotePanelLayout(
        size: NSSize(width: 410, height: 180),
        hasVerticalScroller: true,
        autohidesScrollers: false,
        scrollerStyle: .legacy,
        minimumTextHeight: 105,
        fillsAvailableHeight: true
    )

    init(initialText: String) {
        super.init(initialText: initialText,
                   escapeKeyDeletesFile: false,
                   showsCopyAndDelete: false,
                   showsNewlineShortcut: true,
                   maxLength: InkNoteDocument.maximumNoteLength,
                   layout: Self.layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

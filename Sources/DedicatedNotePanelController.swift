import AppKit

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
                   showsEditorShortcut: false,
                   showsNewlineShortcut: true,
                   maxLength: Self.standaloneMaxLength,
                   layout: Self.layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

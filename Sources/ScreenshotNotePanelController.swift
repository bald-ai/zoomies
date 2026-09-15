import AppKit

final class ScreenshotNotePanelController: NotePanelController {
    static let layout = NotePanelLayout(
        size: NSSize(width: 410, height: 120),
        hasVerticalScroller: true,
        autohidesScrollers: false,
        scrollerStyle: nil,
        minimumTextHeight: 60,
        fillsAvailableHeight: false
    )

    init(initialText: String, escapeKeyDeletesFile: Bool = true) {
        super.init(initialText: initialText,
                   escapeKeyDeletesFile: escapeKeyDeletesFile,
                   maxLength: 1000,
                   layout: Self.layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

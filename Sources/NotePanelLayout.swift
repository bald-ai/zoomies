import AppKit

struct NotePanelLayout {
    let size: NSSize
    let hasVerticalScroller: Bool
    let autohidesScrollers: Bool
    let scrollerStyle: NSScroller.Style?
    let minimumTextHeight: CGFloat
    let fillsAvailableHeight: Bool
}

import AppKit

struct EditorWindowLayoutInput {
    let imagePointSize: NSSize
    let maxContentSize: NSSize
    let minContentSize: NSSize
    let chromeSize: NSSize
    let autoZoomFillRatio: CGFloat
    let maxAutoUserZoom: CGFloat
}

struct EditorWindowLayoutResult {
    let totalPadding: CGFloat
    let fitScale: CGFloat
    let contentSize: NSSize
    let defaultUserZoomFactor: CGFloat
}

enum EditorWindowLayoutLogic {
    static let fallbackMaxContentSize = NSSize(width: 1400.0, height: 900.0)
    static let visibleFrameUsageRatio: CGFloat = 0.90
    /// Blank canvas kept around the image (total, both sides), even for
    /// full-screen captures, so arrows can be drawn in from outside it.
    static let imagePadding: CGFloat = 64.0

    static func maximumContentSize(visibleFrame: NSRect?,
                                   minContentSize: NSSize,
                                   fallback: NSSize = fallbackMaxContentSize) -> NSSize {
        guard let visibleFrame else {
            return NSSize(width: max(minContentSize.width, fallback.width),
                          height: max(minContentSize.height, fallback.height))
        }

        let width = floor(visibleFrame.width * visibleFrameUsageRatio)
        let height = floor(visibleFrame.height * visibleFrameUsageRatio)
        return NSSize(width: max(minContentSize.width, width),
                      height: max(minContentSize.height, height))
    }

    /// Window frame after the editor chrome above or below the canvas changes
    /// height by `heightDelta`, so the canvas keeps its size. The top edge stays
    /// put; growth never exceeds the visible frame, and a window pushed below it
    /// moves up instead.
    static func frameAdjustedForChromeChange(_ frame: NSRect,
                                             heightDelta: CGFloat,
                                             minHeight: CGFloat,
                                             visibleFrame: NSRect?) -> NSRect {
        var height = max(frame.height + heightDelta, minHeight)
        var originY = frame.maxY - height
        if let visibleFrame {
            height = min(height, max(visibleFrame.height, frame.height))
            originY = frame.maxY - height
            if originY < visibleFrame.minY {
                originY = min(visibleFrame.minY, visibleFrame.maxY - height)
            }
        }
        return NSRect(x: frame.minX, y: originY, width: frame.width, height: height)
    }

    static let noteBarMaxHeightRatio: CGFloat = 0.25
    static let noteBarMinimumMaxHeight: CGFloat = 80.0

    /// Tallest the editor note bar may grow before it scrolls: a quarter of
    /// the editor's maximum height, never less than a few lines.
    static func noteBarMaxHeight(maxContentHeight: CGFloat) -> CGFloat {
        max(noteBarMinimumMaxHeight, floor(maxContentHeight * noteBarMaxHeightRatio))
    }

    /// Zoom after the canvas changes from `openingViewportSize` to
    /// `viewportSize`: the image keeps its opening zoom while the canvas is at
    /// least as large as at opening, and shrinks with the canvas otherwise, so
    /// it never loses the margin it opened with (small captures open
    /// auto-zoomed with less than the usual padding).
    static func refittedZoom(viewportSize: NSSize, openingViewportSize: NSSize, openingZoom: CGFloat) -> CGFloat {
        guard openingViewportSize.width > 0, openingViewportSize.height > 0 else { return openingZoom }
        let shrink = min(1, viewportSize.width / openingViewportSize.width,
                         viewportSize.height / openingViewportSize.height)
        return openingZoom * max(shrink, 0)
    }

    static func makeLayout(_ input: EditorWindowLayoutInput) -> EditorWindowLayoutResult {
        let totalPadding = imagePadding

        let availableWidth = max(input.maxContentSize.width - input.chromeSize.width - totalPadding, 1.0)
        let availableHeight = max(input.maxContentSize.height - input.chromeSize.height - totalPadding, 1.0)

        var fitScale: CGFloat
        if input.imagePointSize.width <= availableWidth && input.imagePointSize.height <= availableHeight {
            fitScale = 1.0
        } else {
            fitScale = min(availableWidth / input.imagePointSize.width,
                           availableHeight / input.imagePointSize.height)
        }
        if !fitScale.isFinite || fitScale <= 0 {
            fitScale = 1.0
        }

        let contentWidth = min(max(input.imagePointSize.width * fitScale + totalPadding + input.chromeSize.width,
                                   input.minContentSize.width),
                               input.maxContentSize.width)
        let contentHeight = min(max(input.imagePointSize.height * fitScale + totalPadding + input.chromeSize.height,
                                    input.minContentSize.height),
                                input.maxContentSize.height)
        let contentSize = NSSize(width: contentWidth, height: contentHeight)

        let defaultUserZoomFactor = automaticZoom(input, contentSize: contentSize,
                                                   fitScale: fitScale, padding: totalPadding)
        return EditorWindowLayoutResult(totalPadding: totalPadding,
                                        fitScale: fitScale,
                                        contentSize: contentSize,
                                        defaultUserZoomFactor: defaultUserZoomFactor)
    }

    private static func automaticZoom(_ input: EditorWindowLayoutInput, contentSize: NSSize,
                                       fitScale: CGFloat, padding: CGFloat) -> CGFloat {
        let imageWidth = input.imagePointSize.width * fitScale
        let imageHeight = input.imagePointSize.height * fitScale
        let canvasWidth = contentSize.width - input.chromeSize.width
        let canvasHeight = contentSize.height - input.chromeSize.height
        let hasExtraSlack = canvasWidth > imageWidth + padding + 1 || canvasHeight > imageHeight + padding + 1
        guard hasExtraSlack, canvasWidth > 0, canvasHeight > 0, imageWidth > 0, imageHeight > 0 else { return 1 }
        let candidate = min(canvasWidth * input.autoZoomFillRatio / imageWidth,
                            canvasHeight * input.autoZoomFillRatio / imageHeight)
        return candidate.isFinite ? max(1, min(input.maxAutoUserZoom, candidate)) : 1
    }
}

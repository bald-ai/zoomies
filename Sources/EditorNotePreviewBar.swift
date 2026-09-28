import AppKit

/// UI-only note bar under the editor canvas. It grows with its text up to
/// `maxHeight`, then scrolls so a long note cannot crowd out the image.
final class EditorNotePreviewBar: NSView {
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 10

    var maxHeight: CGFloat {
        didSet { if maxHeight != oldValue { needsLayout = true } }
    }

    var text: String {
        get { textView.string }
        set {
            guard newValue != textView.string else { return }
            textView.string = newValue
            needsLayout = true
        }
    }

    private let scrollView = NSTextView.scrollableTextView()
    private let textView: NSTextView
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    init(text: String, maxHeight: CGFloat) {
        self.maxHeight = maxHeight
        textView = scrollView.documentView as! NSTextView
        super.init(frame: .zero)

        textView.isEditable = false
        // Not selectable: the canvas keeps keyboard focus for its shortcuts.
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        let padding = textView.textContainer?.lineFragmentPadding ?? 0
        textView.textContainerInset = NSSize(width: Self.horizontalInset - padding, height: Self.verticalInset)
        textView.string = text

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Height the full text needs at `width`, including insets.
    func textHeight(forWidth width: CGFloat) -> CGFloat {
        let inset = textView.textContainerInset
        let container = NSTextContainer(size: NSSize(width: max(width - inset.width * 2, 1),
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage(attributedString: textView.attributedString())
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height) + inset.height * 2
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        min(textHeight(forWidth: width), maxHeight)
    }

    func updateHeight(forWidth width: CGFloat) {
        let height = preferredHeight(forWidth: width)
        if abs(heightConstraint.constant - height) > 0.5 {
            heightConstraint.constant = height
        }
    }

    override func layout() {
        super.layout()
        // Rewrap after window-width changes.
        updateHeight(forWidth: bounds.width)
    }
}

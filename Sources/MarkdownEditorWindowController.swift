import AppKit

final class MarkdownMarkerAttachment: NSTextAttachment {
    let number: Int
    let token: String

    init(number: Int, token: String? = nil) {
        self.number = number
        self.token = token ?? "[^\(number)]"
        super.init(data: nil, ofType: nil)
        attachmentCell = MarkdownMarkerCell(number: number)
    }

    required init?(coder: NSCoder) { nil }
}

private final class MarkdownMarkerCell: NSTextAttachmentCell {
    let number: Int
    private let diameter: CGFloat = 21
    init(number: Int) {
        self.number = number
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("Not archived") }

    private var marker: EditorDrawing.MarkerItem {
        .init(number: number, center: .zero, color: EditorPalette.available[0].color, diameter: diameter)
    }
    override func cellSize() -> NSSize {
        let bounds = EditorImageRenderer.markerBounds(for: marker)
        return NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -7) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        var item = marker
        item.center = NSPoint(x: cellFrame.midX, y: cellFrame.midY)
        EditorImageRenderer.drawMarker(item)
    }
}

/// All external transfers use Markdown text, never attributed attachment data.
final class MarkdownTextView: NSTextView {
    var onInsertMarker: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onEditMarker: ((Int, NSRange) -> Void)?
    var convertPaste: ((String) -> NSAttributedString)?
    var retainingCutNotes = false
    let history = UndoManager()
    override var undoManager: UndoManager? { nil }

    static func plainText(_ text: NSAttributedString) -> String {
        let result = NSMutableAttributedString(attributedString: text)
        var markers: [(NSRange, String)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let marker = value as? MarkdownMarkerAttachment { markers.append((range, marker.token)) }
        }
        for (range, token) in markers.reversed() { result.replaceCharacters(in: range, with: token) }
        return result.string
    }

    func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "z", flags == [.command, .shift] { history.redo(); return true }
        guard flags == [.command] else { return false }
        switch key {
        case "a": selectAll(nil)
        case "c": copy(nil)
        case "x": cut(nil)
        case "v": paste(nil)
        case "z": history.undo()
        case "f": onInsertMarker?()
        case "s": onSave?()
        case "w": onClose?()
        default: return false
        }
        return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleShortcut(event) || super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if handleShortcut(event) { return }
        if event.keyCode == 53 { onClose?(); return }
        super.keyDown(with: event)
    }
    override func copy(_ sender: Any?) {
        _ = writeSelection(to: .general, type: .string)
    }
    override func cut(_ sender: Any?) {
        copy(sender)
        // Cut leaves an orphan note so a subsequent plain-text paste can reconnect it.
        retainingCutNotes = true
        replaceSelection(with: NSAttributedString(string: ""))
        retainingCutNotes = false
    }
    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        replaceSelection(with: convertPaste?(text) ?? NSAttributedString(string: text, attributes: typingAttributes))
    }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, selectedRange().length > 0 else { return false }
        let selected = attributedString().attributedSubstring(from: selectedRange())
        pboard.clearContents()
        return pboard.setString(Self.plainText(selected), forType: .string)
    }
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let text = pboard.string(forType: .string) else { return false }
        replaceSelection(with: convertPaste?(text) ?? NSAttributedString(string: text, attributes: typingAttributes))
        return true
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? NSAttributedString)?.string ?? (insertString as? String ?? "")
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        replace(range: range, with: NSAttributedString(string: text, attributes: typingAttributes))
    }
    func replaceSelection(with text: NSAttributedString) { replace(range: selectedRange(), with: text) }
    func replace(range: NSRange, with text: NSAttributedString) {
        guard shouldChangeText(in: range, replacementString: text.string) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        setSelectedRange(NSRange(location: range.location + text.length, length: 0))
        didChangeText()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2, let manager = layoutManager, let container = textContainer {
            let point = convert(event.locationInWindow, from: nil)
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            var fraction: CGFloat = 0
            let index = manager.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
            if index < (textStorage?.length ?? 0),
               let attachment = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? MarkdownMarkerAttachment {
                onEditMarker?(attachment.number, NSRange(location: index, length: 1))
                return
            }
        }
        super.mouseDown(with: event)
    }
}

@MainActor
final class MarkdownEditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSPopoverDelegate {
    let url: URL
    let textView = MarkdownTextView(frame: .zero)
    private(set) var notes: [Int: String] = [:]
    var onClose: (() -> Void)?
    private var markerDocument: MarkdownMarkerLogic.Document
    private var diskBytes: Data
    private var savedMainText: String = ""
    private var savedNotes: [Int: String] = [:]
    private let notesTable = NSTableView()
    private let notesScroll = NSScrollView()
    private var notesHeight: NSLayoutConstraint!
    private var popover: NSPopover?
    private var editingNumber: Int?
    private var newMarkerSnapshot: Snapshot?
    private var pendingSnapshot: Snapshot?
    private var restoring = false
    /// Notes plus anchors without a definition; the latter show as empty rows
    /// but are never written back as empty definitions.
    private var sortedNumbers: [Int] { Set(notes.keys).union(anchorNumbers).sorted() }

    fileprivate struct Snapshot {
        let text: NSAttributedString
        let notes: [Int: String]
        let selection: NSRange
    }

    init(url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url)
        guard data.count <= MarkdownMarkerLogic.maximumFileSize, let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MarkdownEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Markdown must be valid UTF-8 and no larger than 1 MB."])
        }
        diskBytes = data
        markerDocument = MarkdownMarkerLogic.read(string)
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: 320)
        window.delegate = self
        window.representedURL = url
        window.center()
        buildEditor()
        loadDocument()
        window.keyEquivalentInterceptor = { [weak self] event in
            guard let self else { return false }
            if self.popover != nil {
                if event.keyCode == 53 { self.cancelPopover(); return true }
                let field = self.popover?.contentViewController?.view.subviews.first as? MarkerNoteField
                return field?.handleEditingShortcut(event) ?? false
            }
            return self.textView.handleShortcut(event)
        }
    }
    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
    }

    private func buildEditor() {
        guard let content = window?.contentView else { return }
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 820, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 20, height: 18)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.history.groupsByEvent = false
        textView.history.levelsOfUndo = 100
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.delegate = self
        textView.onInsertMarker = { [weak self] in self?.insertMarker() }
        textView.onSave = { [weak self] in _ = self?.save() }
        textView.onClose = { [weak self] in self?.window?.performClose(nil) }
        textView.onEditMarker = { [weak self] number, range in self?.editMarker(number, range: range) }
        textView.convertPaste = { [weak self] string in
            guard let self else { return NSAttributedString(string: string) }
            let selection = self.textView.selectedRange()
            let remaining = Set(self.markerRanges().filter { NSIntersectionRange($0.range, selection).length == 0 }.map { $0.number })
            return self.attributedText(string, anchors: MarkdownMarkerLogic.pastedAnchors(in: string, notes: self.notes, anchored: remaining))
        }
        scroll.documentView = textView
        content.addSubview(scroll)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("notes"))
        notesTable.addTableColumn(column)
        notesTable.headerView = nil
        notesTable.rowHeight = 26
        notesTable.dataSource = self
        notesTable.delegate = self
        notesTable.target = self
        notesTable.action = #selector(noteClicked)
        notesScroll.translatesAutoresizingMaskIntoConstraints = false
        notesScroll.documentView = notesTable
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .bezelBorder
        content.addSubview(notesScroll)
        notesHeight = notesScroll.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: notesScroll.topAnchor),
            notesScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            notesScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            notesScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor), notesHeight
        ])
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.textColor]
    }
    private func attributedText(_ string: String, anchors: [MarkdownMarkerLogic.Anchor]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: string, attributes: baseAttributes)
        for anchor in anchors.reversed() {
            let attachment = NSMutableAttributedString(attachment: MarkdownMarkerAttachment(number: anchor.number, token: (string as NSString).substring(with: anchor.range)))
            attachment.addAttributes(baseAttributes, range: NSRange(location: 0, length: attachment.length))
            result.replaceCharacters(in: anchor.range, with: attachment)
        }
        return result
    }
    private func loadDocument() {
        restoring = true
        notes = markerDocument.notes
        let anchors = MarkdownMarkerLogic.anchors(in: markerDocument.mainText)
        textView.textStorage?.setAttributedString(attributedText(markerDocument.mainText, anchors: anchors))
        textView.typingAttributes = baseAttributes
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.history.removeAllActions()
        savedMainText = mainText
        savedNotes = notes
        restoring = false
        refresh()
    }
    var mainText: String { MarkdownTextView.plainText(textView.attributedString()) }
    var hasUnsavedChanges: Bool { mainText != savedMainText || notes != savedNotes }
    var anchorNumbers: Set<Int> { Set(markerRanges().map { $0.number }) }
    private func markerRanges() -> [(number: Int, range: NSRange)] {
        var result: [(Int, NSRange)] = []
        let text = textView.attributedString()
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let attachment = value as? MarkdownMarkerAttachment { result.append((attachment.number, range)) }
        }
        return result
    }
    private func snapshot() -> Snapshot {
        Snapshot(text: NSAttributedString(attributedString: textView.attributedString()), notes: notes, selection: textView.selectedRange())
    }
    private func record(_ old: Snapshot) {
        let grouping = textView.history.groupingLevel == 0
        if grouping { textView.history.beginUndoGrouping() }
        textView.history.registerUndo(withTarget: self) { target in target.restore(old) }
        if grouping { textView.history.endUndoGrouping() }
    }
    private func restore(_ old: Snapshot) {
        record(snapshot())
        restoring = true
        textView.textStorage?.setAttributedString(old.text)
        notes = old.notes
        textView.setSelectedRange(old.selection)
        textView.typingAttributes = baseAttributes
        restoring = false
        refresh()
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if !restoring { pendingSnapshot = snapshot() }
        return true
    }
    func textDidChange(_ notification: Notification) {
        guard !restoring, let old = pendingSnapshot else { return }
        pendingSnapshot = nil
        let before = Set(old.textMarkers)
        let removed = before.subtracting(anchorNumbers)
        if !textView.retainingCutNotes { for number in removed { notes[number] = nil } }
        record(old)
        textView.typingAttributes = baseAttributes
        refresh()
    }
    private func refresh() {
        window?.title = url.lastPathComponent + (hasUnsavedChanges ? " •" : "")
        window?.isDocumentEdited = hasUnsavedChanges
        notesTable.reloadData()
        resizeNotes()
    }
    private func resizeNotes() {
        let rows = sortedNumbers.count
        notesHeight.constant = min(CGFloat(rows) * 26 + (rows == 0 ? 0 : 4), (window?.contentView?.bounds.height ?? 660) * 0.25)
    }
    func windowDidResize(_ notification: Notification) { resizeNotes() }
    func numberOfRows(in tableView: NSTableView) -> Int { sortedNumbers.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let number = sortedNumbers[row]
        let suffix = anchorNumbers.contains(number) ? "" : "  (no anchor)"
        let field = NSTextField(labelWithString: "\(number): \(notes[number] ?? "")\(suffix)")
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = field.stringValue
        return field
    }
    @objc private func noteClicked() {
        let row = notesTable.clickedRow
        guard sortedNumbers.indices.contains(row) else { return }
        let number = sortedNumbers[row]
        if let marker = markerRanges().first(where: { $0.number == number }) {
            textView.scrollRangeToVisible(marker.range)
            editMarker(number, range: marker.range)
        } else {
            showPopover(number: number, rect: notesTable.rect(ofRow: row), view: notesTable)
        }
    }
    func insertMarker() {
        cancelPopover()
        guard let number = MarkdownMarkerLogic.nextNumber(notes: notes, anchored: anchorNumbers) else { NSSound.beep(); return }
        newMarkerSnapshot = snapshot()
        restoring = true
        let position = NSMaxRange(textView.selectedRange())
        textView.textStorage?.insert(attributedText("[^\(number)]", anchors: [.init(number: number, range: NSRange(location: 0, length: "[^\(number)]".utf16.count))]), at: position)
        notes[number] = ""
        textView.setSelectedRange(NSRange(location: position + 1, length: 0))
        restoring = false
        refresh()
        textView.scrollRangeToVisible(NSRange(location: position, length: 1))
        editMarker(number, range: NSRange(location: position, length: 1))
    }
    private func editMarker(_ number: Int, range: NSRange) {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        showPopover(number: number, rect: rect, view: textView)
    }
    private func showPopover(number: Int, rect: NSRect, view: NSView) {
        if popover != nil { cancelPopover() }
        editingNumber = number
        let field = MarkerNoteField(string: notes[number] ?? "")
        field.placeholderString = "Note for \(number)…"
        field.font = .systemFont(ofSize: 13)
        field.frame = NSRect(x: 10, y: 10, width: 300, height: 24)
        field.cell?.sendsActionOnEndEditing = false
        field.delegate = self
        field.target = self
        field.action = #selector(commitNote(_:))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        content.addSubview(field)
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = controller
        self.popover = popover
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeFirstResponder(field)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelPopover(); return true }
        return false
    }
    @objc private func commitNote(_ field: NSTextField) { commitMarkerNote(field.stringValue) }

    func commitMarkerNote(_ text: String) {
        guard let number = editingNumber else { return }
        let old = newMarkerSnapshot ?? snapshot()
        let value = MarkerNoteLogic.sanitized(text)
        restoring = true
        if value.isEmpty {
            for marker in markerRanges().reversed() where marker.number == number {
                textView.textStorage?.deleteCharacters(in: marker.range)
            }
            notes[number] = nil
            let length = textView.textStorage?.length ?? 0
            textView.setSelectedRange(NSRange(location: min(textView.selectedRange().location, length), length: 0))
        } else { notes[number] = value }
        restoring = false
        newMarkerSnapshot = nil
        editingNumber = nil
        let closing = popover
        popover = nil
        closing?.close()
        if MarkdownTextView.plainText(old.text) != mainText || old.notes != notes { record(old) }
        refresh()
        window?.makeFirstResponder(textView)
    }
    func cancelPopover() {
        editingNumber = nil
        let closing = popover
        popover = nil
        closing?.close()
        if let old = newMarkerSnapshot {
            newMarkerSnapshot = nil
            restoring = true
            textView.textStorage?.setAttributedString(old.text)
            notes = old.notes
            textView.setSelectedRange(old.selection)
            restoring = false
            refresh()
        }
        window?.makeFirstResponder(textView)
    }
    func popoverDidClose(_ notification: Notification) {
        if (notification.object as? NSPopover) === popover { cancelPopover() }
    }

    @discardableResult
    func save() -> Bool {
        do {
            // A missing file (moved or deleted elsewhere) is simply recreated.
            let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            if let current, current != diskBytes {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "File changed on disk"
                alert.informativeText = "Another app changed \(url.lastPathComponent). Overwrite it with your edits, reload its contents, or cancel."
                for button in ["Overwrite", "Reload", "Cancel"] { alert.addButton(withTitle: button) }
                switch AlertPresenter.runModal(alert) {
                case .alertFirstButtonReturn: break
                case .alertSecondButtonReturn:
                    guard current.count <= MarkdownMarkerLogic.maximumFileSize,
                          let string = String(data: current, encoding: .utf8) else {
                        throw NSError(domain: "MarkdownEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "The changed file must be valid UTF-8 and no larger than 1 MB."])
                    }
                    cancelPopover()
                    markerDocument = MarkdownMarkerLogic.read(string)
                    diskBytes = current
                    loadDocument()
                    return true
                default: return false
                }
            }
            let output = MarkdownMarkerLogic.write(markerDocument, mainText: mainText, notes: notes)
            let data = Data(output.utf8)
            try data.write(to: url, options: .atomic)
            diskBytes = data
            savedMainText = mainText
            savedNotes = notes
            refresh()
            return true
        } catch {
            AlertPresenter.presentWarning(title: "Cannot Save Markdown", message: error.localizedDescription)
            return false
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelPopover()
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(url.lastPathComponent)?"
        for button in ["Save", "Discard", "Cancel"] { alert.addButton(withTitle: button) }
        switch AlertPresenter.runModal(alert) {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

private extension MarkdownEditorWindowController.Snapshot {
    var textMarkers: [Int] {
        var result: [Int] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let marker = value as? MarkdownMarkerAttachment { result.append(marker.number) }
        }
        return result
    }
}

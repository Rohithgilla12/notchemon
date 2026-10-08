import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// On the `[ ]` of a task line; the value is whether it is ticked.
    static let notesCheckbox = NSAttributedString.Key("NotchemonNotesCheckbox")
    /// On markup laid out at zero width, off the caret's lines.
    static let notesHidden = NSAttributedString.Key("NotchemonNotesHidden")
}

struct MarkdownTheme {
    static let headingSizes: [CGFloat] = [22, 18, 15]
    // NSParagraphStyle is immutable; only the mutable subclass is unsafe to share.
    nonisolated(unsafe) static let bodyParagraph = paragraphStyle(spacingBefore: 0)
    nonisolated(unsafe) static let headingParagraph = paragraphStyle(spacingBefore: 8)

    var monospaced = false
    var size: CGFloat = 15

    var baseFont: NSFont {
        monospaced ? .monospacedSystemFont(ofSize: size - 1, weight: .regular) : .systemFont(ofSize: size)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: Self.bodyParagraph]
    }

    func headingFont(level: Int) -> NSFont {
        let headingSize = Self.headingSizes[min(level, Self.headingSizes.count) - 1]
        return monospaced
            ? .monospacedSystemFont(ofSize: headingSize, weight: .semibold)
            : .systemFont(ofSize: headingSize, weight: .semibold)
    }

    private static func paragraphStyle(spacingBefore: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.45
        paragraph.paragraphSpacing = 6
        paragraph.paragraphSpacingBefore = spacingBefore
        return paragraph
    }

    /// Restyles the whole lines `range` touches, and the line starting where it
    /// ends: typing Return mid-line edits only the newline, yet the text after
    /// it is now a new line. Markup on the `active` lines shows; elsewhere it
    /// hides. Only attributes change.
    func restyle(_ storage: NSTextStorage, range: NSRange, active: NSRange) {
        let text = storage.mutableString
        let after = NSRange(location: NSMaxRange(range), length: 0)
        let lines = NSUnionRange(text.lineRange(for: range), text.lineRange(for: after))
        storage.setAttributes(baseAttributes, range: lines)
        for span in MarkdownStyler.spans(in: text, range: lines) {
            apply(span, to: storage)
            if span.isHidden(outside: active) {
                storage.addAttribute(.notesHidden, value: true, range: span.range)
            }
        }
    }

    private func apply(_ span: MarkdownSpan, to storage: NSTextStorage) {
        let range = span.range
        switch span.kind {
        case .heading(let level):
            storage.addAttribute(.font, value: headingFont(level: level), range: range)
            // Paragraph styles are fixed per paragraph, so the newline must match.
            storage.addAttribute(.paragraphStyle, value: Self.headingParagraph, range: storage.mutableString.paragraphRange(for: range))
        case .bold:
            addTrait(.bold, to: storage, in: range)
        case .italic:
            addTrait(.italic, to: storage, in: range)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        // No background colour: a translucent one replaces the window
        // material's pixels instead of blending, leaving a see-through box.
        case .code:
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular),
                .foregroundColor: NSColor.systemPink,
            ], range: range)
        case .link(let address):
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            if let url = URL(string: address), url.scheme != nil {
                storage.addAttribute(.link, value: url, range: range)
            }
        case .syntax:
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: NotesPalette.accent.withAlphaComponent(0.7), range: range)
        case .checkbox(let checked):
            storage.addAttributes([
                .notesCheckbox: checked,
                .foregroundColor: NotesPalette.accent,
                .font: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .bold),
                .cursor: NSCursor.pointingHand,
            ], range: range)
        case .done:
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor,
            ], range: range)
        }
    }

    private func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            storage.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: run)
        }
    }
}

/// Restyles the lines each edit touched, never the whole note, and keeps the
/// markup showing only on the lines that hold the caret.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    var theme = MarkdownTheme()
    /// Where the caret lands once the pending edit applies. Nil for an edit
    /// away from the caret, such as loading a note or ticking a box.
    var caretAfterEdit: Int?
    /// Every line styled with its markup showing, in current offsets. It may
    /// cover more lines than that, never fewer.
    private(set) var shownLines: [NSRange] = []

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let length = textStorage.length
        shownLines = shownLines.compactMap { Self.shift($0, past: editedRange, delta: delta, length: length) }
        let active = caretAfterEdit.map { textStorage.mutableString.lineRange(for: NSRange(location: min($0, length), length: 0)) }
        caretAfterEdit = nil
        theme.restyle(textStorage, range: editedRange, active: active ?? NSRange(location: 0, length: 0))
        if let active, active.length > 0 { shownLines = shownLines.filter { $0 != active } + [active] }
    }

    /// Shows the markup on `active` alone, restyling only the lines that change.
    func show(_ active: NSRange, in storage: NSTextStorage) {
        let wanted = active.length > 0 ? [active] : []
        guard shownLines != wanted else { return }
        let stale = shownLines.filter { $0 != active }
        shownLines = wanted
        storage.beginEditing()
        for range in stale + wanted {
            theme.restyle(storage, range: range, active: active)
        }
        storage.endEditing()
    }

    func restyleAll(_ storage: NSTextStorage, active: NSRange) {
        storage.beginEditing()
        theme.restyle(storage, range: NSRange(location: 0, length: storage.length), active: active)
        storage.endEditing()
        shownLines = active.length > 0 ? [active] : []
    }

    /// Moves `range` past an edit that replaced `edited` (in new offsets) and
    /// changed the length by `delta`. A range the edit overlaps grows to cover it.
    static func shift(_ range: NSRange, past edited: NSRange, delta: Int, length: Int) -> NSRange? {
        var lower = range.location
        var upper = NSMaxRange(range)
        if upper <= edited.location {
            // Before the edit: unchanged.
        } else if lower >= NSMaxRange(edited) - delta {
            lower += delta
            upper += delta
        } else {
            lower = min(lower, edited.location)
            upper = max(upper + delta, NSMaxRange(edited))
        }
        lower = max(0, min(lower, length))
        upper = max(lower, min(upper, length))
        return upper > lower ? NSRange(location: lower, length: upper - lower) : nil
    }
}

final class NotesTextView: NSTextView {
    /// The editor as the window uses it, inside its scroll view.
    static func makeScrollable() -> (scrollView: NSScrollView, textView: NotesTextView) {
        let textView = NotesTextView(usingTextLayoutManager: false)
        let layoutManager = NotesLayoutManager()
        textView.textContainer?.replaceLayoutManager(layoutManager)
        textView.textStorage?.delegate = textView.highlighter
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = false
        textView.insertionPointColor = NotesPalette.accent
        textView.textContainerInset = NSSize(width: 28, height: 20)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        layoutManager.allowsNonContiguousLayout = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    let highlighter = MarkdownHighlighter()

    var activeLines: NSRange {
        guard let storage = textStorage else { return NSRange(location: 0, length: 0) }
        return MarkdownStyler.activeLines(for: selectedRanges.map(\.rangeValue), in: storage.mutableString)
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) else { return false }
        if let last = affectedRanges.last?.rangeValue {
            let inserted = replacementStrings?.last.map { ($0 as NSString).length } ?? 0
            highlighter.caretAfterEdit = last.location + inserted
        }
        return true
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Mid-drag, revealing markup would move the text under the pointer.
        if !stillSelecting { revealMarkup() }
    }

    /// Shows the markup on the caret's lines and hides it everywhere else.
    func revealMarkup() {
        guard let storage = textStorage, storage.delegate === highlighter, storage.editedMask.isEmpty else { return }
        highlighter.show(activeLines, in: storage)
    }

    func restyleAll() {
        guard let storage = textStorage else { return }
        highlighter.restyleAll(storage, active: activeLines)
    }

    // Pastes arrive as plain text; the Markdown styling is the only formatting.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    // NSTextView turns Esc into completion; here it hides the window.
    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if toggleCheckbox(at: convert(event.locationInWindow, from: nil)) { return }
        super.mouseDown(with: event)
    }

    /// Ticks or unticks the checkbox under `point`, as one undoable edit.
    @discardableResult
    func toggleCheckbox(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: inContainer, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.contains(inContainer) else { return false }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return false }
        return toggleCheckbox(atCharacter: index)
    }

    @discardableResult
    func toggleCheckbox(atCharacter index: Int) -> Bool {
        guard let storage = textStorage else { return false }
        var box = NSRange()
        let line = storage.mutableString.lineRange(for: NSRange(location: index, length: 0))
        guard let checked = storage.attribute(.notesCheckbox, at: index, longestEffectiveRange: &box, in: line) as? Bool else { return false }
        let mark = NSRange(location: box.location + 1, length: 1)
        let replacement = checked ? " " : "x"
        guard shouldChangeText(in: mark, replacementString: replacement) else { return true }
        let selection = selectedRanges
        highlighter.caretAfterEdit = nil
        storage.replaceCharacters(in: mark, with: replacement)
        selectedRanges = selection
        didChangeText()
        revealMarkup()
        return true
    }
}

/// Lets the window controller focus the editor, which SwiftUI creates.
@MainActor
final class NoteEditorHandle {
    weak var textView: NotesTextView?

    func focusAtEnd() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        let end = NSRange(location: textView.textStorage?.length ?? 0, length: 0)
        textView.setSelectedRange(end)
        textView.scrollRangeToVisible(end)
    }
}

struct NoteEditor: NSViewRepresentable {
    let session: NotesSession
    let handle: NoteEditorHandle
    var monospaced: Bool

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = NotesTextView.makeScrollable()
        textView.delegate = context.coordinator
        handle.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NotesTextView else { return }
        let coordinator = context.coordinator
        if textView.highlighter.theme.monospaced != monospaced {
            textView.highlighter.theme.monospaced = monospaced
            textView.typingAttributes = textView.highlighter.theme.baseAttributes
            textView.restyleAll()
        }
        if coordinator.revision != session.editorRevision {
            coordinator.revision = session.editorRevision
            coordinator.load(session.current, into: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: NotesSession
        var revision = -1
        private var noteID: UUID?

        init(session: NotesSession) {
            self.session = session
        }

        /// A different note opens with the cursor at its end; a reload of the
        /// same note keeps the cursor where it was. Either way the undo history
        /// goes with the old text, since its ranges no longer fit the new one.
        func load(_ note: Note?, into textView: NotesTextView) {
            let text = note?.body ?? ""
            let switched = note?.id != noteID
            noteID = note?.id
            if textView.string != text {
                let selection = textView.selectedRange()
                textView.typingAttributes = textView.highlighter.theme.baseAttributes
                textView.string = text
                textView.undoManager?.removeAllActions()
                let length = (text as NSString).length
                textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            }
            if switched {
                textView.undoManager?.removeAllActions()
                let end = NSRange(location: textView.textStorage?.length ?? 0, length: 0)
                textView.setSelectedRange(end)
                textView.scrollRangeToVisible(end)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            session.edit(textView.string)
        }
    }
}

import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// On the `[ ]` of a task line; the value is whether it is ticked.
    static let notesCheckbox = NSAttributedString.Key("NotchemonNotesCheckbox")
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
    /// it is now a new line. Only attributes change.
    func restyle(_ storage: NSTextStorage, range: NSRange) {
        let text = storage.mutableString
        let after = NSRange(location: NSMaxRange(range), length: 0)
        let lines = NSUnionRange(text.lineRange(for: range), text.lineRange(for: after))
        storage.setAttributes(baseAttributes, range: lines)
        for span in MarkdownStyler.spans(in: text, range: lines) {
            apply(span, to: storage)
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

/// Restyles the paragraphs each edit touched, never the whole note.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    var theme = MarkdownTheme()

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        theme.restyle(textStorage, range: editedRange)
    }

    func restyleAll(_ storage: NSTextStorage) {
        storage.beginEditing()
        theme.restyle(storage, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }
}

final class NotesTextView: NSTextView {
    /// The editor as the window uses it, inside its scroll view.
    static func makeScrollable() -> (scrollView: NSScrollView, textView: NotesTextView) {
        let textView = NotesTextView(usingTextLayoutManager: false)
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
        textView.layoutManager?.allowsNonContiguousLayout = true
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
        storage.replaceCharacters(in: mark, with: replacement)
        selectedRanges = selection
        didChangeText()
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
        textView.textStorage?.delegate = context.coordinator.highlighter
        handle.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NotesTextView else { return }
        let coordinator = context.coordinator
        if coordinator.highlighter.theme.monospaced != monospaced {
            coordinator.highlighter.theme.monospaced = monospaced
            textView.typingAttributes = coordinator.highlighter.theme.baseAttributes
            if let storage = textView.textStorage { coordinator.highlighter.restyleAll(storage) }
        }
        if coordinator.revision != session.editorRevision {
            coordinator.revision = session.editorRevision
            coordinator.load(session.current, into: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: NotesSession
        let highlighter = MarkdownHighlighter()
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
                textView.typingAttributes = highlighter.theme.baseAttributes
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

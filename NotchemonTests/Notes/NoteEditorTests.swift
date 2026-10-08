import AppKit
import Testing
@testable import Notchemon

/// A styled editor in a window that is never shown, which supplies the undo manager.
@MainActor
final class EditorHarness {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 460), styleMask: [.titled], backing: .buffered, defer: true)
    let textView: NotesTextView
    var highlighter: MarkdownHighlighter { textView.highlighter }
    var storage: NSTextStorage { textView.textStorage! }

    init(_ text: String) {
        let (scrollView, textView) = NotesTextView.makeScrollable()
        self.textView = textView
        window.contentView = scrollView
        textView.string = text
    }

    func type(_ text: String, at location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    func font(at location: Int) -> NSFont? {
        storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    /// The same text styled in one pass, with markup showing on the caret's
    /// lines, to compare piecewise restyling against.
    var styledFromScratch: NSAttributedString {
        let fresh = NSTextStorage(string: storage.string)
        highlighter.theme.restyle(fresh, range: NSRange(location: 0, length: fresh.length), active: textView.activeLines)
        return fresh
    }

    func moveCaret(to location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    /// Whether the character at `location` is laid out at zero width.
    func isHidden(at location: Int) -> Bool {
        let layoutManager = textView.layoutManager!
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        return layoutManager.propertyForGlyph(at: glyph) == .null
    }
}

@MainActor
struct NoteEditorTests {
    @Test func typingMarkupStylesTheWordAsYouGo() {
        let editor = EditorHarness("# Plan\nship it today\n")
        editor.type("**", at: 11)
        editor.type("**", at: 7)
        #expect(editor.storage.string == "# Plan\n**ship** it today\n")
        #expect(editor.font(at: 9)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(editor.font(at: 16)?.fontDescriptor.symbolicTraits.contains(.bold) == false)
    }

    @Test func restylingOnlyEditedParagraphsMatchesAFullRestyle() {
        let editor = EditorHarness("# Title\nplain\n- [ ] task\nsome `code` and *em*\n")
        editor.type("## ", at: 8)
        editor.type("x", at: 19)
        editor.type("\n**new** line", at: editor.storage.length - 1)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 2))
        editor.textView.insertText("", replacementRange: NSRange(location: 0, length: 2))
        #expect(editor.storage.isEqual(to: editor.styledFromScratch))
    }

    @Test(arguments: [
        ("# Hello world", 7),
        ("- [x] paid rent", 10),
        ("some **bold** text", 9),
    ])
    func splittingALineWithReturnRestylesBothHalves(text: String, at location: Int) {
        let editor = EditorHarness(text)
        editor.type("\n", at: location)
        #expect(editor.storage.isEqual(to: editor.styledFromScratch))
    }

    @Test func joiningTwoLinesRestylesTheResult() {
        let editor = EditorHarness("# Title\nplain")
        editor.textView.insertText("", replacementRange: NSRange(location: 7, length: 1))
        #expect(editor.storage.isEqual(to: editor.styledFromScratch))
    }

    @Test func markupHidesOffTheCaretLineAndShowsOnIt() {
        let editor = EditorHarness("# Plan\nship **it** today\n")
        editor.moveCaret(to: 0)
        #expect(editor.isHidden(at: 12))
        #expect(!editor.isHidden(at: 0))
        #expect(editor.storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .tertiaryLabelColor)
        editor.moveCaret(to: 9)
        #expect(editor.isHidden(at: 0))
        #expect(editor.isHidden(at: 1))
        #expect(!editor.isHidden(at: 12))
        #expect(!editor.isHidden(at: 2))
        #expect(editor.storage.isEqual(to: editor.styledFromScratch))
    }

    @Test func typingKeepsTheCaretLineMarkupShowing() {
        let editor = EditorHarness("**a** b\n**c**\n")
        editor.type("x", at: 11)
        #expect(!editor.isHidden(at: 8))
        #expect(editor.isHidden(at: 0))
        editor.type("\n", at: 6)
        #expect(editor.isHidden(at: 0))
        #expect(editor.isHidden(at: 9))
        #expect(editor.storage.isEqual(to: editor.styledFromScratch))
    }

    @Test(arguments: [
        (NSRange(location: 10, length: 5), 3, NSRange(location: 13, length: 5)),
        (NSRange(location: 0, length: 4), 2, NSRange(location: 0, length: 4)),
        (NSRange(location: 2, length: 4), 3, NSRange(location: 2, length: 7)),
        (NSRange(location: 5, length: 2), -2, NSRange(location: 4, length: 1)),
    ])
    func shownLinesMovePastEdits(range: NSRange, delta: Int, expected: NSRange) {
        let edited = delta >= 0 ? NSRange(location: 4, length: delta) : NSRange(location: 4, length: 0)
        #expect(MarkdownHighlighter.shift(range, past: edited, delta: delta, length: 100) == expected)
    }

    @Test func reloadingTheSameNoteDropsUndoForTheOldText() throws {
        let sandbox = try NotesSandbox()
        let session = NotesSession(store: sandbox.store, now: { october8 })
        _ = try sandbox.store.create("Plan\nv1", at: october8)
        session.load()
        let coordinator = NoteEditor.Coordinator(session: session)
        let editor = EditorHarness("")
        let note = try #require(session.current)
        coordinator.load(note, into: editor.textView)
        editor.type("typed", at: 4)
        let undo = try #require(editor.textView.undoManager)
        #expect(undo.canUndo)
        var reloaded = note
        reloaded.body = "Short"
        coordinator.load(reloaded, into: editor.textView)
        #expect(!undo.canUndo)
        #expect(editor.storage.string == "Short")
    }

    @Test func clickingACheckboxTicksItAndUndoUnticksIt() throws {
        let editor = EditorHarness("Groceries\n- [ ] milk\n")
        let box = (editor.storage.string as NSString).range(of: "[ ]")
        #expect(editor.textView.toggleCheckbox(atCharacter: box.location + 1))
        #expect(editor.storage.string == "Groceries\n- [x] milk\n")
        let done = (editor.storage.string as NSString).range(of: "milk")
        #expect(editor.storage.attribute(.strikethroughStyle, at: done.location, effectiveRange: nil) == nil)
        let colour = editor.storage.attribute(.foregroundColor, at: done.location, effectiveRange: nil) as? NSColor
        #expect(colour?.alphaComponent == 0.55)
        try #require(editor.textView.undoManager).undo()
        #expect(editor.storage.string == "Groceries\n- [ ] milk\n")
    }

    @Test func clickingTheDrawnBoxTicksItWithinA22PointTarget() throws {
        let editor = EditorHarness("Groceries\n- [ ] milk\n")
        editor.moveCaret(to: 0)
        let layoutManager = try #require(editor.textView.layoutManager as? NotesLayoutManager)
        layoutManager.ensureLayout(for: try #require(editor.textView.textContainer))
        let marker = NSRange(location: 10, length: 6)
        #expect(editor.storage.attribute(.notesDecoration, at: 10, effectiveRange: nil) as? Int == MarkdownSpan.Block.task.rawValue)
        let frame = try #require(layoutManager.decorationFrame(.task, marker: marker))
        #expect(frame.size == NSSize(width: 14, height: 14))
        let origin = editor.textView.textContainerOrigin
        let centre = NSPoint(x: frame.midX + origin.x, y: frame.midY + origin.y)

        #expect(!editor.textView.toggleCheckbox(at: NSPoint(x: centre.x + 12, y: centre.y)))
        #expect(editor.textView.toggleCheckbox(at: NSPoint(x: centre.x + 10, y: centre.y)))
        #expect(editor.storage.string == "Groceries\n- [x] milk\n")
        #expect(layoutManager.checkAnimation?.box == 12)
        #expect(editor.storage.attribute(.notesDecoration, at: 10, effectiveRange: nil) as? Int == MarkdownSpan.Block.doneTask.rawValue)
        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: 0))

        #expect(editor.textView.toggleCheckbox(at: centre))
        #expect(editor.storage.string == "Groceries\n- [ ] milk\n")
    }

    @Test func theCaretLineShowsTheTaskPrefixInsteadOfABox() {
        let editor = EditorHarness("Groceries\n- [ ] milk\n")
        editor.moveCaret(to: 18)
        #expect(editor.storage.attribute(.notesDecoration, at: 10, effectiveRange: nil) == nil)
        #expect(!editor.isHidden(at: 10))
        let paragraph = editor.storage.attribute(.paragraphStyle, at: 10, effectiveRange: nil) as? NSParagraphStyle
        #expect(paragraph?.headIndent == 22)
        #expect(editor.storage.isEqual(to: editor.styledFromScratch))
    }

    @Test func textOutsideACheckboxIsNotAToggle() {
        let editor = EditorHarness("Groceries\n- [ ] milk\n")
        #expect(!editor.textView.toggleCheckbox(atCharacter: 2))
        #expect(editor.storage.string == "Groceries\n- [ ] milk\n")
    }

    @Test func pasteTakesPlainTextOnly() throws {
        let editor = EditorHarness("")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NotchemonNotesTest-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let rich = NSAttributedString(string: "pasted", attributes: [.font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.red])
        let rtf = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("pasted", forType: .string)
        #expect(editor.textView.readSelection(from: pasteboard))
        #expect(editor.storage.string == "pasted")
        #expect(editor.font(at: 0)?.pointSize == editor.highlighter.theme.size)
        #expect(editor.storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor != NSColor.red)
    }
}

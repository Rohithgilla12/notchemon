import AppKit
import Testing
@testable import Notchemon

/// A styled editor in a window that is never shown, which supplies the undo manager.
@MainActor
final class EditorHarness {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 460), styleMask: [.titled], backing: .buffered, defer: true)
    let textView: NotesTextView
    let highlighter = MarkdownHighlighter()
    var storage: NSTextStorage { textView.textStorage! }

    init(_ text: String) {
        let (scrollView, textView) = NotesTextView.makeScrollable()
        self.textView = textView
        textView.textStorage?.delegate = highlighter
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

    /// The same text styled in one pass, to compare piecewise restyling against.
    var styledFromScratch: NSAttributedString {
        let fresh = NSTextStorage(string: storage.string)
        highlighter.theme.restyle(fresh, range: NSRange(location: 0, length: fresh.length))
        return fresh
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

    @Test func clickingACheckboxTicksItAndUndoUnticksIt() throws {
        let editor = EditorHarness("Groceries\n- [ ] milk\n")
        let box = (editor.storage.string as NSString).range(of: "[ ]")
        #expect(editor.textView.toggleCheckbox(atCharacter: box.location + 1))
        #expect(editor.storage.string == "Groceries\n- [x] milk\n")
        let done = (editor.storage.string as NSString).range(of: "milk")
        #expect(editor.storage.attribute(.strikethroughStyle, at: done.location, effectiveRange: nil) != nil)
        try #require(editor.textView.undoManager).undo()
        #expect(editor.storage.string == "Groceries\n- [ ] milk\n")
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

import Foundation
import Testing
@testable import Notchemon

struct MarkdownStylerTests {
    /// Each span as `kind:"covered text"`, which reads better than offsets.
    func styled(_ text: String) -> [String] {
        let string = text as NSString
        return MarkdownStyler.spans(in: text).map { span in
            "\(label(span.kind)):\(string.substring(with: span.range))"
        }
    }

    func label(_ kind: MarkdownSpan.Kind) -> String {
        switch kind {
        case .heading(let level): "h\(level)"
        case .bold: "bold"
        case .italic: "italic"
        case .code: "code"
        case .link(let url): "link(\(url))"
        case .syntax: "syntax"
        case .listMarker: "list"
        case .checkbox(let checked): checked ? "done-box" : "box"
        case .done: "done"
        }
    }

    @Test func headings() {
        #expect(styled("# Title") == ["h1:# Title", "syntax:#"])
        #expect(styled("### Three **b**") == ["h3:### Three **b**", "syntax:###", "syntax:**", "bold:b", "syntax:**"])
        #expect(styled("#hashtag").isEmpty)
        #expect(styled("####### seven").isEmpty)
    }

    @Test func boldAndItalic() {
        #expect(styled("a **b** c") == ["syntax:**", "bold:b", "syntax:**"])
        #expect(styled("a __b__ c") == ["syntax:__", "bold:b", "syntax:__"])
        #expect(styled("an *em* word") == ["syntax:*", "italic:em", "syntax:*"])
        #expect(styled("an _em_ word") == ["syntax:_", "italic:em", "syntax:_"])
        #expect(styled("**bold *and italic* too**") == [
            "syntax:**", "bold:bold *and italic* too", "syntax:**", "syntax:*", "italic:and italic", "syntax:*",
        ])
    }

    @Test func literalStarsAndUnderscoresStayPlain() {
        #expect(styled("2 * 3 * 4").isEmpty)
        #expect(styled("snake_case_name").isEmpty)
        #expect(styled("** not bold**").isEmpty)
        #expect(styled("---").isEmpty)
    }

    @Test func inlineCodeHidesMarkupInside() {
        #expect(styled("run `make **all**` now") == ["syntax:`", "code:make **all**", "syntax:`"])
        #expect(styled("a `` b").isEmpty)
    }

    @Test func links() {
        #expect(styled("see [docs](https://example.com) here") == [
            "syntax:[", "link(https://example.com):docs", "syntax:](https://example.com)",
        ])
        #expect(styled("[not a link]").isEmpty)
    }

    @Test func bulletsAndNumbers() {
        #expect(styled("- item") == ["list:-"])
        #expect(styled("  * nested") == ["list:*"])
        #expect(styled("12. twelfth") == ["list:12."])
        #expect(styled("-not a list").isEmpty)
    }

    @Test func checkboxes() {
        #expect(styled("- [ ] buy milk") == ["list:-", "box:[ ]"])
        #expect(styled("- [x] paid rent") == ["list:-", "done-box:[x]", "done: paid rent"])
        #expect(styled("- [X] shouty") == ["list:-", "done-box:[X]", "done: shouty"])
        #expect(styled("- [ ]") == ["list:-", "box:[ ]"])
        #expect(styled("- [y] nope") == ["list:-"])
    }

    @Test func offsetsAreDocumentOffsetsAcrossLinesAndEmoji() {
        let text = "🙂 **a**\n- [ ] b"
        let spans = MarkdownStyler.spans(in: text)
        let box = spans.first { $0.kind == .checkbox(checked: false) }
        #expect(box.map { (text as NSString).substring(with: $0.range) } == "[ ]")
        #expect(spans.first { $0.kind == .bold }?.range == NSRange(location: 5, length: 1))
    }

    @Test func restylingTheEditedParagraphsMatchesRestylingEverything() {
        let text = "# Plan\nsome **bold** text\n- [x] done item\nplain `code` line\n" as NSString
        let whole = MarkdownStyler.spans(in: text, range: NSRange(location: 0, length: text.length))
        var pieced: [MarkdownSpan] = []
        var location = 0
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            pieced += MarkdownStyler.spans(in: text, range: NSRange(location: paragraph.location + 1, length: 0))
            location = NSMaxRange(paragraph)
        }
        #expect(pieced == whole)
    }
}

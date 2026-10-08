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
        case .strikethrough: "strike"
        case .code: "code"
        case .link(let url): "link(\(url))"
        case .syntax: "syntax"
        case .block(let block): "\(block)"
        case .number: "number"
        case .checkbox(let checked): checked ? "done-box" : "box"
        case .done: "done"
        case .quoted: "quoted"
        }
    }

    @Test func headings() {
        #expect(styled("# Title") == ["h1:# Title", "syntax:# "])
        #expect(styled("#") == ["h1:#", "syntax:#"])
        #expect(styled("### Three **b**") == ["h3:### Three **b**", "syntax:### ", "syntax:**", "bold:b", "syntax:**"])
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

    @Test func strikethrough() {
        #expect(styled("a ~~gone~~ b") == ["syntax:~~", "strike:gone", "syntax:~~"])
        #expect(styled("~~ loose ~~").isEmpty)
        #expect(styled("a ~ b ~ c").isEmpty)
    }

    @Test func literalStarsAndUnderscoresStayPlain() {
        #expect(styled("2 * 3 * 4").isEmpty)
        #expect(styled("snake_case_name").isEmpty)
        #expect(styled("** not bold**").isEmpty)
    }

    @Test func rulesAndQuotes() {
        #expect(styled("---") == ["rule:---"])
        #expect(styled("___") == ["rule:___"])
        #expect(styled("****").isEmpty)
        #expect(styled("--").isEmpty)
        #expect(styled("-- -").isEmpty)
        #expect(styled("> said **so**") == ["quote:> ", "quoted:said **so**", "syntax:**", "bold:so", "syntax:**"])
        #expect(styled(">") == ["quote:>"])
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
        #expect(styled("- item") == ["bullet:- "])
        #expect(styled("  * nested") == ["bullet:* "])
        #expect(styled("12. twelfth") == ["number:12."])
        #expect(styled("-not a list").isEmpty)
    }

    @Test func checkboxes() {
        #expect(styled("- [ ] buy milk") == ["task:- [ ] ", "box:[ ]"])
        #expect(styled("- [x] paid rent") == ["doneTask:- [x] ", "done-box:[x]", "done: paid rent"])
        #expect(styled("- [X] shouty") == ["doneTask:- [X] ", "done-box:[X]", "done: shouty"])
        #expect(styled("- [ ]") == ["task:- [ ]", "box:[ ]"])
        #expect(styled("- [y] nope") == ["bullet:- "])
        #expect(styled("1. [ ] numbered") == ["number:1.", "box:[ ]"])
    }

    @Test func offsetsAreDocumentOffsetsAcrossLinesAndEmoji() {
        let text = "🙂 **a**\n- [ ] b"
        let spans = MarkdownStyler.spans(in: text)
        let box = spans.first { $0.kind == .checkbox(checked: false) }
        #expect(box.map { (text as NSString).substring(with: $0.range) } == "[ ]")
        #expect(spans.first { $0.kind == .bold }?.range == NSRange(location: 5, length: 1))
    }

    @Test func markupHidesEverywhereButTheCaretLine() {
        let text = "# Plan\nsome **bold** text\n[docs](https://a.b) and `code`\n" as NSString
        let all = NSRange(location: 0, length: text.length)
        let hidden = { (caret: Int) -> [String] in
            let active = MarkdownStyler.activeLines(for: [NSRange(location: caret, length: 0)], in: text)
            return MarkdownStyler.hiddenRanges(in: text, range: all, active: active).map(text.substring(with:))
        }
        #expect(hidden(9) == ["# ", "[", "](https://a.b)", "`", "`"])
        let list = "- [x] done\n- item\n1. one" as NSString
        let listAll = NSRange(location: 0, length: list.length)
        let caretOnItem = MarkdownStyler.activeLines(for: [NSRange(location: 13, length: 0)], in: list)
        #expect(MarkdownStyler.hiddenRanges(in: list, range: listAll, active: caretOnItem).map(list.substring(with:)) == ["- [x] "])
        #expect(hidden(0) == ["**", "**", "[", "](https://a.b)", "`", "`"])
        #expect(hidden(text.length) == ["# ", "**", "**", "[", "](https://a.b)", "`", "`"])
    }

    @Test func aSelectionShowsMarkupOnEveryLineItTouches() {
        let text = "**a**\n**b**\n**c**" as NSString
        let active = MarkdownStyler.activeLines(for: [NSRange(location: 2, length: 6)], in: text)
        #expect(active == NSRange(location: 0, length: 12))
        let hidden = MarkdownStyler.hiddenRanges(in: text, range: NSRange(location: 0, length: text.length), active: active)
        #expect(hidden == [NSRange(location: 12, length: 2), NSRange(location: 15, length: 2)])
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

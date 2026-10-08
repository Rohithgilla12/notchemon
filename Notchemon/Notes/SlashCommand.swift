import Foundation

/// One replacement of the note's text, with where the selection lands after it.
struct TextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

/// A command in the `/` menu. Each one rewrites the `/query` the user typed
/// into plain Markdown.
struct SlashCommand: Identifiable, Equatable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case headings = "Headings"
        case inline = "Inline"
        case blocks = "Blocks"
    }

    enum Markup: Equatable, Sendable {
        /// Replaces the line's block prefix, such as `# ` or `- [ ] `.
        case linePrefix(String)
        /// Surrounds the caret, leaving it between the two markers.
        case wrap(String)
        case divider
    }

    let id: String
    let title: String
    let symbol: String
    let group: Group
    let markup: Markup

    static let all: [SlashCommand] = [
        SlashCommand(id: "h1", title: "Heading 1", symbol: "h.square", group: .headings, markup: .linePrefix("# ")),
        SlashCommand(id: "h2", title: "Heading 2", symbol: "h.square", group: .headings, markup: .linePrefix("## ")),
        SlashCommand(id: "h3", title: "Heading 3", symbol: "h.square", group: .headings, markup: .linePrefix("### ")),
        SlashCommand(id: "bold", title: "Bold", symbol: "bold", group: .inline, markup: .wrap("**")),
        SlashCommand(id: "italic", title: "Italic", symbol: "italic", group: .inline, markup: .wrap("_")),
        SlashCommand(id: "strikethrough", title: "Strikethrough", symbol: "strikethrough", group: .inline, markup: .wrap("~~")),
        SlashCommand(id: "code", title: "Code", symbol: "chevron.left.forwardslash.chevron.right", group: .inline, markup: .wrap("`")),
        SlashCommand(id: "checklist", title: "Checklist", symbol: "checklist", group: .blocks, markup: .linePrefix("- [ ] ")),
        SlashCommand(id: "bullets", title: "Bulleted list", symbol: "list.bullet", group: .blocks, markup: .linePrefix("- ")),
        SlashCommand(id: "numbers", title: "Numbered list", symbol: "list.number", group: .blocks, markup: .linePrefix("1. ")),
        SlashCommand(id: "quote", title: "Quote", symbol: "text.quote", group: .blocks, markup: .linePrefix("> ")),
        SlashCommand(id: "divider", title: "Divider", symbol: "minus", group: .blocks, markup: .divider),
    ]

    /// Commands whose titles fuzzily match `query`, grouped in table order
    /// and best first within each group. An empty query lists them all.
    static func matching(_ query: String) -> [SlashCommand] {
        let scored: [(command: SlashCommand, score: Int)] = all.compactMap { command in
            NoteSearch.fuzzyScore(query, in: command.title).map { (command, $0) }
        }
        return Group.allCases.flatMap { group -> [SlashCommand] in
            let members = scored.filter { $0.command.group == group }
            return members.sorted { $0.score > $1.score }.map(\.command)
        }
    }

    /// Whether a `/` typed at `slash` opens the menu: at a line's start or
    /// after whitespace, so paths and fractions stay plain text.
    static func opens(at slash: Int, in text: NSString) -> Bool {
        guard slash > 0 else { return true }
        let before = text.character(at: slash - 1)
        return before == 0x20 || before == 0x09 || before == 0x0A || before == 0x0D
    }

    /// The edit that turns `trigger`, the typed `/query`, into this command's
    /// markup in one replacement.
    func apply(to text: NSString, trigger: NSRange) -> TextEdit {
        var lineStart = 0
        var contentsEnd = 0
        text.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd, for: trigger)
        let head = text.substring(with: NSRange(location: lineStart, length: trigger.location - lineStart))
        switch markup {
        case .linePrefix(let prefix):
            let indent = String(head.prefix { $0 == " " || $0 == "\t" })
            let body = Self.removingBlockPrefix(from: String(head.dropFirst(indent.count)))
            let replacement = indent + prefix + body
            let range = NSRange(location: lineStart, length: NSMaxRange(trigger) - lineStart)
            return TextEdit(range: range, replacement: replacement, selection: NSRange(location: lineStart + (replacement as NSString).length, length: 0))
        case .wrap(let marker):
            let caret = trigger.location + (marker as NSString).length
            return TextEdit(range: trigger, replacement: marker + marker, selection: NSRange(location: caret, length: 0))
        case .divider:
            let alone = head.allSatisfy(\.isWhitespace) && NSMaxRange(trigger) == contentsEnd
            let replacement = alone ? "---\n" : "\n---\n"
            let caret = trigger.location + (replacement as NSString).length
            return TextEdit(range: trigger, replacement: replacement, selection: NSRange(location: caret, length: 0))
        }
    }

    /// `line` without a leading `# `, `- `, `- [ ] `, `1. `, or `> `, so a
    /// block command replaces the line's kind instead of stacking on it.
    static func removingBlockPrefix(from line: String) -> String {
        let patterns = [#"^#{1,6} "#, #"^[-*+] \[[ xX]\] "#, #"^[-*+] "#, #"^\d+[.)] "#, #"^> "#]
        for pattern in patterns {
            if let match = line.range(of: pattern, options: .regularExpression) {
                return String(line[match.upperBound...])
            }
        }
        return line
    }
}

/// The open `/` menu: where its trigger is, what was typed, and which row is chosen.
struct SlashMenuState: Equatable, Sendable {
    let slash: Int
    let query: String
    let results: [SlashCommand]
    let selected: Int

    var trigger: NSRange { NSRange(location: slash, length: (query as NSString).length + 1) }
    var selectedCommand: SlashCommand? { results.indices.contains(selected) ? results[selected] : nil }

    /// The menu after the text or caret changed, or nil when it should close:
    /// the `/` is gone, the caret left the query, the query spans a line, or
    /// a space ended a query that matches nothing.
    static func after(_ previous: SlashMenuState?, slash: Int, text: NSString, caret: Int) -> SlashMenuState? {
        guard slash < text.length, text.character(at: slash) == 0x2F, caret > slash, caret <= text.length else { return nil }
        let query = text.substring(with: NSRange(location: slash + 1, length: caret - slash - 1))
        guard !query.contains(where: \.isNewline) else { return nil }
        let results = SlashCommand.matching(query)
        if results.isEmpty, query.last == " " { return nil }
        let kept = previous?.selectedCommand.flatMap { command in results.firstIndex(of: command) }
        let selected = query == previous?.query ? kept : nil
        return SlashMenuState(slash: slash, query: query, results: results, selected: selected ?? bestIndex(query, in: results))
    }

    /// Moves the selection, wrapping past either end.
    func moving(by offset: Int) -> SlashMenuState {
        guard !results.isEmpty else { return self }
        let count = results.count
        return SlashMenuState(slash: slash, query: query, results: results, selected: ((selected + offset) % count + count) % count)
    }

    private static func bestIndex(_ query: String, in results: [SlashCommand]) -> Int {
        let scores: [Int] = results.map { NoteSearch.fuzzyScore(query, in: $0.title) ?? 0 }
        guard let best = scores.max() else { return 0 }
        return scores.firstIndex(of: best) ?? 0
    }
}

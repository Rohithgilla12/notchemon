import Foundation

struct MarkdownSpan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case bold
        case italic
        case strikethrough
        case code
        case link(String)
        /// Markup characters such as `# `, `**`, and backticks: hidden off the
        /// caret's lines, drawn faintly on them.
        case syntax
        /// A line's leading markup, such as `- ` or `- [x] `, drawn as a
        /// decoration off the caret's lines and faintly on them.
        case block(Block)
        /// The `1.` of a numbered item, which always shows.
        case number
        /// The `[ ]` or `[x]` of a task line.
        case checkbox(checked: Bool)
        /// The text after a ticked checkbox.
        case done
        /// The text after a quote's `> `.
        case quoted
    }

    enum Block: Int, Sendable {
        case bullet
        case task
        case doneTask
        case quote
        case rule
    }

    let kind: Kind
    let range: NSRange

    init(_ kind: Kind, _ location: Int, _ length: Int) {
        self.kind = kind
        range = NSRange(location: location, length: length)
    }

    /// Markup is hidden unless it sits on one of the `active` lines, the ones
    /// holding the caret or selection, so editing it stays honest. A line
    /// prefix hides only when a character follows it to hang its decoration on.
    func isHidden(outside active: NSRange, textLength: Int) -> Bool {
        switch kind {
        case .syntax: !NSLocationInRange(range.location, active)
        case .block: !NSLocationInRange(range.location, active) && NSMaxRange(range) < textLength
        default: false
        }
    }
}

/// Live-preview Markdown for the notes editor: text in, styled ranges out.
/// Every construct it knows fits on one line, so restyling the paragraphs an
/// edit touched gives the same result as restyling the whole note.
enum MarkdownStyler {
    static func spans(in text: String) -> [MarkdownSpan] {
        let string = text as NSString
        return spans(in: string, range: NSRange(location: 0, length: string.length))
    }

    /// Spans for the whole lines that `range` touches, in document offsets.
    static func spans(in text: NSString, range: NSRange) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var buffer: [unichar] = []
        var lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        let end = NSMaxRange(range)
        repeat {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            let length = contentsEnd - lineStart
            if length > 0 {
                buffer.removeAll(keepingCapacity: true)
                buffer.append(contentsOf: repeatElement(0, count: length))
                buffer.withUnsafeMutableBufferPointer { pointer in
                    text.getCharacters(pointer.baseAddress!, range: NSRange(location: lineStart, length: length))
                }
                var line = Line(characters: buffer, offset: lineStart)
                line.style()
                spans.append(contentsOf: line.spans)
            }
            if lineEnd <= lineStart { break }
            lineStart = lineEnd
        } while lineStart < end
        return spans
    }

    /// The whole lines the selections touch, where markup stays visible.
    static func activeLines(for selections: [NSRange], in text: NSString) -> NSRange {
        guard let first = selections.first else { return NSRange(location: 0, length: 0) }
        return selections.dropFirst().reduce(text.lineRange(for: first)) { NSUnionRange($0, text.lineRange(for: $1)) }
    }

    /// The markup laid out at zero width in the lines `range` touches.
    static func hiddenRanges(in text: NSString, range: NSRange, active: NSRange) -> [NSRange] {
        spans(in: text, range: range).filter { $0.isHidden(outside: active, textLength: text.length) }.map(\.range)
    }
}

private enum Char {
    static let space = unichar(0x20)
    static let tab = unichar(0x09)
    static let hash = unichar(0x23)
    static let star = unichar(0x2A)
    static let plus = unichar(0x2B)
    static let minus = unichar(0x2D)
    static let dot = unichar(0x2E)
    static let underscore = unichar(0x5F)
    static let backtick = unichar(0x60)
    static let openBracket = unichar(0x5B)
    static let closeBracket = unichar(0x5D)
    static let openParen = unichar(0x28)
    static let closeParen = unichar(0x29)
    static let tilde = unichar(0x7E)
    static let greater = unichar(0x3E)
    static let lowerX = unichar(0x78)
    static let upperX = unichar(0x58)

    static func isSpace(_ c: unichar) -> Bool { c == space || c == tab }
    static func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }

    static func isWord(_ c: unichar) -> Bool {
        isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c > 0x7F
    }
}

private struct Line {
    let characters: [unichar]
    let offset: Int
    var spans: [MarkdownSpan] = []

    init(characters: [unichar], offset: Int) {
        self.characters = characters
        self.offset = offset
    }

    var count: Int { characters.count }

    func at(_ index: Int) -> unichar? {
        index < count ? characters[index] : nil
    }

    mutating func add(_ kind: MarkdownSpan.Kind, _ start: Int, _ end: Int) {
        guard end > start else { return }
        spans.append(MarkdownSpan(kind, offset + start, end - start))
    }

    mutating func style() {
        var indent = 0
        while indent < count, Char.isSpace(characters[indent]) { indent += 1 }
        if let after = heading(from: indent) {
            inline(after, count)
        } else if rule(from: indent) {
            return
        } else if let after = listItem(from: indent) {
            inline(after, count)
        } else if let after = quote(from: indent) {
            inline(after, count)
        } else {
            inline(indent, count)
        }
    }

    /// `#` to `######` then a space, the whole line styled as a heading.
    mutating func heading(from start: Int) -> Int? {
        guard start <= 3 else { return nil }
        var end = start
        while end < count, characters[end] == Char.hash { end += 1 }
        let level = end - start
        guard (1...6).contains(level), end == count || Char.isSpace(characters[end]) else { return nil }
        add(.heading(level: level), 0, count)
        add(.syntax, start, end < count ? end + 1 : end)
        return end
    }

    /// Three or more `-` or `_` alone on a line. Not `*`: an empty `****`
    /// from the Bold command must not turn into a rule.
    mutating func rule(from start: Int) -> Bool {
        guard start <= 3, let mark = at(start), mark == Char.minus || mark == Char.underscore,
              count - start >= 3, characters[start...].allSatisfy({ $0 == mark }) else { return false }
        add(.block(.rule), start, count)
        return true
    }

    /// A bullet (`-`, `*`, `+`) or number (`1.`, `1)`) then a space, and an
    /// optional `[ ]` or `[x]` checkbox. Returns where the item's text starts.
    mutating func listItem(from start: Int) -> Int? {
        guard let first = at(start) else { return nil }
        let bulleted = first == Char.minus || first == Char.star || first == Char.plus
        var markerEnd = start + 1
        if !bulleted {
            markerEnd = start
            while markerEnd < count, Char.isDigit(characters[markerEnd]) { markerEnd += 1 }
            guard markerEnd > start, let dot = at(markerEnd), dot == Char.dot || dot == Char.closeParen else { return nil }
            markerEnd += 1
        }
        guard let gap = at(markerEnd), Char.isSpace(gap) else { return nil }
        let box = markerEnd + 1
        guard let checked = checkbox(at: box) else {
            add(bulleted ? .block(.bullet) : .number, start, bulleted ? box : markerEnd)
            return box
        }
        if bulleted {
            add(.block(checked ? .doneTask : .task), start, min(box + 4, count))
        } else {
            add(.number, start, markerEnd)
        }
        add(.checkbox(checked: checked), box, box + 3)
        if checked { add(.done, box + 3, count) }
        return box + 3
    }

    /// Whether `[ ]` or `[x]` starts at `box`, ending the line or followed by a space.
    func checkbox(at box: Int) -> Bool? {
        guard at(box) == Char.openBracket, at(box + 2) == Char.closeBracket, let mark = at(box + 1),
              mark == Char.space || mark == Char.lowerX || mark == Char.upperX,
              box + 3 == count || at(box + 3).map(Char.isSpace) == true else { return nil }
        return mark != Char.space
    }

    /// `> ` then the quoted text.
    mutating func quote(from start: Int) -> Int? {
        guard start <= 3, at(start) == Char.greater else { return nil }
        let end = at(start + 1).map(Char.isSpace) == true ? start + 2 : start + 1
        add(.block(.quote), start, end)
        add(.quoted, end, count)
        return end
    }

    mutating func inline(_ start: Int, _ end: Int) {
        var index = start
        while index < end {
            let next: Int?
            switch characters[index] {
            case Char.backtick: next = codeSpan(index, end)
            case Char.openBracket: next = link(index, end)
            case Char.star, Char.underscore: next = emphasis(index, end)
            case Char.tilde: next = strikethrough(index, end)
            default: next = nil
            }
            index = next ?? index + 1
        }
    }

    mutating func codeSpan(_ open: Int, _ end: Int) -> Int? {
        guard let close = find(Char.backtick, from: open + 1, before: end), close > open + 1 else { return nil }
        add(.syntax, open, open + 1)
        add(.code, open + 1, close)
        add(.syntax, close, close + 1)
        return close + 1
    }

    /// `[text](url)`: the text takes the link, the brackets and URL are syntax.
    mutating func link(_ open: Int, _ end: Int) -> Int? {
        guard let closeText = find(Char.closeBracket, from: open + 1, before: end), closeText > open + 1,
              at(closeText + 1) == Char.openParen,
              let closeURL = find(Char.closeParen, from: closeText + 2, before: end), closeURL > closeText + 2 else { return nil }
        let url = String(utf16CodeUnits: Array(characters[(closeText + 2)..<closeURL]), count: closeURL - closeText - 2)
        add(.syntax, open, open + 1)
        add(.link(url), open + 1, closeText)
        add(.syntax, closeText, closeURL + 1)
        return closeURL + 1
    }

    /// `**bold**`, `__bold__`, `*italic*`, `_italic_`. Underscores inside a
    /// word, as in snake_case, stay literal.
    mutating func emphasis(_ open: Int, _ end: Int) -> Int? {
        let marker = characters[open]
        if marker == Char.underscore, open > 0, Char.isWord(characters[open - 1]) { return nil }
        let width = at(open + 1) == marker ? 2 : 1
        let innerStart = open + width
        guard let first = at(innerStart), innerStart < end, !Char.isSpace(first), first != marker else { return nil }
        var search = innerStart + 1
        while let close = find(marker, from: search, before: end) {
            let closesRun = width == 1 || at(close + 1) == marker
            let tightBefore = !Char.isSpace(characters[close - 1])
            let afterClose = close + width
            let wordAfter = marker == Char.underscore && afterClose < count && Char.isWord(characters[afterClose])
            let doubledSingle = width == 1 && at(close + 1) == marker
            if closesRun, tightBefore, !wordAfter, !doubledSingle, afterClose <= end {
                add(.syntax, open, innerStart)
                add(width == 2 ? .bold : .italic, innerStart, close)
                add(.syntax, close, afterClose)
                inline(innerStart, close)
                return afterClose
            }
            search = close + (doubledSingle ? 2 : 1)
        }
        return nil
    }

    /// `~~struck~~`, tight against its text like emphasis.
    mutating func strikethrough(_ open: Int, _ end: Int) -> Int? {
        let innerStart = open + 2
        guard at(open + 1) == Char.tilde, innerStart < end, !Char.isSpace(characters[innerStart]),
              characters[innerStart] != Char.tilde else { return nil }
        var search = innerStart + 1
        while let close = find(Char.tilde, from: search, before: end) {
            if close + 1 < end, characters[close + 1] == Char.tilde, !Char.isSpace(characters[close - 1]) {
                add(.syntax, open, innerStart)
                add(.strikethrough, innerStart, close)
                add(.syntax, close, close + 2)
                inline(innerStart, close)
                return close + 2
            }
            search = close + 1
        }
        return nil
    }

    func find(_ target: unichar, from start: Int, before end: Int) -> Int? {
        var index = start
        while index < end {
            if characters[index] == target { return index }
            index += 1
        }
        return nil
    }
}

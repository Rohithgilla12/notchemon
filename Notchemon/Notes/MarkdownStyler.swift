import Foundation

struct MarkdownSpan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(level: Int)
        case bold
        case italic
        case code
        case link(String)
        /// Markup characters such as `#`, `**`, and backticks, drawn faintly.
        case syntax
        case listMarker
        /// The `[ ]` or `[x]` of a task line.
        case checkbox(checked: Bool)
        /// The text after a ticked checkbox.
        case done
    }

    let kind: Kind
    let range: NSRange

    init(_ kind: Kind, _ location: Int, _ length: Int) {
        self.kind = kind
        range = NSRange(location: location, length: length)
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
        } else if let after = listItem(from: indent) {
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
        add(.syntax, start, end)
        return end
    }

    /// A bullet (`-`, `*`, `+`) or number (`1.`, `1)`) then a space, and an
    /// optional `[ ]` or `[x]` checkbox. Returns where the item's text starts.
    mutating func listItem(from start: Int) -> Int? {
        guard let first = at(start) else { return nil }
        var markerEnd = start
        if first == Char.minus || first == Char.star || first == Char.plus {
            markerEnd = start + 1
        } else {
            while markerEnd < count, Char.isDigit(characters[markerEnd]) { markerEnd += 1 }
            guard markerEnd > start, let dot = at(markerEnd), dot == Char.dot || dot == Char.closeParen else { return nil }
            markerEnd += 1
        }
        guard let gap = at(markerEnd), Char.isSpace(gap) else { return nil }
        add(.listMarker, start, markerEnd)
        let box = markerEnd + 1
        guard at(box) == Char.openBracket, at(box + 2) == Char.closeBracket, let mark = at(box + 1),
              mark == Char.space || mark == Char.lowerX || mark == Char.upperX,
              box + 3 == count || at(box + 3).map(Char.isSpace) == true else { return box }
        let checked = mark != Char.space
        add(.checkbox(checked: checked), box, box + 3)
        if checked { add(.done, box + 3, count) }
        return box + 3
    }

    mutating func inline(_ start: Int, _ end: Int) {
        var index = start
        while index < end {
            let next: Int?
            switch characters[index] {
            case Char.backtick: next = codeSpan(index, end)
            case Char.openBracket: next = link(index, end)
            case Char.star, Char.underscore: next = emphasis(index, end)
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

    func find(_ target: unichar, from start: Int, before end: Int) -> Int? {
        var index = start
        while index < end {
            if characters[index] == target { return index }
            index += 1
        }
        return nil
    }
}

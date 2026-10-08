import Foundation

struct NoteMatch: Equatable, Sendable {
    let id: UUID
    let title: String
    /// The body line that matched, when the title did not.
    let snippet: String?
}

/// The quick switcher's search: fuzzy over titles, every word over bodies.
enum NoteSearch {
    static let snippetLength = 90
    private static let titleBonus = 1_000

    /// Best first; ties keep the list order. An empty query lists every note.
    static func rank(_ query: String, in notes: [Note]) -> [NoteMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return notes.map { NoteMatch(id: $0.id, title: $0.title, snippet: nil) }
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        var scored: [(match: NoteMatch, score: Int, order: Int)] = []
        for (order, note) in notes.enumerated() {
            let title = note.title
            if let score = fuzzyScore(trimmed, in: title) {
                scored.append((NoteMatch(id: note.id, title: title, snippet: nil), titleBonus + score, order))
            } else if let line = lineMatchingAll(words, in: note.body) {
                scored.append((NoteMatch(id: note.id, title: title, snippet: line), 0, order))
            }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.map(\.match)
    }

    /// Nil unless `query`'s letters appear in order in `candidate`. Runs of
    /// consecutive letters and letters at word starts score higher.
    static func fuzzyScore(_ query: String, in candidate: String) -> Int? {
        let needle = Array(fold(query).filter { !$0.isWhitespace })
        let haystack = Array(fold(candidate))
        guard !needle.isEmpty else { return 0 }
        var score = 0
        var matched = 0
        var previous: Int?
        for (index, character) in haystack.enumerated() where matched < needle.count {
            guard character == needle[matched] else { continue }
            score += 1
            if let previous, previous == index - 1 { score += 5 }
            if index == 0 || !(haystack[index - 1].isLetter || haystack[index - 1].isNumber) { score += 8 }
            previous = index
            matched += 1
        }
        return matched == needle.count ? score : nil
    }

    /// The first body line after the title holding every word, shortened.
    static func lineMatchingAll(_ words: [String], in body: String) -> String? {
        let folded = words.map(fold)
        let whole = fold(body)
        guard folded.allSatisfy({ whole.contains($0) }) else { return nil }
        let lines = body.split(whereSeparator: \.isNewline)
        let line = lines.dropFirst().first { line in
            let foldedLine = fold(String(line))
            return folded.contains { foldedLine.contains($0) }
        } ?? lines.first
        return line.map { String($0.trimmingCharacters(in: .whitespaces).prefix(snippetLength)) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

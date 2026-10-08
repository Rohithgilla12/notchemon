import Foundation

/// One floating note. The file name is the note's lasting identity: it is
/// chosen once, at the first save, and never follows later title edits, so no
/// separate index maps notes to files. `id` only identifies the note in memory,
/// including before it has a file.
struct Note: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Nil until the first save names the file.
    var url: URL?
    /// The whole Markdown text. Its first line is the title.
    var body: String
    var modified: Date

    init(id: UUID = UUID(), url: URL? = nil, body: String, modified: Date) {
        self.id = id
        self.url = url
        self.body = body
        self.modified = modified
    }

    var title: String { Self.title(of: body) }

    /// The first line without heading marks, or "Untitled" when blank.
    static func title(of body: String) -> String {
        let firstLine = body.prefix { !$0.isNewline }
        let stripped = firstLine.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Untitled" : stripped
    }
}

enum NoteFileName {
    static let maxSlugLength = 48

    /// `YYYYMMDD-kebab-title.md`, with `-2`, `-3`, … appended until it is not
    /// in `taken`. Compared case-insensitively, as APFS is by default.
    static func make(title: String, date: Date, timeZone: TimeZone = .current, taken: Set<String>) -> String {
        let stem = "\(datePrefix(date, timeZone: timeZone))-\(slug(title))"
        let lowered = Set(taken.map { $0.lowercased() })
        var candidate = "\(stem).md"
        var suffix = 2
        while lowered.contains(candidate.lowercased()) {
            candidate = "\(stem)-\(suffix).md"
            suffix += 1
        }
        return candidate
    }

    /// Lowercase letters and digits joined by single hyphens, diacritics folded.
    static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var words: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        var slug = ""
        for word in words {
            let next = slug.isEmpty ? word : "\(slug)-\(word)"
            if next.count > maxSlugLength { break }
            slug = next
        }
        if slug.isEmpty, let first = words.first { slug = String(first.prefix(maxSlugLength)) }
        return slug.isEmpty ? "untitled" : slug
    }

    static func datePrefix(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

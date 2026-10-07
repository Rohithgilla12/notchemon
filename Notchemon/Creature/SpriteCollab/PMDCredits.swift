import Foundation

/// A species' `credits.txt`: one tab-separated contribution per line.
/// Sprites are CC BY-NC 4.0, so these authors must be shown wherever the sprite is.
struct PMDCredits: Sendable, Equatable {
    struct Contribution: Sendable, Equatable {
        let timestamp: String
        let authorID: String
        let status: String
        let license: String
        let animNames: [String]
    }

    let contributions: [Contribution]

    init(text: String) {
        contributions = text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, !fields[1].isEmpty else { return nil }
            let field = { (index: Int) in index < fields.count ? fields[index] : "" }
            return Contribution(
                timestamp: fields[0],
                authorID: fields[1],
                status: field(2),
                license: field(3),
                animNames: field(4).split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
        }
    }

    var allAuthors: [String] {
        unique(contributions.map(\.authorID))
    }

    func authors(for animName: String) -> [String] {
        unique(contributions.filter { $0.animNames.contains(animName) }.map(\.authorID))
    }

    private func unique(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

/// The repo-wide `credit_names.txt`: `Name<TAB>Discord<TAB>Contact`, where the
/// Discord column is the author id that `credits.txt` uses.
struct PMDCreditNames: Sendable, Equatable {
    private let names: [String: String]

    init(text: String) {
        var names: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty,
                  names[fields[1]] == nil
            else { continue }
            names[fields[1]] = fields[0]
        }
        self.names = names
    }

    func displayName(for authorID: String) -> String? {
        names[authorID]
    }
}

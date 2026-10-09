import Foundation

/// A creature on screen with the credits of the frames it is drawn in.
struct DrawnCreature: Sendable, Equatable {
    let name: String
    let attributions: [Attribution]
}

/// The credit owed for every creature on screen. Creatures drawn from one
/// source share its entry, and each author is named once, in the order the
/// creatures are drawn.
struct SpriteCredits: Sendable, Equatable {
    struct Source: Sendable, Equatable {
        let source: String
        let license: String
        let url: URL
        fileprivate(set) var authors: [String]

        var terms: String { "\(source) (\(license))" }

        /// The part of the line that truncates, or nil when the source credits no one.
        var byline: String? {
            authors.isEmpty ? nil : "Sprites by \(authors.joined(separator: ", "))"
        }

        var line: String {
            guard let byline else { return "Sprites from \(terms)" }
            return "\(byline) · \(terms)"
        }

        fileprivate func credits(_ attribution: Attribution) -> Bool {
            source == attribution.source && license == attribution.license && url == attribution.url
        }
    }

    /// One credited creature and who drew it, for the full list.
    struct Credit: Sendable, Equatable {
        let name: String
        /// Its authors, or its sources' terms when they credit no one.
        let byline: String
    }

    let sources: [Source]
    let creatures: [Credit]

    /// Nil when no creature on screen is owed a credit.
    init?(_ drawn: [DrawnCreature]) {
        var sources: [Source] = []
        var creatures: [Credit] = []
        for creature in drawn where !creature.attributions.isEmpty {
            var authors: [String] = []
            var terms: [String] = []
            for attribution in creature.attributions {
                authors.appendUnique(attribution.authors)
                if let index = sources.firstIndex(where: { $0.credits(attribution) }) {
                    sources[index].authors.appendUnique(attribution.authors)
                } else {
                    var source = Source(source: attribution.source, license: attribution.license, url: attribution.url, authors: [])
                    source.authors.appendUnique(attribution.authors)
                    sources.append(source)
                }
                terms.appendUnique(["\(attribution.source) (\(attribution.license))"])
            }
            let byline: String = authors.isEmpty ? terms.joined(separator: ", ") : authors.joined(separator: ", ")
            creatures.append(Credit(name: creature.name, byline: byline))
        }
        guard !sources.isEmpty else { return nil }
        self.sources = sources
        self.creatures = creatures
    }

    /// For example "Sprites by A, B · SpriteCollab (CC BY-NC 4.0)".
    var line: String {
        sources.map(\.line).joined(separator: "; ")
    }

    /// Each creature with its authors, then the terms.
    var fullList: String {
        let names: [String] = creatures.map { "\($0.name): \($0.byline)" }
        let pages = sources.count == 1 ? "page" : "pages"
        let terms = sources.map(\.terms).joined(separator: ", ")
        return (names + ["\(terms). Click to open the project \(pages)."]).joined(separator: "\n")
    }
}

private extension [String] {
    mutating func appendUnique(_ names: [String]) {
        for name in names where !contains(name) {
            append(name)
        }
    }
}

extension CompanionSnapshot {
    /// The leader, its followers, and a visitor, in that order.
    var drawnCreatures: [DrawnCreature] {
        var drawn: [DrawnCreature] = []
        if case .active(let species, _) = phase, let sprite {
            drawn.append(DrawnCreature(name: species.name, attributions: sprite.attributions))
        }
        for follower in followers {
            drawn.append(DrawnCreature(name: follower.species.name, attributions: follower.sprites.attributions))
        }
        if let encounter {
            drawn.append(DrawnCreature(name: encounter.species.name, attributions: encounter.show.attributions))
        }
        return drawn
    }
}

extension SpriteShow {
    var attributions: [Attribution] {
        let shown: [SpriteFrames?] = [loop, oneShot?.frames, walk?.left, walk?.right]
        return shown.compactMap { $0?.attribution }
    }
}

extension SpriteSet {
    /// In anim and facing order rather than dictionary order, so the authors
    /// keep their order from one launch to the next.
    var attributions: [Attribution] {
        SpriteState.allCases.flatMap { (state: SpriteState) -> [Attribution] in
            Facing.allCases.compactMap { (facing: Facing) -> Attribution? in anims[state]?[facing]?.attribution }
        }
    }
}

import Foundation

struct Progress: Codable, Sendable, Equatable {
    var speciesId: Int
    var level: Int
    var xp: Int

    static func starter(_ speciesId: Int) -> Progress {
        Progress(speciesId: speciesId, level: XPRules.startingLevel, xp: 0)
    }
}

enum ProgressEvent: Sendable, Equatable {
    case levelledUp(to: Int)
    case evolves(from: Int, to: Int)
}

enum XPRules {
    static let startingLevel = 5
    static let maxLevel = 100
    static let xpPerCompletedSession = 100

    static func xpToNextLevel(from level: Int) -> Int { level * 40 }

    static func xp(forCompletedSessionOf minutes: Int, standardMinutes: Int = 25) -> Int {
        guard minutes > 0 else { return 0 }
        return xpPerCompletedSession * minutes / standardMinutes
    }

    /// Adds XP, rolls over levels, and reports at most one evolution: the caller
    /// fetches the evolved species to learn whether a further stage applies.
    static func award(_ amount: Int, to progress: Progress, species: Species) -> (Progress, [ProgressEvent]) {
        var next = progress
        var events: [ProgressEvent] = []
        next.xp += max(0, amount)
        while next.level < maxLevel, next.xp >= xpToNextLevel(from: next.level) {
            next.xp -= xpToNextLevel(from: next.level)
            next.level += 1
            events.append(.levelledUp(to: next.level))
        }
        if next.level >= maxLevel { next.xp = 0 }
        if let evolution = pendingEvolution(level: next.level, species: species) {
            events.append(evolution)
        }
        return (next, events)
    }

    static func pendingEvolution(level: Int, species: Species) -> ProgressEvent? {
        guard let target = species.evolvesTo, let at = species.evolvesAtLevel, level >= at else { return nil }
        return .evolves(from: species.id, to: target)
    }
}

import Foundation

/// What opens a tier: this much focus or this much creature-scale walking,
/// whichever comes first.
struct UnlockThreshold: Sendable, Equatable {
    let focusMinutes: Int
    let creatureKilometres: Double

    func isMet(by stats: Stats) -> Bool {
        stats.focusMinutes >= focusMinutes || stats.creatureMetres >= creatureKilometres * 1000
    }
}

/// Which species may join the collection, derived from the stats every
/// time and never stored. An open tier makes its species available to
/// choose; it adds nobody by itself.
enum UnlockRules {
    /// The requirement for tier 1, 2, and so on; tier 0 is always open.
    /// Tier 1 is about a week of light use: a focus session or two a day,
    /// or a couple of hours a day of wandering, which walks a half-metre
    /// creature about 2 km. Each later tier asks for more than the last
    /// step did, so the last arrives after about seven months of the same.
    static let thresholds: [UnlockThreshold] = [
        UnlockThreshold(focusMinutes: 250, creatureKilometres: 15),
        UnlockThreshold(focusMinutes: 600, creatureKilometres: 35),
        UnlockThreshold(focusMinutes: 1_200, creatureKilometres: 70),
        UnlockThreshold(focusMinutes: 2_000, creatureKilometres: 120),
        UnlockThreshold(focusMinutes: 3_000, creatureKilometres: 180),
        UnlockThreshold(focusMinutes: 4_200, creatureKilometres: 250),
        UnlockThreshold(focusMinutes: 5_600, creatureKilometres: 340),
        UnlockThreshold(focusMinutes: 7_200, creatureKilometres: 440),
    ]

    /// Nil for tier 0, which needs nothing, and for tiers past the table,
    /// which only the override opens.
    static func threshold(forTier tier: Int) -> UnlockThreshold? {
        thresholds.indices.contains(tier - 1) ? thresholds[tier - 1] : nil
    }

    static func isOpen(tier: Int, stats: Stats, override: Bool) -> Bool {
        if override || tier == 0 { return true }
        return threshold(forTier: tier)?.isMet(by: stats) ?? false
    }

    /// How many of `tierCount` tiers are open.
    static func openTiers(stats: Stats, tierCount: Int, override: Bool) -> Int {
        (0..<tierCount).filter { isOpen(tier: $0, stats: stats, override: override) }.count
    }

    /// Every species in an open tier, in tier order.
    static func available(stats: Stats, tiers: [[Int]], override: Bool) -> [Int] {
        tiers.indices.filter { isOpen(tier: $0, stats: stats, override: override) }.flatMap { tiers[$0] }
    }

    /// The lowest tier still closed and what opens it, or nil when every
    /// tier the table covers is open.
    static func next(stats: Stats, tierCount: Int) -> (tier: Int, threshold: UnlockThreshold)? {
        for tier in 1..<max(1, tierCount) {
            guard let threshold = threshold(forTier: tier), !threshold.isMet(by: stats) else { continue }
            return (tier, threshold)
        }
        return nil
    }
}

/// Lets a developer, or anyone who asks for it, choose every species.
enum UnlockOverride {
    static let defaultsKey = "NotchemonUnlockAll"

    /// Debug builds carry the `.debug` bundle ID suffix.
    static func isDeveloperBuild(bundleIdentifier: String?) -> Bool {
        bundleIdentifier?.hasSuffix(".debug") == true
    }

    /// A saved choice wins; without one, debug builds start with everything open.
    static func isOn(defaults: UserDefaults, bundleIdentifier: String?) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil else { return isDeveloperBuild(bundleIdentifier: bundleIdentifier) }
        return defaults.bool(forKey: defaultsKey)
    }
}

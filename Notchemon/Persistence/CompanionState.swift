import Foundation

/// Persisted at `~/Library/Application Support/Notchemon/state.json`.
/// `progress` is nil until the user picks a starter.
struct CompanionState: Codable, Sendable, Equatable {
    var progress: Progress?
    var stats = Stats()
    /// File bookmark data, oldest first.
    var stash: [Data] = []
    var preferences = Preferences()

    static let empty = CompanionState(progress: nil)
    static let stashCapacity = 5
}

extension CompanionState {
    /// Tolerates files written before a field existed, and ignores keys
    /// that are no longer read.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progress = try container.decodeIfPresent(Progress.self, forKey: .progress)
        stats = try container.decodeIfPresent(Stats.self, forKey: .stats) ?? Stats()
        // Before stats, focus minutes were the one tally kept.
        if !container.contains(.stats) {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            stats.focusMinutes = try legacy.decodeIfPresent(Int.self, forKey: .totalFocusMinutes) ?? 0
        }
        stash = try container.decodeIfPresent([Data].self, forKey: .stash) ?? []
        preferences = try container.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }

    private enum LegacyKeys: String, CodingKey {
        case totalFocusMinutes
    }
}

struct Preferences: Codable, Sendable, Equatable {
    static let focusLengths = [15, 25, 45, 60]

    var focusMinutes = 25
    var focusSound = FocusSound.off
    var sleepEnabled = true
    var virtualNotchEnabled = true
    var clickToOpen = false
    var idleStyle = IdleStyle.calm
    var hopsOnApproach = true
    var fidgets = true
    var wander = WanderRange.topEdgeAndDock
}

/// Played when a focus session completes. The raw values are stored in
/// `state.json`, so they never change; `label` is free to.
enum FocusSound: String, Codable, Sendable, CaseIterable {
    case off
    case chime
    case fanfare
    case ping

    var label: String {
        switch self {
        case .off: "Off"
        case .chime: "Chime"
        case .fanfare: "Fanfare"
        case .ping: "Ping"
        }
    }

    /// A sound every Mac ships in /System/Library/Sounds.
    var systemSoundName: String? {
        switch self {
        case .off: nil
        case .chime: "Glass"
        case .fanfare: "Hero"
        case .ping: "Ping"
        }
    }
}

/// Where the creature may walk: along the strip below the menu bar, along
/// the top of the Dock, or both.
enum WanderRange: String, Codable, Sendable, CaseIterable {
    /// Stays under the notch.
    case off
    /// A short walk either side of the notch.
    case nearNotch
    /// Anywhere along the top edge of the screen.
    case topEdge
    /// Along the top of the Dock, coming back to the notch now and then.
    case dock
    /// Anywhere along the top edge, and along the top of the Dock.
    case topEdgeAndDock

    var includesDock: Bool { self == .dock || self == .topEdgeAndDock }
}

/// How the creature passes the time between everything else it does.
enum IdleStyle: String, Codable, Sendable, CaseIterable {
    /// Stands still on its idle anim's rest frame.
    case calm
    /// Plays its idle anim on a loop, whatever motion that anim has.
    case lively
    /// Lies down where the species has the art for it, else stands calm.
    case sitting
}

extension Preferences {
    /// Every field falls back to its default, so adding one never fails an
    /// older file. Without this, synthesized Codable throws on the nested
    /// object and `StateStore` sets the user's whole state aside.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? defaults.focusMinutes
        // A sound from a newer version reads as off, not as a broken file.
        focusSound = (try? container.decodeIfPresent(FocusSound.self, forKey: .focusSound)) ?? defaults.focusSound
        sleepEnabled = try container.decodeIfPresent(Bool.self, forKey: .sleepEnabled) ?? defaults.sleepEnabled
        virtualNotchEnabled = try container.decodeIfPresent(Bool.self, forKey: .virtualNotchEnabled) ?? defaults.virtualNotchEnabled
        clickToOpen = try container.decodeIfPresent(Bool.self, forKey: .clickToOpen) ?? defaults.clickToOpen
        // A style from a newer version reads as the default, not as a broken file.
        idleStyle = (try? container.decodeIfPresent(IdleStyle.self, forKey: .idleStyle)) ?? defaults.idleStyle
        hopsOnApproach = try container.decodeIfPresent(Bool.self, forKey: .hopsOnApproach) ?? defaults.hopsOnApproach
        fidgets = try container.decodeIfPresent(Bool.self, forKey: .fidgets) ?? defaults.fidgets
        wander = (try? container.decodeIfPresent(WanderRange.self, forKey: .wander)) ?? defaults.wander
    }
}

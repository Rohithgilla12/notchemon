import Foundation

/// Persisted at `~/Library/Application Support/Notchemon/state.json`.
/// `progress` is nil until the user picks a starter.
struct CompanionState: Codable, Sendable, Equatable {
    var progress: Progress?
    var totalFocusMinutes: Int
    /// File bookmark data, oldest first.
    var stash: [Data]
    var preferences = Preferences()

    static let empty = CompanionState(progress: nil, totalFocusMinutes: 0, stash: [])
    static let stashCapacity = 5
}

extension CompanionState {
    /// Tolerates files written before a field existed, and ignores keys
    /// that are no longer read.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progress = try container.decodeIfPresent(Progress.self, forKey: .progress)
        totalFocusMinutes = try container.decodeIfPresent(Int.self, forKey: .totalFocusMinutes) ?? 0
        stash = try container.decodeIfPresent([Data].self, forKey: .stash) ?? []
        preferences = try container.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }
}

struct Preferences: Codable, Sendable, Equatable {
    static let focusLengths = [15, 25, 45, 60]

    var focusMinutes = 25
    var sleepEnabled = true
    var virtualNotchEnabled = true
}

extension Preferences {
    /// Every field falls back to its default, so adding one never fails an
    /// older file. Without this, synthesized Codable throws on the nested
    /// object and `StateStore` sets the user's whole state aside.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? defaults.focusMinutes
        sleepEnabled = try container.decodeIfPresent(Bool.self, forKey: .sleepEnabled) ?? defaults.sleepEnabled
        virtualNotchEnabled = try container.decodeIfPresent(Bool.self, forKey: .virtualNotchEnabled) ?? defaults.virtualNotchEnabled
    }
}

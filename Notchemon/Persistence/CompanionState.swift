import Foundation

/// Persisted at `~/Library/Application Support/Notchemon/state.json`.
/// `progress` is nil until the user picks a starter.
struct CompanionState: Codable, Sendable, Equatable {
    var progress: Progress?
    var totalFocusMinutes: Int
    var lastInteraction: Date
    /// Security-scoped bookmark data, oldest first.
    var stash: [Data]

    static let empty = CompanionState(progress: nil, totalFocusMinutes: 0, lastInteraction: .distantPast, stash: [])
    static let stashCapacity = 5
}

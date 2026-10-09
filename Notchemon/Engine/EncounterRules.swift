import Foundation
import os

/// Scheduling, visits, catches, and departures. Read with
/// `log show --info --predicate 'subsystem == "com.rohithgilla.Notchemon" && category == "encounter"'`.
let encounterLog = Logger(subsystem: "com.rohithgilla.Notchemon", category: "encounter")

/// What says the user is around and free to notice a visitor.
struct EncounterConditions: Sendable, Equatable {
    var secondsSinceInput: TimeInterval
    var sleeping: Bool
    var fullScreen: Bool
    var focusing: Bool
    var hasPartner: Bool
    /// A wild creature is already here.
    var visiting: Bool
}

/// Saved in `state.json`, so quitting neither skips a cooldown nor resets
/// the day's count.
struct EncounterClock: Codable, Sendable, Equatable {
    /// Active time still to pass before the next visit.
    var cooldownLeft: TimeInterval
    /// The start of the day `visitsToday` counts.
    var day: Date
    var visitsToday: Int
}

/// The clock plus the active stretch under way, which is never saved: a
/// relaunch starts inactive until the conditions say otherwise.
struct EncounterSchedule: Sendable, Equatable {
    var clock: EncounterClock
    var activeSince: Date?
}

/// When a wild creature visits. Cooldown counts only active time, so the
/// next visit is a deadline that exists only while the user is active, and
/// moves whenever that changes.
enum EncounterRules {
    static let cooldown: ClosedRange<TimeInterval> = (45 * 60)...(90 * 60)
    static let dailyLimit = 4
    /// How long a visitor walks around before it wanders off.
    static let visitLength: TimeInterval = 60
    /// Input within this long counts as the user being there.
    static let recentInput: TimeInterval = 120

    static func isActive(_ conditions: EncounterConditions) -> Bool {
        conditions.hasPartner && !conditions.visiting && conditions.secondsSinceInput < recentInput
            && !conditions.sleeping && !conditions.fullScreen && !conditions.focusing
    }

    static func fresh(at now: Date, calendar: Calendar, using rng: inout some RandomNumberGenerator) -> EncounterClock {
        EncounterClock(cooldownLeft: .random(in: cooldown, using: &rng), day: calendar.startOfDay(for: now), visitsToday: 0)
    }

    /// Banks the active time since the last update, starts a new day's
    /// count at midnight, and starts or ends the active stretch.
    static func update(_ schedule: EncounterSchedule, active: Bool, now: Date, calendar: Calendar) -> EncounterSchedule {
        var next = schedule
        if let since = schedule.activeSince {
            next.clock.cooldownLeft = max(0, schedule.clock.cooldownLeft - max(0, now.timeIntervalSince(since)))
        }
        next.activeSince = active ? now : nil
        let today = calendar.startOfDay(for: now)
        if today != schedule.clock.day {
            next.clock.day = today
            next.clock.visitsToday = 0
        }
        return next
    }

    /// When the next visit is due, or nil while the user is away or once
    /// today's visits are spent.
    static func deadline(_ schedule: EncounterSchedule) -> Date? {
        guard let since = schedule.activeSince, schedule.clock.visitsToday < dailyLimit else { return nil }
        return since + schedule.clock.cooldownLeft
    }

    /// Counts a visit that began and draws the next cooldown.
    static func visited(_ schedule: EncounterSchedule, using rng: inout some RandomNumberGenerator) -> EncounterSchedule {
        var next = schedule
        next.clock.visitsToday += 1
        next.clock.cooldownLeft = .random(in: cooldown, using: &rng)
        next.activeSince = nil
        return next
    }
}

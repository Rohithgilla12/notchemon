import Foundation

struct FocusSession: Sendable, Equatable {
    let startedAt: Date
    let duration: TimeInterval
    /// XP is credited for the configured length even when a debug override
    /// shortens the wall-clock duration.
    let creditedMinutes: Int

    var endsAt: Date { startedAt.addingTimeInterval(duration) }

    func remainingFraction(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, endsAt.timeIntervalSince(now) / duration))
    }
}

enum FocusOutcome: Sendable, Equatable {
    case completed(minutes: Int)
    case abandoned

    var xp: Int {
        switch self {
        case .completed(let minutes): XPRules.xp(forCompletedSessionOf: minutes)
        case .abandoned: 0
        }
    }
}

struct FocusTimer: Sendable, Equatable {
    private(set) var session: FocusSession?

    /// Starting while a session runs is a no-op that returns the running one.
    @discardableResult
    mutating func start(at now: Date, duration: TimeInterval, creditedMinutes: Int) -> FocusSession {
        if let session { return session }
        let session = FocusSession(startedAt: now, duration: duration, creditedMinutes: creditedMinutes)
        self.session = session
        return session
    }

    /// Stopping before the end abandons; a stop that races the end completes.
    mutating func stop(at now: Date) -> FocusOutcome? {
        guard let session else { return nil }
        self.session = nil
        return now >= session.endsAt ? .completed(minutes: session.creditedMinutes) : .abandoned
    }

    mutating func finishIfDue(at now: Date) -> FocusOutcome? {
        guard let session, now >= session.endsAt else { return nil }
        return stop(at: now)
    }
}

import Foundation
import Observation

/// Runs `RoamRules` in real time for one party member. It asks again only
/// at the current phase's deadline, when a walk carries the creature across
/// the edge of a still cursor's watch radius, or when an input changes, so
/// between those nothing in the app wakes; the renderer moves the sprite.
@MainActor
@Observable
final class Roamer {
    /// The root of the partner this roamer walks.
    @ObservationIgnored let partner: Int
    private(set) var phase = RoamPhase.home
    /// Called after the phase changes or a walk crosses the cursor's watch
    /// radius, so the creature can look at the cursor again from where it
    /// now is.
    @ObservationIgnored var onLookAgain: (() -> Void)?
    /// Called once for each walk that ends and each hop between perches.
    @ObservationIgnored var onEvent: ((CompanionEvent) -> Void)?
    /// Where the rest of the party stands and is headed, read only when this
    /// member decides where to go next, so a neighbour moving wakes nothing.
    @ObservationIgnored var occupied: () -> [Perch: [ClosedRange<Double>]] = { [:] }
    /// Set by the party while this member follows the leader.
    @ObservationIgnored var follower = false

    @ObservationIgnored private var range: ClosedRange<Double> = 0...0
    @ObservationIgnored private var dock: ClosedRange<Double>?
    @ObservationIgnored private var homing = Homing.snap
    @ObservationIgnored private var cursor: CursorOffset?
    @ObservationIgnored private var rng: SplitMix64
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var wakeAt: Date?

    /// Each member draws from its own generator, so two never wander in step.
    init(partner: Int, seed: UInt64 = .random(in: .min ... .max)) {
        self.partner = partner
        rng = SplitMix64(seed: seed)
    }

    /// For a member leaving the party: its next wake-up would find nothing to do.
    func stop() {
        wake?.cancel()
        wake = nil
        wakeAt = nil
    }

    /// Cheap to call on every mouse move: unchanged inputs do nothing.
    func update(range: ClosedRange<Double>, dock: ClosedRange<Double>?, homing: Homing) {
        guard range != self.range || dock != self.dock || homing != self.homing else { return }
        self.range = range
        self.dock = dock
        self.homing = homing
        advance()
    }

    /// The cursor relative to the creature's centre at x 0 on the perch it is
    /// on, or nil when it is unknown. Cheap to call on every mouse move.
    func watch(_ cursor: CursorOffset?) {
        guard cursor != self.cursor else { return }
        self.cursor = cursor
        schedule()
    }

    private func advance(lookAgain: Bool = false) {
        let now = Date()
        let inputs = RoamInputs(now: now, range: range, dock: dock, homing: homing, occupied: occupied(), follower: follower)
        let next = RoamRules.next(phase, inputs, using: &rng)
        let moved = next != phase
        let events = moved ? RoamRules.events(from: phase, to: next, at: now, partner: partner) : []
        if moved {
            roamLog.debug("partner \(self.partner, privacy: .public) \(String(describing: next), privacy: .public)")
            phase = next
        }
        for event in events { onEvent?(event) }
        schedule()
        if moved || lookAgain { onLookAgain?() }
    }

    private func schedule() {
        let now = Date()
        let crossings = cursor.flatMap { phase.walk?.crossings(of: $0, radius: BehaviourRules.watchRadius) } ?? []
        let deadline = ([phase.deadline].compactMap(\.self) + crossings.filter { $0 > now }).min()
        guard deadline != wakeAt else { return }
        wake?.cancel()
        wakeAt = deadline
        guard let deadline else {
            wake = nil
            return
        }
        wake = Task { [weak self] in
            // The default tolerance let an 8 s sleep run about half a second
            // long, by which time a walk is 17 pt past a crossing.
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)), tolerance: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            wakeAt = nil
            advance(lookAgain: true)
        }
    }
}

import Foundation
import Observation

/// Runs `RoamRules` in real time. It asks again only at the current phase's
/// deadline or when an input changes, so between those nothing in the app
/// wakes; the renderer moves the sprite.
@MainActor
@Observable
final class Roamer {
    private(set) var phase = RoamPhase.home
    /// Called after the phase changes, so the creature can look at the
    /// cursor again from where it now is.
    @ObservationIgnored var onPhaseChanged: (() -> Void)?

    @ObservationIgnored private var range: ClosedRange<Double> = 0...0
    @ObservationIgnored private var homing = Homing.snap
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var wakeAt: Date?

    /// Cheap to call on every mouse move: unchanged inputs do nothing.
    func update(range: ClosedRange<Double>, homing: Homing) {
        guard range != self.range || homing != self.homing else { return }
        self.range = range
        self.homing = homing
        advance()
    }

    private func advance() {
        let next = RoamRules.next(phase, RoamInputs(now: Date(), range: range, homing: homing), using: &rng)
        schedule(next.deadline)
        guard next != phase else { return }
        phase = next
        onPhaseChanged?()
    }

    private func schedule(_ deadline: Date?) {
        guard deadline != wakeAt else { return }
        wake?.cancel()
        wakeAt = deadline
        guard let deadline else {
            wake = nil
            return
        }
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            wakeAt = nil
            advance()
        }
    }
}

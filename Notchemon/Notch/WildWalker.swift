import Foundation
import Observation

/// Plays a wild creature's planned visit in real time. It wakes only at the
/// edge of each leg, so nothing in the app runs while the visitor walks;
/// the renderer moves the sprite.
@MainActor
@Observable
final class WildWalker {
    private(set) var visit: WildVisit?
    /// The engine's serial for the visit under way.
    private(set) var serial: Int?
    /// What the sprite does now. It changes only at a leg's edge.
    private(set) var track: SpriteTrack?
    /// Called whenever the visitor starts, changes leg, or goes.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called once a visit has played to its end, caught or not.
    @ObservationIgnored var onGone: ((Int) -> Void)?
    @ObservationIgnored private var wake: Task<Void, Never>?

    var isCaught: Bool {
        if case .caught = track { true } else { false }
    }

    func begin(_ visit: WildVisit, serial: Int) {
        self.visit = visit
        self.serial = serial
        advance()
    }

    /// Cuts the visit short with the catch where the visitor stands.
    /// Returns false when there was nothing there to catch.
    @discardableResult
    func catchNow() -> Bool {
        guard !isCaught, let caught = visit?.caught(at: Date()) else { return false }
        visit = caught
        advance()
        return true
    }

    /// Ends the visit without reporting it gone, for one the engine ended.
    func end() {
        wake?.cancel()
        wake = nil
        visit = nil
        serial = nil
        track = nil
        onChange?()
    }

    private func advance() {
        guard let visit, let leg = visit.leg(at: Date()) else {
            let gone = serial
            end()
            if let gone { onGone?(gone) }
            return
        }
        if track != leg.track { track = leg.track }
        onChange?()
        wake?.cancel()
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, leg.until.timeIntervalSinceNow)), tolerance: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }
}

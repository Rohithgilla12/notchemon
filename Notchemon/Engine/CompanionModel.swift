import CoreGraphics
import Foundation
import Observation

/// Main-actor mirror of the engine's latest snapshot, plus the intents views
/// send back. Views read this; they never talk to the engine directly.
@MainActor
@Observable
final class CompanionModel {
    private(set) var snapshot = CompanionSnapshot()
    private(set) var starterOptions: [StarterOption] = []
    private(set) var isLoadingStarters = false
    var noteDraft = ""
    @ObservationIgnored var onPreferencesChanged: ((Preferences) -> Void)?
    @ObservationIgnored var onChoosingStarter: (() -> Void)?

    @ObservationIgnored private let engine: CreatureEngine
    @ObservationIgnored private var lastSentOffset: Double??

    init(engine: CreatureEngine) {
        self.engine = engine
    }

    func run() async {
        await engine.start()
        apply(await engine.currentSnapshot)
        for await next in engine.snapshots {
            apply(next)
        }
    }

    private func apply(_ next: CompanionSnapshot) {
        let preferencesChanged = next.preferences != snapshot.preferences
        let wasChoosing = isChoosing(snapshot.phase)
        snapshot = next
        if preferencesChanged { onPreferencesChanged?(next.preferences) }
        if isChoosing(next.phase), !wasChoosing {
            onChoosingStarter?()
            if starterOptions.isEmpty, !isLoadingStarters {
                Task { await loadStarters() }
            }
        }
    }

    private func isChoosing(_ phase: CompanionPhase) -> Bool {
        if case .choosingStarter = phase { true } else { false }
    }

    var activeSpecies: Species? {
        if case .active(let species, _) = snapshot.phase { species } else { nil }
    }

    var progress: Progress? {
        if case .active(_, let progress) = snapshot.phase { progress } else { nil }
    }

    func loadStarters() async {
        isLoadingStarters = true
        starterOptions = await engine.starterOptions()
        isLoadingStarters = false
    }

    func choose(_ option: StarterOption) {
        Task { await engine.chooseStarter(option.id) }
    }

    func resetForNewStarter() {
        starterOptions = []
        Task { await engine.resetForNewStarter() }
    }

    func retry() {
        Task { await engine.retryNow() }
    }

    func toggleFocus() {
        Task {
            if snapshot.focus == nil {
                await engine.startFocus()
            } else {
                await engine.stopFocus()
            }
        }
    }

    func update(_ change: (inout Preferences) -> Void) {
        var preferences = snapshot.preferences
        change(&preferences)
        Task { await engine.setPreferences(preferences) }
    }

    func submitNote() {
        let text = noteDraft
        Task {
            if await engine.appendNote(text) { noteDraft = "" }
        }
    }

    func addToStash(_ urls: [URL]) async -> Bool {
        await engine.addToStash(urls)
    }

    func removeFromStash(_ url: URL) {
        Task { await engine.removeFromStash(url) }
    }

    /// Forwards the cursor only when what the creature would do changes, so
    /// mouse movement far from the notch costs no actor hops.
    func cursorMoved(to point: CGPoint, spriteCentre: CGPoint) {
        let dx = point.x - spriteCentre.x
        let dy = point.y - spriteCentre.y
        let near = (dx * dx + dy * dy).squareRoot() <= BehaviourRules.watchRadius
        let offset: Double? = near ? (Double(dx) / 30).rounded() * 30 : nil
        guard lastSentOffset != .some(offset) else { return }
        lastSentOffset = .some(offset)
        Task { await engine.cursorMoved(offsetX: offset) }
    }
}

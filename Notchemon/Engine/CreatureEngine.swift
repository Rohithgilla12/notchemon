import CoreGraphics
import Foundation

enum CompanionPhase: Sendable, Equatable {
    case loading
    /// `carryOver` is progress from a species the current provider does not
    /// know (after a provider switch); the new starter inherits its level.
    case choosingStarter(carryOver: Progress?)
    case active(Species, Progress)
    case unavailable(String)
}

enum Banner: Sendable, Equatable {
    case levelUp(Int)
    case evolved(into: String)
    case stashFull
}

struct StarterOption: Sendable, Identifiable {
    let species: Species
    let frames: SpriteFrames?
    var id: Int { species.id }
}

/// Everything the views render, published by the engine as one value.
struct CompanionSnapshot: Sendable {
    var phase: CompanionPhase = .loading
    var frames: SpriteFrames?
    var behaviour: Behaviour = .idle
    var preferences = Preferences()
    var focus: FocusSession?
    var banner: Banner?
    var stash: [StashItem] = []
    var evolutionCount = 0
    var totalFocusMinutes = 0
}

enum InputIdle {
    static func seconds() -> TimeInterval {
        // Any input event type; reading idle time needs no Accessibility permission.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// Owns the companion's state. Behaviour is never stored as a transition
/// history: the engine samples its inputs and asks `BehaviourRules` what the
/// creature is doing now.
actor CreatureEngine {
    nonisolated let snapshots: AsyncStream<CompanionSnapshot>
    private let continuation: AsyncStream<CompanionSnapshot>.Continuation

    private let provider: any CreatureProvider
    private let store: StateStore
    private let bookmarks: any BookmarkCodec
    private let notesURL: URL
    private let idleSeconds: @Sendable () -> TimeInterval
    private let now: @Sendable () -> Date
    private let sessionSecondsOverride: TimeInterval?

    private var state = CompanionState.empty
    private var snapshot = CompanionSnapshot()
    private var species: Species?
    private var framesByState: [SpriteState: SpriteFrames] = [:]
    private var timer = FocusTimer()
    private var cursorOffsetX: Double?
    private var lastCursorNear = Date.distantPast
    private var celebration: Celebration?
    private var celebrationTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var samplingTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    static let celebrationLength: Duration = .seconds(2)
    static let bannerLength: Duration = .seconds(4)
    static let retryInterval: Duration = .seconds(30)

    init(
        provider: any CreatureProvider,
        store: StateStore,
        bookmarks: any BookmarkCodec = SecurityScopedBookmarks(),
        notesURL: URL = AppPaths.notes,
        idleSeconds: @escaping @Sendable () -> TimeInterval = InputIdle.seconds,
        now: @escaping @Sendable () -> Date = Date.init,
        sessionSecondsOverride: TimeInterval? = nil
    ) {
        (snapshots, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.provider = provider
        self.store = store
        self.bookmarks = bookmarks
        self.notesURL = notesURL
        self.idleSeconds = idleSeconds
        self.now = now
        self.sessionSecondsOverride = sessionSecondsOverride
    }

    var currentSnapshot: CompanionSnapshot { snapshot }

    func start() async {
        state = store.load()
        snapshot.preferences = state.preferences
        snapshot.totalFocusMinutes = state.totalFocusMinutes
        refreshStash()
        await loadCompanion()
        startSampling()
    }

    func starterOptions() async -> [StarterOption] {
        await withTaskGroup(of: (Int, StarterOption?).self) { group in
            for (index, id) in provider.starterIDs.enumerated() {
                group.addTask { [provider] in
                    guard let species = try? await provider.species(id: id) else { return (index, nil) }
                    let frames = try? await provider.sprite(for: species, state: .idle)
                    return (index, StarterOption(species: species, frames: frames))
                }
            }
            var options: [(Int, StarterOption)] = []
            for await (index, option) in group {
                if let option { options.append((index, option)) }
            }
            return options.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func chooseStarter(_ id: Int) async {
        guard let chosen = try? await provider.species(id: id) else { return }
        var progress = Progress.starter(id)
        if case .choosingStarter(let carryOver?) = snapshot.phase {
            progress.level = carryOver.level
            progress.xp = carryOver.xp
        }
        state.progress = progress
        persist()
        await activate(chosen)
        await resolvePendingEvolutions()
    }

    /// Re-picking a starter resets progress; the menu confirms this first.
    func resetForNewStarter() {
        cancelFocus()
        state.progress = nil
        species = nil
        framesByState = [:]
        persist()
        snapshot.frames = nil
        snapshot.phase = .choosingStarter(carryOver: nil)
        publish()
    }

    func cursorMoved(offsetX: Double?) async {
        cursorOffsetX = offsetX
        if offsetX != nil { lastCursorNear = now() }
        await sample()
    }

    func setPreferences(_ preferences: Preferences) {
        guard preferences != state.preferences else { return }
        state.preferences = preferences
        snapshot.preferences = preferences
        persist()
        publish()
    }

    func startFocus() {
        guard species != nil, timer.session == nil else { return }
        let minutes = state.preferences.focusMinutes
        let duration = sessionSecondsOverride ?? TimeInterval(minutes * 60)
        let session = timer.start(at: now(), duration: duration, creditedMinutes: minutes)
        snapshot.focus = session
        publish()
        focusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self?.finishFocusIfDue()
        }
    }

    func stopFocus() async {
        guard let outcome = timer.stop(at: now()) else { return }
        focusTask?.cancel()
        await settle(outcome)
    }

    private func cancelFocus() {
        focusTask?.cancel()
        _ = timer.stop(at: .distantPast)
        snapshot.focus = nil
    }

    private func finishFocusIfDue() async {
        guard let outcome = timer.finishIfDue(at: now()) else { return }
        await settle(outcome)
    }

    private func settle(_ outcome: FocusOutcome) async {
        snapshot.focus = nil
        if case .completed(let minutes) = outcome {
            state.totalFocusMinutes += minutes
            snapshot.totalFocusMinutes = state.totalFocusMinutes
            await award(outcome.xp)
        } else {
            publish()
        }
    }

    func award(_ xp: Int) async {
        guard let species, let progress = state.progress else { return }
        let (next, events) = XPRules.award(xp, to: progress, species: species)
        state.progress = next
        snapshot.phase = .active(species, next)
        persist()
        if let level = events.compactMap({ if case .levelledUp(let level) = $0 { level } else { nil } }).last {
            await celebrate(.levelUp(level), banner: .levelUp(level))
        }
        publish()
        await resolvePendingEvolutions()
    }

    /// Idempotent: evolves as many stages as the current level allows, and if
    /// a fetch fails the evolution simply stays pending for the next call.
    private func resolvePendingEvolutions() async {
        while let species, let progress = state.progress,
              case .evolves(_, let targetID)? = XPRules.pendingEvolution(level: progress.level, species: species) {
            guard let target = try? await provider.species(id: targetID) else { return }
            state.progress?.speciesId = targetID
            persist()
            framesByState = [:]
            await activate(target)
            snapshot.evolutionCount += 1
            await celebrate(.evolution(from: species.id, to: targetID), banner: .evolved(into: target.name))
            publish()
        }
    }

    private func celebrate(_ celebration: Celebration, banner: Banner) async {
        self.celebration = celebration
        showBanner(banner)
        celebrationTask?.cancel()
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.celebrationLength)
            guard !Task.isCancelled else { return }
            await self?.endCelebration()
        }
        await sample()
    }

    private func endCelebration() async {
        celebration = nil
        await sample()
    }

    private func showBanner(_ banner: Banner) {
        snapshot.banner = banner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.bannerLength)
            guard !Task.isCancelled else { return }
            await self?.clearBanner()
        }
    }

    private func clearBanner() {
        snapshot.banner = nil
        publish()
    }

    func appendNote(_ text: String) -> Bool {
        (try? QuickNote.append(text, at: now(), to: notesURL)) ?? false
    }

    /// Returns false when anything was refused, so the view can shake.
    func addToStash(_ urls: [URL]) async -> Bool {
        let result = FileStash.add(urls, to: state.stash, capacity: CompanionState.stashCapacity, codec: bookmarks)
        if result.added > 0 {
            state.stash = result.bookmarks
            persist()
            refreshStash()
        }
        if result.refused > 0 { showBanner(.stashFull) }
        publish()
        await sample()
        return result.refused == 0
    }

    func removeFromStash(_ url: URL) async {
        state.stash = FileStash.remove(url, from: state.stash, codec: bookmarks)
        persist()
        refreshStash()
        publish()
        await sample()
    }

    private func refreshStash() {
        let (items, live) = FileStash.items(state.stash, codec: bookmarks)
        snapshot.stash = items
        if live.count != state.stash.count {
            state.stash = live
            persist()
        }
    }

    private func startSampling() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.sample() else { return }
                try? await Task.sleep(for: delay)
            }
        }
    }

    /// Resolves behaviour from current inputs and returns how soon to look
    /// again: quickly while asleep (keyboard input cannot be observed without
    /// Accessibility, so waking relies on polling idle time) or while the
    /// gaze is lingering, slowly otherwise.
    @discardableResult
    func sample() async -> Duration {
        await finishFocusIfDue()
        let instant = now()
        let inputs = BehaviourInputs(
            secondsSinceInput: idleSeconds(),
            cursorOffsetX: cursorOffsetX,
            secondsSinceCursorNear: instant.timeIntervalSince(lastCursorNear),
            stashCount: snapshot.stash.count,
            celebration: celebration,
            sleepEnabled: state.preferences.sleepEnabled
        )
        let behaviour = BehaviourRules.resolve(inputs)
        if behaviour != snapshot.behaviour {
            if snapshot.behaviour == .sleeping {
                state.lastInteraction = instant
                persist()
            }
            snapshot.behaviour = behaviour
            await refreshFrames()
            publish()
        }
        switch behaviour {
        case .sleeping: return .seconds(1)
        case .watching: return .milliseconds(500)
        default: return .seconds(3)
        }
    }

    private func loadCompanion() async {
        guard let progress = state.progress else {
            snapshot.phase = .choosingStarter(carryOver: nil)
            publish()
            return
        }
        do {
            let loaded = try await provider.species(id: progress.speciesId)
            await activate(loaded)
            await resolvePendingEvolutions()
        } catch CreatureError.unknownSpecies {
            snapshot.phase = .choosingStarter(carryOver: progress)
            publish()
        } catch {
            snapshot.phase = .unavailable("Can't reach the creature server. Retrying…")
            publish()
            scheduleRetry()
        }
    }

    func retryNow() async {
        guard case .unavailable = snapshot.phase else { return }
        retryTask?.cancel()
        snapshot.phase = .loading
        publish()
        await loadCompanion()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.retryInterval)
            guard !Task.isCancelled else { return }
            await self?.retryNow()
        }
    }

    private func activate(_ newSpecies: Species) async {
        species = newSpecies
        if let progress = state.progress {
            snapshot.phase = .active(newSpecies, progress)
        }
        await refreshFrames()
        publish()
    }

    private func refreshFrames() async {
        guard let species else { return }
        let spriteState = snapshot.behaviour.spriteState
        if let frames = framesByState[spriteState] {
            snapshot.frames = frames
            return
        }
        guard let frames = try? await provider.sprite(for: species, state: spriteState) else { return }
        guard self.species?.id == species.id else { return }
        framesByState[spriteState] = frames
        snapshot.frames = frames
    }

    private func persist() {
        try? store.save(state)
    }

    private func publish() {
        continuation.yield(snapshot)
    }
}

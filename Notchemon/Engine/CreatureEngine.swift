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
    /// `portrait` is the new form's large art for the reveal, when it loaded.
    case evolved(into: String, portrait: CGImage?)
    case stashFull
}

struct StarterOption: Sendable, Identifiable {
    let species: Species
    let portrait: CGImage?
    var id: Int { species.id }
}

/// A one-shot animation played once over the loop.
struct OneShot: Sendable {
    let state: SpriteState
    let frames: SpriteFrames
    /// Increments on every play, so a replay differs from a republish.
    let serial: Int
}

/// What the sprite view plays.
struct SpriteShow: Sendable {
    var loop: SpriteFrames
    /// The anim `loop` was drawn for, which decides the ground line it stands on.
    var loopState: SpriteState
    var playback: LoopPlayback
    var facing: Facing
    var bounds: SpriteBounds
    var oneShot: OneShot?
    /// Nil only when the provider has no frames for walking at all.
    var walk: WalkCycle?
}

/// The walk in each direction the creature travels along the strip.
struct WalkCycle: Sendable {
    let left: SpriteFrames
    let right: SpriteFrames

    func frames(toward facing: Facing) -> SpriteFrames {
        facing.horizontal < 0 ? left : right
    }
}

/// Everything the views render, published by the engine as one value.
struct CompanionSnapshot: Sendable {
    var phase: CompanionPhase = .loading
    var sprite: SpriteShow?
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
    private let sleepAfter: TimeInterval

    private var state = CompanionState.empty
    private var snapshot = CompanionSnapshot()
    private var species: Species?
    private var spriteCache: [SpriteKey: SpriteFrames] = [:]
    private var spriteBounds: SpriteBounds?
    private var oneShotSerial = 0
    private var timer = FocusTimer()
    private var cursorOffset: CursorOffset?
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
        bookmarks: any BookmarkCodec = FileBookmarks(),
        notesURL: URL = AppPaths.notes,
        idleSeconds: @escaping @Sendable () -> TimeInterval = InputIdle.seconds,
        now: @escaping @Sendable () -> Date = Date.init,
        sessionSecondsOverride: TimeInterval? = nil,
        sleepAfter: TimeInterval = BehaviourRules.sleepAfter
    ) {
        (snapshots, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.provider = provider
        self.store = store
        self.bookmarks = bookmarks
        self.notesURL = notesURL
        self.idleSeconds = idleSeconds
        self.now = now
        self.sessionSecondsOverride = sessionSecondsOverride
        self.sleepAfter = sleepAfter
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
                    let portrait = try? await provider.portrait(for: species)
                    return (index, StarterOption(species: species, portrait: portrait))
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
        forgetSprites()
        persist()
        snapshot.sprite = nil
        snapshot.phase = .choosingStarter(carryOver: nil)
        publish()
    }

    func cursorMoved(offset: CursorOffset?) async {
        cursorOffset = offset
        if offset != nil { lastCursorNear = now() }
        await sample()
    }

    func cursorNoticed() async {
        await play(.cursorNoticed)
    }

    func setPreferences(_ preferences: Preferences) async {
        guard preferences != state.preferences else { return }
        let restyled = preferences.idleStyle != state.preferences.idleStyle
        state.preferences = preferences
        snapshot.preferences = preferences
        persist()
        if restyled { await refreshLoop() }
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
            // Another entrant may have evolved, or reset, during the fetch.
            guard state.progress?.speciesId == species.id else { continue }
            state.progress?.speciesId = targetID
            persist()
            forgetSprites()
            await activate(target)
            snapshot.evolutionCount += 1
            let portrait = try? await provider.portrait(for: target)
            await celebrate(.evolution(from: species.id, to: targetID), banner: .evolved(into: target.name, portrait: portrait))
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
        if live != state.stash {
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
            cursorOffset: cursorOffset,
            secondsSinceCursorNear: instant.timeIntervalSince(lastCursorNear),
            stashCount: snapshot.stash.count,
            celebration: celebration,
            sleepEnabled: state.preferences.sleepEnabled,
            sleepAfter: sleepAfter
        )
        let behaviour = BehaviourRules.resolve(inputs)
        let previous = snapshot.behaviour
        if behaviour != previous {
            snapshot.behaviour = behaviour
            await refreshLoop()
            publish()
            await play(.behaviourChanged(from: previous, to: behaviour))
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
        await refreshLoop()
        publish()
    }

    private func refreshLoop() async {
        guard let species else { return }
        let behaviour = snapshot.behaviour
        let style = state.preferences.idleStyle
        guard let bounds = await bounds(of: species) else { return }
        var walk: WalkCycle?
        if let left = await frames(.walking, facing: .left, of: species), let right = await frames(.walking, facing: .right, of: species) {
            walk = WalkCycle(left: left, right: right)
        }
        for choice in SpriteChoreography.loops(for: behaviour, style: style) {
            guard let loop = await frames(choice.state, facing: behaviour.facing, of: species) else { continue }
            guard snapshot.behaviour == behaviour, state.preferences.idleStyle == style else { return }
            snapshot.sprite = SpriteShow(
                loop: loop,
                loopState: choice.state,
                playback: choice.playback,
                facing: behaviour.facing,
                bounds: bounds,
                oneShot: snapshot.sprite?.oneShot,
                walk: walk
            )
            return
        }
    }

    /// Without the cue's own frames, the loop stands in and the renderer
    /// supplies the motion, so a hop still reads as a hop offline.
    private func play(_ cue: SpriteCue) async {
        guard let state = SpriteChoreography.oneShot(for: cue), let species else { return }
        let fetched = await frames(state, facing: snapshot.behaviour.facing, of: species)
        guard let frames = fetched ?? snapshot.sprite?.loop, self.species?.id == species.id else { return }
        oneShotSerial += 1
        snapshot.sprite?.oneShot = OneShot(state: state, frames: frames, serial: oneShotSerial)
        publish()
    }

    private func frames(_ state: SpriteState, facing: Facing, of species: Species) async -> SpriteFrames? {
        if let hit = spriteCache[SpriteKey(state: state, facing: facing)] { return hit }
        guard let frames = try? await provider.sprite(for: species, state: state, facing: facing),
              self.species?.id == species.id
        else { return nil }
        // Undirected frames are the same from every side, so one fetch serves all eight.
        for cached in frames.directional ? [facing] : Facing.allCases {
            spriteCache[SpriteKey(state: state, facing: cached)] = frames
        }
        return frames
    }

    /// Fetches every anim in every facing the creature shows, so the bounds
    /// cover a hop before it first plays and its one-shots are cached ahead.
    private func bounds(of species: Species) async -> SpriteBounds? {
        if let spriteBounds { return spriteBounds }
        guard let rest = await frames(.idle, facing: .down, of: species) else { return nil }
        var anims: [SpriteState: [Facing: SpriteFrames]] = [:]
        for state in SpriteState.allCases {
            for facing in Facing.front {
                anims[state, default: [:]][facing] = await frames(state, facing: facing, of: species)
            }
        }
        guard self.species?.id == species.id else { return nil }
        let measured = SpriteRendering.bounds(rest: rest, anims: anims)
        spriteBounds = measured
        return measured
    }

    private func forgetSprites() {
        spriteCache = [:]
        spriteBounds = nil
    }

    private struct SpriteKey: Hashable {
        let state: SpriteState
        let facing: Facing
    }

    private func persist() {
        try? store.save(state)
    }

    private func publish() {
        continuation.yield(snapshot)
    }
}

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
    case stashCleared(undo: [Data])
    case caught(String)
    /// A wild creature whose family is already a partner.
    case seenAgain(String)
}

/// A wild creature on its visit.
struct Encounter: Sendable {
    /// Counts visits since launch, so each visitor differs from the last.
    let serial: Int
    let species: Species
    let show: SpriteShow
    var caught = false
}

/// A species the user can send out: a partner they have, or one they could add.
struct PartnerOption: Sendable, Identifiable {
    let species: Species
    let portrait: CGImage?
    /// The partner of its family, or nil for a family not yet in the collection.
    let partner: Partner?
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

/// Every anim one species has in every front facing, measured together.
struct SpriteSet: Sendable {
    let bounds: SpriteBounds
    let anims: [SpriteState: [Facing: SpriteFrames]]

    var walk: WalkCycle? {
        guard let left = anims[.walking]?[.left], let right = anims[.walking]?[.right] else { return nil }
        return WalkCycle(left: left, right: right)
    }

    /// The first loop the art has for `behaviour` in `style`, as `SpriteChoreography` ranks them.
    func show(for behaviour: Behaviour, style: IdleStyle) -> SpriteShow? {
        let facing = behaviour.facing
        for choice in SpriteChoreography.loops(for: behaviour, style: style) {
            guard let loop = anims[choice.state]?[facing] else { continue }
            return SpriteShow(
                loop: loop, loopState: choice.state, playback: choice.playback, facing: facing, bounds: bounds, oneShot: nil, walk: walk
            )
        }
        return nil
    }
}

/// A partner walking with the leader, with the frames it is drawn in.
struct Follower: Sendable {
    let root: Int
    let species: Species
    let sprites: SpriteSet
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
    /// Evolutions since launch, which flash the sprite.
    var evolutionCount = 0
    var stats = Stats()
    var unlocks = UnlockStatus()
    var encounter: Encounter?
    /// Sessions completed since launch. Each one plays the focus sound.
    var completedFocusSessions = 0
    /// The root of the partner that is out, which leads the party.
    var leader: Int?
    /// The roots of the partners walking with it, as soon as they are chosen.
    var followerRoots: [Int] = []
    /// Those followers whose frames have loaded, in party order.
    var followers: [Follower] = []
}

/// Where the user stands on unlocks, derived from the stats.
struct UnlockStatus: Sendable, Equatable {
    var openTiers = 0
    /// Every species is available, and the partner picker searches them all.
    var override = false
    /// What opens the next tier, or nil once the table runs out.
    var next: UnlockThreshold?
}

extension CompanionSnapshot {
    /// The sound to play on moving from `previous` to this snapshot, if a
    /// session completed in between. Snapshots coalesce, so this compares
    /// counts rather than watching for one particular snapshot.
    func focusSound(after previous: CompanionSnapshot) -> FocusSound? {
        guard completedFocusSessions > previous.completedFocusSessions, preferences.focusSound != .off else { return nil }
        return preferences.focusSound
    }
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
    private let unlockAll: @Sendable () -> Bool
    private var index: [SpeciesEntry]?

    private var state = CompanionState.empty
    private var snapshot = CompanionSnapshot()
    private var species: Species?
    /// Each follower's current species, by root.
    private var followerSpecies: [Int: Species] = [:]
    private var spriteCache: [SpriteKey: SpriteFrames] = [:]
    /// Fetches under way, which a second request for the same frames joins.
    private var spriteFetches: [SpriteKey: Task<SpriteFrames?, Never>] = [:]
    /// By species id.
    private var spriteSets: [Int: SpriteSet] = [:]
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
    private var rng = SystemRandomNumberGenerator()
    private let calendar = Calendar.current
    private var schedule: EncounterSchedule?
    private var encounterDeadline: Date?
    private var encounterTask: Task<Void, Never>?
    private var visitTask: Task<Void, Never>?
    private var spawning = false
    private var encounterSerial = 0
    private var fullScreen = false
    private var systemAsleep = false

    static let celebrationLength: Duration = .seconds(2)
    static let bannerLength: Duration = .seconds(4)
    static let undoLength: Duration = .seconds(5)
    static let retryInterval: Duration = .seconds(30)
    /// How soon to look again when no wild creature could be found.
    static let encounterRetry: TimeInterval = 5 * 60
    /// The visit ends by itself even if the view never reports it gone,
    /// well after the longest walk off a screen could take.
    static let visitLimit: Duration = .seconds(3 * EncounterRules.visitLength)

    init(
        provider: any CreatureProvider,
        store: StateStore,
        bookmarks: any BookmarkCodec = FileBookmarks(),
        notesURL: URL = AppPaths.notes,
        idleSeconds: @escaping @Sendable () -> TimeInterval = InputIdle.seconds,
        now: @escaping @Sendable () -> Date = Date.init,
        sessionSecondsOverride: TimeInterval? = nil,
        sleepAfter: TimeInterval = BehaviourRules.sleepAfter,
        unlockAll: @escaping @Sendable () -> Bool = { false }
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
        self.unlockAll = unlockAll
    }

    var currentSnapshot: CompanionSnapshot { snapshot }

    func start() async {
        state = store.load()
        if state.progress != nil, state.stats.firstMet == nil {
            // Stats arrived after the companion did, which is about as old as its saved state.
            state.stats.firstMet = store.firstSaved ?? now()
            persist()
        }
        snapshot.preferences = state.preferences
        snapshot.stats = state.stats
        refreshUnlockStatus()
        let clock = state.encounterClock ?? EncounterRules.fresh(at: now(), calendar: calendar, using: &rng)
        schedule = EncounterSchedule(clock: clock, activeSince: nil)
        refreshStash()
        await loadCompanion()
        startSampling()
    }

    /// Full screen sends a visitor away and holds the next one off.
    func setFullScreen(_ on: Bool) {
        guard on != fullScreen else { return }
        fullScreen = on
        if on, let encounter = snapshot.encounter {
            encounterLog.info("wild creature \(encounter.species.id, privacy: .public) left for full screen")
            endEncounter(encounter.serial)
        }
        refreshEncounters(secondsSinceInput: idleSeconds())
    }

    /// A sleeping Mac banks no active time. Waking starts a new stretch,
    /// so a deadline that passed overnight does not fire on wake.
    func setSystemAsleep(_ asleep: Bool) {
        guard asleep != systemAsleep else { return }
        systemAsleep = asleep
        refreshEncounters(secondsSinceInput: idleSeconds())
    }

    /// For developers: a visit now, whatever the schedule says. It does
    /// not count toward the day's visits.
    func spawnEncounterNow() async {
        await spawnEncounter(scheduled: false)
    }

    /// A click on the visitor. A family not yet in the collection joins at
    /// its first stage and the starting level; one already there was only
    /// seen again.
    func catchEncounter() {
        guard var encounter = snapshot.encounter, !encounter.caught else { return }
        encounter.caught = true
        snapshot.encounter = encounter
        let wild = encounter.species
        let root = wild.familyRoot ?? wild.id
        if state.collection.add(Partner(root: root, progress: .starter(root))) {
            encounterLog.info("caught wild creature \(wild.id, privacy: .public)")
            showBanner(.caught(wild.name))
            record(.encounterCaught)
        } else {
            encounterLog.info("wild creature \(wild.id, privacy: .public) seen again; its family is already a partner")
            showBanner(.seenAgain(wild.name))
            publish()
        }
    }

    /// The visitor left, or its catch finished playing.
    func endEncounter(_ serial: Int) {
        guard let encounter = snapshot.encounter, encounter.serial == serial else { return }
        visitTask?.cancel()
        snapshot.encounter = nil
        if !encounter.caught {
            encounterLog.info("wild creature \(encounter.species.id, privacy: .public) wandered off")
        }
        publish()
        refreshEncounters(secondsSinceInput: idleSeconds())
    }

    /// Starts or ends the active stretch when the conditions change, and
    /// with it the deadline the next visit waits for.
    private func refreshEncounters(secondsSinceInput: TimeInterval) {
        guard let current = schedule else { return }
        let active = EncounterRules.isActive(encounterConditions(secondsSinceInput: secondsSinceInput, visiting: snapshot.encounter != nil))
        // Midnight starts a new day's count even for a user who never pauses.
        let newDay = calendar.startOfDay(for: now()) != current.clock.day
        guard active != (current.activeSince != nil) || newDay else { return }
        schedule = EncounterRules.update(current, active: active, now: now(), calendar: calendar)
        saveEncounterClock()
        scheduleEncounter()
    }

    private func encounterConditions(secondsSinceInput: TimeInterval, visiting: Bool) -> EncounterConditions {
        EncounterConditions(
            secondsSinceInput: secondsSinceInput,
            sleeping: snapshot.behaviour == .sleeping,
            fullScreen: fullScreen,
            focusing: timer.session != nil,
            hasPartner: species != nil,
            visiting: visiting,
            systemAsleep: systemAsleep
        )
    }

    private func scheduleEncounter() {
        let deadline = schedule.flatMap(EncounterRules.deadline)
        guard deadline != encounterDeadline else { return }
        encounterTask?.cancel()
        encounterDeadline = deadline
        guard let deadline else { return }
        let wait = max(0, deadline.timeIntervalSince(now()))
        encounterLog.info("next wild creature in \(Int(wait), privacy: .public) s of active use")
        encounterTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.encounterDue()
        }
    }

    private func encounterDue() async {
        encounterDeadline = nil
        guard let current = schedule, let deadline = EncounterRules.deadline(current), now() >= deadline - 1 else {
            scheduleEncounter()
            return
        }
        await spawnEncounter(scheduled: true)
    }

    private func spawnEncounter(scheduled: Bool) async {
        guard species != nil, snapshot.encounter == nil, !spawning else { return }
        spawning = true
        defer { spawning = false }
        var draw = rng
        let candidate = try? await provider.encounterCandidate(using: &draw)
        // The search can take a while; the user may have gone, focused, or gone full screen meanwhile.
        let stillWanted = scheduled
            ? EncounterRules.isActive(encounterConditions(secondsSinceInput: idleSeconds(), visiting: snapshot.encounter != nil))
            : !fullScreen && !systemAsleep
        guard stillWanted, let candidate, let show = await wildShow(of: candidate), species != nil, snapshot.encounter == nil else {
            encounterLog.info("no visit this time; looking again later")
            if scheduled, var current = schedule {
                current = EncounterRules.update(current, active: current.activeSince != nil, now: now(), calendar: calendar)
                current.clock.cooldownLeft = Self.encounterRetry
                schedule = current
                saveEncounterClock()
                scheduleEncounter()
            }
            return
        }
        encounterSerial += 1
        let serial = encounterSerial
        snapshot.encounter = Encounter(serial: serial, species: candidate, show: show)
        if scheduled, let current = schedule {
            schedule = EncounterRules.visited(EncounterRules.update(current, active: false, now: now(), calendar: calendar), using: &rng)
        } else if let current = schedule {
            schedule = EncounterRules.update(current, active: false, now: now(), calendar: calendar)
        }
        saveEncounterClock()
        scheduleEncounter()
        encounterLog.info("wild creature \(candidate.id, privacy: .public) arrived")
        record(.encounterSeen)
        visitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visitLimit)
            guard !Task.isCancelled else { return }
            await self?.endEncounter(serial)
        }
    }

    /// Idle facing the viewer and a walk each way, measured on their own.
    private func wildShow(of wild: Species) async -> SpriteShow? {
        guard let idle = try? await provider.sprite(for: wild, state: .idle, facing: .down),
              let left = try? await provider.sprite(for: wild, state: .walking, facing: .left),
              let right = try? await provider.sprite(for: wild, state: .walking, facing: .right)
        else { return nil }
        let anims: [SpriteState: [Facing: SpriteFrames]] = [.idle: [.down: idle], .walking: [.left: left, .right: right]]
        return SpriteShow(
            loop: idle, loopState: .idle, playback: .cycle, facing: .down,
            bounds: SpriteRendering.bounds(rest: idle, anims: anims), oneShot: nil, walk: WalkCycle(left: left, right: right)
        )
    }

    private func saveEncounterClock() {
        state.encounterClock = schedule?.clock
        persist()
    }

    func starterOptions() async -> [PartnerOption] {
        await options(provider.starterIDs.map { OptionEntry(speciesId: $0, partner: nil) })
    }

    /// The partners in the order they joined, then the species of every
    /// open tier whose family is not among them yet. A partner the
    /// provider cannot show, such as one from another provider, is left out.
    func partnerOptions() async -> [PartnerOption] {
        let owned = state.collection.partners.map { OptionEntry(speciesId: $0.progress.speciesId, partner: $0) }
        let fresh = available().filter { !state.collection.owns($0) }.map { OptionEntry(speciesId: $0, partner: nil) }
        return await options(owned + fresh)
    }

    /// Species whose name contains `query`, or whose id it is, from
    /// everything the provider can show. Only with the override on.
    func searchOptions(_ query: String, limit: Int = 8) async -> [PartnerOption] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard unlockAll(), !needle.isEmpty else { return [] }
        let ids: [Int]
        if let id = Int(needle) {
            ids = [id]
        } else {
            if index == nil { index = try? await provider.speciesIndex() }
            ids = (index ?? []).filter { $0.name.lowercased().contains(needle) }.prefix(limit).map(\.id)
        }
        let found = await options(ids.map { OptionEntry(speciesId: $0, partner: nil) })
        return found.map { option in
            let partner = state.collection.partner(option.species.familyRoot ?? option.species.id)
            return PartnerOption(species: option.species, portrait: option.portrait, partner: partner)
        }
    }

    private func available() -> [Int] {
        UnlockRules.available(stats: state.stats, tiers: provider.unlockTiers, override: unlockAll())
    }

    /// Call when the override may have changed.
    func refreshUnlocks() {
        refreshUnlockStatus()
        publish()
    }

    private func refreshUnlockStatus() {
        let override = unlockAll()
        let tierCount = provider.unlockTiers.count
        snapshot.unlocks = UnlockStatus(
            openTiers: UnlockRules.openTiers(stats: state.stats, tierCount: tierCount, override: override),
            override: override,
            next: override ? nil : UnlockRules.next(stats: state.stats, tierCount: tierCount)?.threshold
        )
    }

    private struct OptionEntry: Sendable {
        let speciesId: Int
        let partner: Partner?
    }

    private func options(_ entries: [OptionEntry]) async -> [PartnerOption] {
        await withTaskGroup(of: (Int, PartnerOption?).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask { [provider] in
                    guard let species = try? await provider.species(id: entry.speciesId) else { return (index, nil) }
                    let portrait = try? await provider.portrait(for: species)
                    return (index, PartnerOption(species: species, portrait: portrait, partner: entry.partner))
                }
            }
            var options: [(Int, PartnerOption)] = []
            for await (index, option) in group {
                if let option { options.append((index, option)) }
            }
            return options.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Sends out species `id`: the partner of its family when there is one,
    /// else a new partner at the starting level. A starter chosen because
    /// the provider no longer knows the partner that was out inherits its
    /// level and XP.
    func adopt(_ id: Int) async {
        guard let chosen = try? await provider.species(id: id) else { return }
        let root = chosen.familyRoot ?? chosen.id
        if state.collection.owns(root) {
            await switchPartner(to: root)
            return
        }
        guard unlockAll() || available().contains(id) else { return }
        var progress = Progress.starter(id)
        if case .choosingStarter(let carryOver?) = snapshot.phase {
            progress.level = carryOver.level
            progress.xp = carryOver.xp
        }
        state.collection.add(Partner(root: root, progress: progress))
        state.collection.activate(root)
        state.stats.firstMet = state.stats.firstMet ?? now()
        snapshot.stats = state.stats
        persist()
        await sendOut(chosen)
    }

    /// Every partner keeps its own stage, level, and XP while another is out.
    func switchPartner(to root: Int) async {
        guard let partner = state.collection.partner(root), root != state.collection.active || species == nil else { return }
        guard let target = try? await provider.species(id: partner.progress.speciesId) else { return }
        // A follower sent out swaps with the leader, which then follows in
        // frames already loaded, so it never drops out of the party between.
        if let leader = state.collection.active, let species { followerSpecies[leader] = species }
        state.collection.activate(root)
        persist()
        await sendOut(target)
    }

    /// For developers: empties the collection, keeping the stats.
    func resetCollection() {
        cancelFocus()
        state.collection = PartnerCollection()
        species = nil
        followerSpecies = [:]
        snapshot.encounter = nil
        forgetUnshownSprites()
        persist()
        snapshot.sprite = nil
        snapshot.phase = .choosingStarter(carryOver: nil)
        publish()
    }

    /// For developers: a walk of one kilometre at the current partner's scale.
    func addCreatureKilometre() {
        guard let species, let leader = state.collection.active else { return }
        let perPoint = Distance.creatureMetresPerPoint(heightMetres: species.heightMetres)
        record(.walked(points: 1_000 / perPoint, perch: .topEdge, partner: leader))
    }

    /// For developers: an hour of focus, counted without XP.
    func addFocusHour() {
        record(.focusCompleted(minutes: 60))
    }

    /// A follower sent out swaps places with the leader, so the followers
    /// are loaded again after the new leader is.
    private func sendOut(_ next: Species) async {
        await activate(next)
        await resolvePendingEvolutions()
        await refreshFollowers()
    }

    func cursorMoved(offset: CursorOffset?) async {
        cursorOffset = offset
        if offset != nil { lastCursorNear = now() }
        await sample()
    }

    func cursorNoticed() async {
        guard let leader = state.collection.active else { return }
        record(.hopped(partner: leader))
        await play(.cursorNoticed)
    }

    /// Folds one event into the stats. A walk is measured in the walker's
    /// own body heights, and in millimetres of the display it crossed, and
    /// is added to that partner's own distance too.
    func record(_ event: CompanionEvent, screenMillimetresPerPoint: Double = 0) {
        guard species != nil else { return }
        let walker: Species? = event.partner.flatMap { member($0) }
        let scale = WalkScale(
            creatureMetresPerPoint: Distance.creatureMetresPerPoint(heightMetres: walker?.heightMetres),
            screenMillimetresPerPoint: screenMillimetresPerPoint
        )
        let next = StatsReducer.apply(event, to: state.stats, scale: scale)
        let walked = next.creatureMetres - state.stats.creatureMetres
        if walked > 0, let partner = event.partner { state.collection.update(partner) { $0.creatureMetres += walked } }
        state.stats = next
        snapshot.stats = next
        refreshUnlockStatus()
        statsLog.debug("folded \(String(describing: event), privacy: .public)")
        persist()
        publish()
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
            record(.focusCompleted(minutes: minutes))
            snapshot.completedFocusSessions += 1
            await award(outcome.xp)
        } else {
            publish()
        }
    }

    func award(_ xp: Int) async {
        guard let species, let progress = state.progress else { return }
        let (next, events) = XPRules.award(xp, to: progress, species: species)
        state.collection.updateActive { $0.progress = next }
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
            state.collection.updateActive { $0.progress.speciesId = targetID }
            persist()
            await activate(target)
            forgetUnshownSprites()
            snapshot.evolutionCount += 1
            record(.evolved)
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

    private func showBanner(_ banner: Banner, for length: Duration = CreatureEngine.bannerLength) {
        snapshot.banner = banner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: length)
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

    /// This and the clear and undo below return whether the stash changed.
    @discardableResult
    func removeFromStash(_ url: URL) async -> Bool {
        let left = FileStash.remove(url, from: state.stash, codec: bookmarks)
        guard left != state.stash else { return false }
        state.stash = left
        persist()
        refreshStash()
        publish()
        await sample()
        return true
    }

    @discardableResult
    func clearStash() async -> Bool {
        guard !state.stash.isEmpty else { return false }
        let cleared = state.stash
        state.stash = []
        persist()
        refreshStash()
        showBanner(.stashCleared(undo: cleared), for: Self.undoLength)
        publish()
        await sample()
        return true
    }

    @discardableResult
    func undoClearStash() async -> Bool {
        guard case .stashCleared(let cleared) = snapshot.banner else { return false }
        let result = FileStash.restore(cleared, into: state.stash, capacity: CompanionState.stashCapacity, codec: bookmarks)
        state.stash = result.bookmarks
        persist()
        refreshStash()
        if result.refused > 0 {
            showBanner(.stashFull)
        } else {
            bannerTask?.cancel()
            snapshot.banner = nil
        }
        publish()
        await sample()
        return true
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
        let idle = idleSeconds()
        let inputs = BehaviourInputs(
            secondsSinceInput: idle,
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
            if behaviour == .sleeping { record(.napped) }
            snapshot.behaviour = behaviour
            await refreshLoop()
            publish()
            await play(.behaviourChanged(from: previous, to: behaviour))
        }
        refreshEncounters(secondsSinceInput: idle)
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
            if let root = loaded.familyRoot, let active = state.collection.active, root != active {
                state.collection.rekey(active, to: root)
                persist()
            }
            await activate(loaded)
            await resolvePendingEvolutions()
            await refreshFollowers()
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
        guard let set = await spriteSet(of: species), self.species?.id == species.id,
              snapshot.behaviour == behaviour, state.preferences.idleStyle == style,
              var show = set.show(for: behaviour, style: style)
        else { return }
        show.oneShot = snapshot.sprite?.oneShot
        snapshot.sprite = show
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

    /// Frames are cached per species, for every party member at once, and
    /// a request for frames already being fetched waits for that fetch.
    private func frames(_ state: SpriteState, facing: Facing, of species: Species) async -> SpriteFrames? {
        let key = SpriteKey(species: species.id, state: state, facing: facing)
        if let hit = spriteCache[key] { return hit }
        if let fetch = spriteFetches[key] { return await fetch.value }
        // The task caches what it fetched on this actor before anyone waiting
        // on it resumes, so none of them asks again for a facing it covers.
        let fetch = Task { [self, provider] () -> SpriteFrames? in
            let fetched = try? await provider.sprite(for: species, state: state, facing: facing)
            spriteFetches[key] = nil
            guard let fetched, isShown(species.id) else { return nil }
            // Undirected frames are the same from every side, so one fetch serves all eight.
            for cached in fetched.directional ? [facing] : Facing.allCases {
                spriteCache[SpriteKey(species: species.id, state: state, facing: cached)] = fetched
            }
            return fetched
        }
        spriteFetches[key] = fetch
        return await fetch.value
    }

    /// Fetches every anim in every facing the creature shows, so the bounds
    /// cover a hop before it first plays and its one-shots are cached ahead.
    private func spriteSet(of species: Species) async -> SpriteSet? {
        if let set = spriteSets[species.id] { return set }
        guard let rest = await frames(.idle, facing: .down, of: species) else { return nil }
        var anims: [SpriteState: [Facing: SpriteFrames]] = [:]
        for state in SpriteState.allCases {
            for facing in Facing.front {
                anims[state, default: [:]][facing] = await frames(state, facing: facing, of: species)
            }
        }
        guard isShown(species.id) else { return nil }
        let set = SpriteSet(bounds: SpriteRendering.bounds(rest: rest, anims: anims), anims: anims)
        spriteSets[species.id] = set
        return set
    }

    /// Whether the leader or a follower is of species `id`, so its frames are worth keeping.
    private func isShown(_ id: Int) -> Bool {
        species?.id == id || followerSpecies.values.contains { $0.id == id }
    }

    /// Drops the frames of every species no party member is.
    private func forgetUnshownSprites() {
        spriteCache = spriteCache.filter { isShown($0.key.species) }
        spriteSets = spriteSets.filter { isShown($0.key) }
    }

    /// Starts or stops partner `root` walking with the leader, then loads
    /// what it is drawn in. Refused when the party is full.
    func setWalking(_ root: Int, _ walking: Bool) async -> WalkingChange {
        let change = state.collection.setWalking(root, walking)
        guard change == .changed else { return change }
        persist()
        publish()
        await refreshFollowers()
        return change
    }

    /// Loads each follower's species and frames, forgets those of partners
    /// that stopped walking, and publishes the followers that can be drawn.
    /// It repeats until the party holds still across its fetches, so calls
    /// that overlap all end on the same followers.
    private func refreshFollowers() async {
        while true {
            let roots = state.collection.followers
            followerSpecies = followerSpecies.filter { roots.contains($0.key) }
            for root in roots {
                guard let partner = state.collection.partner(root) else { continue }
                let wanted = partner.progress.speciesId
                if followerSpecies[root]?.id != wanted {
                    guard let found = try? await provider.species(id: wanted) else { continue }
                    followerSpecies[root] = found
                }
                if let species = followerSpecies[root] { _ = await spriteSet(of: species) }
            }
            guard state.collection.followers == roots else { continue }
            forgetUnshownSprites()
            publish()
            return
        }
    }

    /// The followers whose current species and frames are loaded, in party order.
    private func loadedFollowers() -> [Follower] {
        state.collection.followers.compactMap { (root: Int) -> Follower? in
            guard let species = followerSpecies[root], species.id == state.collection.partner(root)?.progress.speciesId,
                  let sprites = spriteSets[species.id]
            else { return nil }
            return Follower(root: root, species: species, sprites: sprites)
        }
    }

    /// The species of party member `root`, while it walks.
    private func member(_ root: Int) -> Species? {
        root == state.collection.active ? species : followerSpecies[root]
    }

    private struct SpriteKey: Hashable {
        let species: Int
        let state: SpriteState
        let facing: Facing
    }

    private func persist() {
        try? store.save(state)
    }

    private func publish() {
        snapshot.leader = species == nil ? nil : state.collection.active
        snapshot.followerRoots = state.collection.followers
        snapshot.followers = loadedFollowers()
        continuation.yield(snapshot)
    }
}

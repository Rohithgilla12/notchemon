import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

/// testmon (901) levels into testmid (902) at 6, which levels into testmax
/// (903) at 7. 904 never evolves.
struct FakeProvider: CreatureProvider {
    let starterIDs = [901, 904]
    let roster: [Int: Species] = [
        901: Species(id: 901, name: "Testmon", evolvesTo: 902, evolvesAtLevel: 6),
        902: Species(id: 902, name: "Testmid", evolvesTo: 903, evolvesAtLevel: 7),
        903: Species(id: 903, name: "Testmax", evolvesTo: nil, evolvesAtLevel: nil),
        904: Species(id: 904, name: "Testsolo", evolvesTo: nil, evolvesAtLevel: nil),
    ]

    func species(id: Int) async throws -> Species {
        guard let species = roster[id] else { throw CreatureError.unknownSpecies }
        return species
    }

    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        SpriteFrames(frames: [Self.image()], durations: [0.1])
    }

    func portrait(for species: Species) async throws -> CGImage {
        Self.image()
    }

    static func image() -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}

/// Serves directional frames and records every sprite request.
final class RecordingProvider: CreatureProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    let starterIDs = [904]

    var requests: [String] { lock.withLock { recorded } }

    func species(id: Int) async throws -> Species {
        try await FakeProvider().species(id: id)
    }

    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        lock.withLock { recorded.append("\(state)/\(facing)") }
        return SpriteFrames(frames: [FakeProvider.image()], durations: [0.1], directional: true, loops: state == .idle || state == .sleeping)
    }

    func portrait(for species: Species) async throws -> CGImage {
        FakeProvider.image()
    }
}

final class IdleClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval = 0

    var seconds: TimeInterval {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

struct EngineTests {
    let clock = TestClock()
    let directory = Fixtures.temporaryDirectory()
    var store: StateStore { StateStore(url: directory.appendingPathComponent("state.json")) }

    func engine(sessionSeconds: TimeInterval? = nil, provider: any CreatureProvider = FakeProvider()) -> CreatureEngine {
        CreatureEngine(
            provider: provider,
            store: store,
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 },
            now: { [clock] in clock.now },
            sessionSecondsOverride: sessionSeconds
        )
    }

    func started(_ engine: CreatureEngine, choosing starter: Int = 901) async -> CreatureEngine {
        await engine.start()
        await engine.chooseStarter(starter)
        return engine
    }

    @Test func firstLaunchAsksForAStarterAndPersistsTheChoice() async {
        let engine = engine()
        await engine.start()
        #expect(await engine.currentSnapshot.phase == .choosingStarter(carryOver: nil))
        await engine.chooseStarter(904)
        #expect(store.load().progress == .starter(904))
        #expect(await engine.currentSnapshot.phase == .active(FakeProvider().roster[904]!, .starter(904)))
    }

    @Test func completedSessionAwardsXPAndFocusMinutes() async {
        let engine = await started(engine())
        await engine.startFocus()
        clock.advance(25 * 60)
        await engine.stopFocus()
        let saved = store.load()
        #expect(saved.progress?.xp == 100)
        #expect(saved.totalFocusMinutes == 25)
        #expect(await engine.currentSnapshot.focus == nil)
    }

    @Test func abandonedSessionAwardsNothing() async {
        let engine = await started(engine())
        await engine.startFocus()
        clock.advance(24 * 60)
        await engine.stopFocus()
        #expect(store.load().progress == .starter(901))
        #expect(store.load().totalFocusMinutes == 0)
    }

    @Test func debugSessionLengthCompletesOnItsOwnAndCreditsFullLength() async throws {
        let engine = await started(engine(sessionSeconds: 0.05))
        await engine.startFocus()
        clock.advance(1)
        for _ in 0..<100 where store.load().progress?.xp != 100 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.load().progress?.xp == 100)
    }

    @Test func levelUpCelebratesAndShowsBanner() async {
        let engine = await started(engine(), choosing: 904)
        await engine.award(200)
        let snapshot = await engine.currentSnapshot
        #expect(snapshot.banner == .levelUp(6))
        #expect(snapshot.behaviour == .celebrating(.levelUp(6)))
    }

    @Test func evolutionChainsThroughEveryStageTheLevelAllows() async {
        let engine = await started(engine())
        await engine.award(200 + 240)
        let snapshot = await engine.currentSnapshot
        #expect(store.load().progress?.speciesId == 903)
        #expect(store.load().progress?.level == 7)
        #expect(snapshot.evolutionCount == 2)
        guard case .evolved(let name, let portrait) = snapshot.banner else {
            Issue.record("expected an evolution banner, got \(String(describing: snapshot.banner))")
            return
        }
        #expect(name == "Testmax")
        #expect(portrait != nil)
    }

    @Test func unknownSavedSpeciesOffersStartersAndKeepsLevel() async {
        try? store.save(CompanionState(progress: Progress(speciesId: 4242, level: 12, xp: 30), totalFocusMinutes: 0, lastInteraction: .distantPast, stash: []))
        let engine = engine()
        await engine.start()
        #expect(await engine.currentSnapshot.phase == .choosingStarter(carryOver: Progress(speciesId: 4242, level: 12, xp: 30)))
        await engine.chooseStarter(904)
        #expect(store.load().progress == Progress(speciesId: 904, level: 12, xp: 30))
    }

    @Test func repickingResetsProgress() async {
        let engine = await started(engine(), choosing: 904)
        await engine.award(150)
        await engine.resetForNewStarter()
        #expect(store.load().progress == nil)
        #expect(await engine.currentSnapshot.phase == .choosingStarter(carryOver: nil))
    }

    @Test func watchingSwapsToTheFacingRowAndFetchesEachRowOnce() async throws {
        let provider = RecordingProvider()
        let engine = await started(engine(provider: provider), choosing: 904)
        await engine.cursorMoved(offset: CursorOffset(dx: -60, dy: -60))
        let watching = await engine.currentSnapshot
        #expect(watching.behaviour == .watching(facing: .downLeft))
        #expect(watching.sprite?.facing == .downLeft)
        await engine.cursorMoved(offset: CursorOffset(dx: 60, dy: -60))
        await engine.cursorMoved(offset: CursorOffset(dx: -60, dy: -60))
        #expect(await engine.currentSnapshot.sprite?.facing == .downLeft)
        #expect(provider.requests == ["idle/down", "idle/downLeft", "idle/downRight"])
    }

    @Test func cursorEnteringTheNotchPlaysHopOverTheLoop() async throws {
        let engine = await started(engine(provider: RecordingProvider()), choosing: 904)
        await engine.cursorEnteredNotch()
        let first = try #require(await engine.currentSnapshot.sprite?.oneShot)
        #expect(first.state == .hop)
        #expect(!first.frames.loops)
        await engine.cursorEnteredNotch()
        #expect(await engine.currentSnapshot.sprite?.oneShot?.serial == first.serial + 1)
    }

    @Test func fallingAsleepLoopsSleepAndWakingPlaysWake() async throws {
        let idle = IdleClock()
        let provider = RecordingProvider()
        let engine = CreatureEngine(
            provider: provider,
            store: store,
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { idle.seconds },
            now: { [clock] in clock.now },
            sleepAfter: 5
        )
        await engine.start()
        await engine.chooseStarter(904)
        idle.seconds = 6
        await engine.sample()
        let asleep = await engine.currentSnapshot
        #expect(asleep.behaviour == .sleeping)
        #expect(asleep.sprite?.oneShot == nil)
        #expect(provider.requests.last == "sleeping/down")
        idle.seconds = 0
        await engine.sample()
        #expect(await engine.currentSnapshot.sprite?.oneShot?.state == .wake)
    }

    @Test func levelUpPlaysTheCelebrationOneShot() async {
        let engine = await started(engine(provider: RecordingProvider()), choosing: 904)
        await engine.award(200)
        #expect(await engine.currentSnapshot.sprite?.oneShot?.state == .celebrating)
    }

    @Test func notesAppendToTheNotesFile() async throws {
        let engine = await started(engine())
        #expect(await engine.appendNote("buy milk"))
        #expect(await !engine.appendNote("   "))
        let text = try String(contentsOf: directory.appendingPathComponent("notes.md"), encoding: .utf8)
        #expect(text.hasSuffix("buy milk\n"))
        #expect(text.components(separatedBy: "\n").count == 2)
    }
}

struct StateStoreTests {
    let store = StateStore(url: Fixtures.temporaryDirectory().appendingPathComponent("state.json"))

    @Test func roundTripsEveryField() throws {
        let state = CompanionState(
            progress: Progress(speciesId: 7, level: 9, xp: 120),
            totalFocusMinutes: 300,
            lastInteraction: Date(timeIntervalSince1970: 1_800_000_000),
            stash: [Data([1, 2, 3])],
            preferences: Preferences(focusMinutes: 45, sleepEnabled: false, virtualNotchEnabled: false)
        )
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func missingFileIsAFirstLaunch() {
        #expect(store.load() == .empty)
    }

    @Test func fileWithoutPreferencesGetsDefaults() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"progress":{"speciesId":1,"level":5,"xp":0},"totalFocusMinutes":0,"lastInteraction":"2026-01-01T00:00:00Z","stash":[]}"#.utf8).write(to: store.url)
        let loaded = store.load()
        #expect(loaded.progress == .starter(1))
        #expect(loaded.preferences == Preferences())
    }

    @Test func corruptFileIsSetAsideAndStartsFresh() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.url)
        #expect(store.load() == .empty)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.hasPrefix("state.corrupt-") })
    }
}

struct FocusTimerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func stoppingAtOrAfterTheEndCompletes() {
        var timer = FocusTimer()
        timer.start(at: start, duration: 1500, creditedMinutes: 25)
        #expect(timer.stop(at: start + 1500) == .completed(minutes: 25))
        #expect(timer.session == nil)
    }

    @Test func stoppingEarlyAbandonsForZeroXP() {
        var timer = FocusTimer()
        timer.start(at: start, duration: 1500, creditedMinutes: 25)
        let outcome = timer.stop(at: start + 1499)
        #expect(outcome == .abandoned)
        #expect(outcome?.xp == 0)
    }

    @Test func finishIfDueOnlyFiresAfterTheEnd() {
        var timer = FocusTimer()
        timer.start(at: start, duration: 60, creditedMinutes: 25)
        #expect(timer.finishIfDue(at: start + 59) == nil)
        #expect(timer.session != nil)
        #expect(timer.finishIfDue(at: start + 60) == .completed(minutes: 25))
    }

    @Test func debugLengthStillCreditsConfiguredMinutes() {
        var timer = FocusTimer()
        timer.start(at: start, duration: 5, creditedMinutes: 25)
        #expect(timer.stop(at: start + 5)?.xp == 100)
    }

    @Test func startingTwiceKeepsTheRunningSession() {
        var timer = FocusTimer()
        let first = timer.start(at: start, duration: 60, creditedMinutes: 25)
        let second = timer.start(at: start + 10, duration: 90, creditedMinutes: 45)
        #expect(first == second)
    }

    @Test func remainingFractionDrainsToZero() {
        let session = FocusSession(startedAt: start, duration: 100, creditedMinutes: 25)
        #expect(session.remainingFraction(at: start) == 1)
        #expect(session.remainingFraction(at: start + 25) == 0.75)
        #expect(session.remainingFraction(at: start + 500) == 0)
    }
}

struct QuickNoteTests {
    let utc = TimeZone(identifier: "UTC")!
    let date = Date(timeIntervalSince1970: 1_791_376_800)

    @Test func formatsTimestampedMarkdownBullet() {
        #expect(QuickNote.line(for: "ship it", at: date, timeZone: utc) == "- [2026-10-07 12:40] ship it")
    }

    @Test func flattensNewlinesAndTrims() {
        #expect(QuickNote.line(for: "  one\n\n two  ", at: date, timeZone: utc) == "- [2026-10-07 12:40] one two")
    }

    @Test func blankInputWritesNothing() throws {
        let url = Fixtures.temporaryDirectory().appendingPathComponent("notes.md")
        #expect(QuickNote.line(for: " \n ", at: date) == nil)
        #expect(try !QuickNote.append("   ", at: date, to: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func appendsOneLinePerNoteEvenIfFileLacksTrailingNewline() throws {
        let url = Fixtures.temporaryDirectory().appendingPathComponent("notes.md")
        try QuickNote.append("first", at: date, to: url, timeZone: utc)
        try Data("handwritten".utf8).write(to: url, options: .atomic)
        try QuickNote.append("second", at: date, to: url, timeZone: utc)
        #expect(try String(contentsOf: url, encoding: .utf8) == "handwritten\n- [2026-10-07 12:40] second\n")
    }
}

struct FileStashTests {
    /// Bookmarks are just the path bytes; files listed in `missing` no longer resolve.
    struct PathCodec: BookmarkCodec {
        var missing: Set<String> = []
        func bookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
        func resolve(_ bookmark: Data) -> URL? {
            let path = String(decoding: bookmark, as: UTF8.self)
            return missing.contains(path) ? nil : URL(fileURLWithPath: path)
        }
    }

    func urls(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }

    @Test func addsUntilFullThenRefuses() {
        let result = FileStash.add(urls("a", "b", "c", "d", "e", "f", "g"), to: [], capacity: 5, codec: PathCodec())
        #expect(result.added == 5)
        #expect(result.refused == 2)
        #expect(result.bookmarks.count == 5)
    }

    @Test func fileAlreadyHeldIsNeitherAddedNorRefused() {
        let first = FileStash.add(urls("a"), to: [], capacity: 5, codec: PathCodec())
        let again = FileStash.add(urls("a"), to: first.bookmarks, capacity: 5, codec: PathCodec())
        #expect(again == StashAddResult(bookmarks: first.bookmarks, added: 0, refused: 0))
    }

    @Test func removingDropsOnlyThatFile() {
        let held = FileStash.add(urls("a", "b"), to: [], capacity: 5, codec: PathCodec()).bookmarks
        let left = FileStash.remove(urls("a")[0], from: held, codec: PathCodec())
        #expect(FileStash.items(left, codec: PathCodec()).items.map(\.name) == ["b"])
    }

    @Test func vanishedFilesHealOutOfTheStash() {
        let held = FileStash.add(urls("a", "b"), to: [], capacity: 5, codec: PathCodec()).bookmarks
        let (items, live) = FileStash.items(held, codec: PathCodec(missing: ["/tmp/a"]))
        #expect(items.map(\.name) == ["b"])
        #expect(live.count == 1)
    }
}

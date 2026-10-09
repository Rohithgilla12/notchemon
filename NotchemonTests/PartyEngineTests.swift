import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

/// Three starters of known heights, plus one more the unlock override
/// opens. Records every sprite request with its species.
final class PartyProvider: CreatureProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var lookedUp: [Int] = []
    private let directional: Bool
    let starterIDs = [11, 12, 13]
    let roster: [Int: Species] = [
        11: Species(id: 11, name: "Tallmon", evolvesTo: nil, evolvesAtLevel: nil, heightMetres: 2),
        12: Species(id: 12, name: "Midmon", evolvesTo: nil, evolvesAtLevel: nil, heightMetres: 1),
        13: Species(id: 13, name: "Smallmon", evolvesTo: nil, evolvesAtLevel: nil, heightMetres: 0.5),
    ]

    /// Undirected frames are drawn once for every facing.
    init(directional: Bool = true) {
        self.directional = directional
    }

    var requests: [String] { lock.withLock { recorded } }
    var lookups: [Int] { lock.withLock { lookedUp } }

    func species(id: Int) async throws -> Species {
        lock.withLock { lookedUp.append(id) }
        guard let species = roster[id] else { throw CreatureError.unknownSpecies }
        return species
    }

    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        lock.withLock { recorded.append("\(species.id)/\(state)/\(facing)") }
        // A real fetch suspends, which is when a second request can join it.
        await Task.yield()
        return SpriteFrames(frames: [FakeProvider.image()], durations: [0.1], directional: directional, loops: state.loops)
    }

    func portrait(for species: Species) async throws -> CGImage {
        FakeProvider.image()
    }
}

struct PartyEngineTests {
    let clock = TestClock()
    let directory = Fixtures.temporaryDirectory()
    var store: StateStore { StateStore(url: directory.appendingPathComponent("state.json")) }

    func engine(_ provider: any CreatureProvider) -> CreatureEngine {
        CreatureEngine(
            provider: provider,
            store: store,
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 },
            now: { [clock] in clock.now }
        )
    }

    /// 13 leads; 11 and 12 are partners too.
    func threePartners(_ provider: PartyProvider = PartyProvider()) async -> CreatureEngine {
        let engine = engine(provider)
        await engine.start()
        await engine.adopt(11)
        await engine.adopt(12)
        await engine.adopt(13)
        return engine
    }

    @Test func aWalkingPartnerIsLoadedAndPublishedAsAFollower() async throws {
        let engine = await threePartners()
        #expect(await engine.setWalking(11, true) == .changed)
        let snapshot = await engine.currentSnapshot
        #expect(snapshot.leader == 13)
        #expect(snapshot.followerRoots == [11])
        let follower = try #require(snapshot.followers.first)
        #expect(follower.root == 11)
        #expect(follower.species.id == 11)
        #expect(follower.sprites.walk != nil)
        #expect(store.load().collection.followers == [11])
    }

    @Test func aRelaunchBringsTheSameFollowersBack() async {
        let first = await threePartners()
        _ = await first.setWalking(12, true)
        _ = await first.setWalking(11, true)
        let second = engine(PartyProvider())
        await second.start()
        let snapshot = await second.currentSnapshot
        #expect(snapshot.followerRoots == [12, 11])
        #expect(snapshot.followers.map(\.root) == [12, 11])
    }

    @Test func stoppingAFollowerDropsItAndAFullPartyRefusesAnother() async {
        let engine = engine(PartyProvider())
        await engine.start()
        await engine.adopt(11)
        _ = await engine.setWalking(11, false)
        #expect(await engine.setWalking(11, true) == .unchanged)
        let party = await threePartners()
        #expect(await party.setWalking(11, true) == .changed)
        #expect(await party.setWalking(12, true) == .changed)
        #expect(await party.setWalking(12, false) == .changed)
        #expect(await party.currentSnapshot.followers.map(\.root) == [11])
    }

    @Test(arguments: [true, false])
    func eachSpeciesFramesAreFetchedOnceAcrossTheWholeParty(directional: Bool) async {
        let provider = PartyProvider(directional: directional)
        let engine = await threePartners(provider)
        let start = provider.requests.count
        async let first = engine.setWalking(11, true)
        async let second = engine.setWalking(12, true)
        _ = await (first, second)
        let loaded = provider.requests.count
        let looked = provider.lookups.count
        await engine.switchPartner(to: 11)
        let snapshot = await engine.currentSnapshot
        #expect(snapshot.leader == 11)
        #expect(snapshot.followerRoots == [13, 12])
        #expect(snapshot.followers.map(\.root) == [13, 12])
        #expect(provider.requests.count == loaded, "a swap fetches nothing new")
        #expect(Array(provider.lookups[looked...]) == [11], "the old leader follows in the species it already had")
        let party: [String] = Array(provider.requests[start...])
        #expect(party.count == Set(party).count, "no frames fetched twice")
        #expect(Set(party.map { $0.prefix(3) }) == ["11/", "12/"])
    }

    @Test func framesOfAPartnerThatStopsWalkingAreForgotten() async {
        let provider = PartyProvider()
        let engine = await threePartners(provider)
        _ = await engine.setWalking(11, true)
        _ = await engine.setWalking(11, false)
        let before = provider.requests.count
        _ = await engine.setWalking(11, true)
        #expect(provider.requests.count > before)
    }

    @Test func aFollowersWalkFoldsIntoTheStatsAndItsOwnDistanceAtItsOwnHeight() async {
        let engine = await threePartners()
        _ = await engine.setWalking(11, true)
        await engine.record(.walked(points: 80, perch: .topEdge, partner: 11))
        await engine.record(.walked(points: 80, perch: .dock, partner: 13))
        await engine.record(.hopped(partner: 11))
        await engine.record(.transferred(to: .dock, partner: 11))
        let state = store.load()
        let tall = 80 * Distance.creatureMetresPerPoint(heightMetres: 2)
        let small = 80 * Distance.creatureMetresPerPoint(heightMetres: 0.5)
        #expect(abs((state.collection.partner(11)?.creatureMetres ?? 0) - tall) < 1e-9)
        #expect(abs((state.collection.partner(13)?.creatureMetres ?? 0) - small) < 1e-9)
        #expect(state.collection.partner(12)?.creatureMetres == 0)
        #expect(abs(state.stats.creatureMetres - (tall + small)) < 1e-9)
        #expect(state.stats.topEdgePoints == 80)
        #expect(state.stats.dockPoints == 80)
        #expect(state.stats.hops == 1)
        #expect(state.stats.dockVisits == 1)
    }

    @Test func resettingTheCollectionSendsTheFollowersHomeToo() async {
        let engine = await threePartners()
        _ = await engine.setWalking(11, true)
        await engine.resetCollection()
        let snapshot = await engine.currentSnapshot
        #expect(snapshot.leader == nil)
        #expect(snapshot.followerRoots.isEmpty)
        #expect(snapshot.followers.isEmpty)
    }

    @Test func aFollowerTheProviderCannotShowStaysInThePartyUndrawn() async throws {
        var collection = PartnerCollection(only: .starter(13))
        collection.add(Partner(root: 4242, progress: .starter(4242)))
        #expect(collection.setWalking(4242, true) == .changed)
        try store.save(CompanionState(collection: collection))
        let engine = engine(PartyProvider())
        await engine.start()
        let snapshot = await engine.currentSnapshot
        #expect(snapshot.leader == 13)
        #expect(snapshot.followerRoots == [4242])
        #expect(snapshot.followers.isEmpty)
    }
}

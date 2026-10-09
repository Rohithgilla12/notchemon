import Foundation
import Testing
@testable import Notchemon

struct PartnerCollectionTests {
    @Test func aFamilyJoinsOnce() {
        var collection = PartnerCollection(only: .starter(25))
        let again = collection.add(Partner(root: 25, progress: Progress(speciesId: 26, level: 40, xp: 0)))
        let fresh = collection.add(Partner(root: 1, progress: .starter(1)))
        #expect(!again)
        #expect(fresh)
        #expect(collection.partners.map(\.root) == [25, 1])
        #expect(collection.partner(25)?.progress == .starter(25))
    }

    @Test func onlyAPartnerCanBeSentOut() {
        var collection = PartnerCollection(only: .starter(25))
        collection.activate(7)
        #expect(collection.active == 25)
    }

    @Test func changesReachOnlyThePartnerThatIsOut() {
        var collection = PartnerCollection(only: .starter(25))
        collection.add(Partner(root: 1, progress: .starter(1)))
        collection.activate(1)
        collection.updateActive { $0.progress.level = 9 }
        #expect(collection.partner(1)?.progress.level == 9)
        #expect(collection.partner(25)?.progress.level == XPRules.startingLevel)
    }

    @Test func rekeyingMovesAPartnerToItsFamilysFirstStage() {
        var collection = PartnerCollection(only: Progress(speciesId: 26, level: 30, xp: 0))
        collection.rekey(26, to: 25)
        #expect(collection.partners.map(\.root) == [25])
        #expect(collection.active == 25)
        #expect(collection.activePartner?.progress.speciesId == 26)
    }

    @Test func rekeyingOntoAFamilyAlreadyHereKeepsTheOneFurtherAlong() {
        var collection = PartnerCollection(only: Progress(speciesId: 26, level: 30, xp: 0))
        collection.add(Partner(root: 25, progress: .starter(25)))
        collection.rekey(26, to: 25)
        #expect(collection.partners.count == 1)
        #expect(collection.partner(25)?.progress.level == 30)
        #expect(collection.active == 25)
    }

    func fourPartners() -> PartnerCollection {
        var collection = PartnerCollection(only: .starter(25))
        for root in [1, 4, 7] {
            collection.add(Partner(root: root, progress: .starter(root)))
        }
        return collection
    }

    @Test func upToTwoPartnersWalkWithTheLeaderAndAThirdIsRefused() {
        var collection = fourPartners()
        #expect(collection.setWalking(1, true) == .changed)
        #expect(collection.setWalking(4, true) == .changed)
        #expect(collection.setWalking(7, true) == .partyFull)
        #expect(collection.followers == [1, 4])
        #expect(collection.party == [25, 1, 4])
        #expect(collection.setWalking(1, false) == .changed)
        #expect(collection.setWalking(7, true) == .changed)
        #expect(collection.followers == [4, 7])
    }

    @Test func theLeaderAndStrangersCannotBeToggled() {
        var collection = fourPartners()
        #expect(collection.setWalking(25, false) == .unchanged)
        #expect(collection.setWalking(25, true) == .unchanged)
        #expect(collection.setWalking(99, true) == .unchanged)
        #expect(collection.setWalking(1, false) == .unchanged)
        #expect(collection.party == [25])
    }

    @Test func sendingOutAFollowerSwapsItWithTheLeader() {
        var collection = fourPartners()
        _ = collection.setWalking(1, true)
        _ = collection.setWalking(4, true)
        collection.activate(4)
        #expect(collection.party == [4, 1, 25])
        collection.activate(7)
        #expect(collection.party == [7, 1, 25])
    }

    @Test func followersFollowARekeyAndNeverDuplicateTheLeader() {
        var collection = fourPartners()
        _ = collection.setWalking(1, true)
        collection.rekey(1, to: 2)
        #expect(collection.followers == [2])
        collection.rekey(2, to: 25)
        #expect(collection.followers.isEmpty)
        #expect(collection.active == 25)
    }

    @Test func followersRoundTripAndAFileWithoutThemHasNone() throws {
        var collection = fourPartners()
        _ = collection.setWalking(7, true)
        _ = collection.setWalking(1, true)
        let saved = try JSONEncoder().encode(collection)
        #expect(try JSONDecoder().decode(PartnerCollection.self, from: saved).followers == [7, 1])
        let old = #"{"partners":[{"root":1,"progress":{"speciesId":1,"level":8}}],"active":1}"#
        #expect(try JSONDecoder().decode(PartnerCollection.self, from: Data(old.utf8)).followers.isEmpty)
    }

    @Test func savedFollowersThatCannotWalkAreDropped() throws {
        let json = """
        {"partners":[{"root":1,"progress":{"speciesId":1}},{"root":4,"progress":{"speciesId":4}},
         {"root":7,"progress":{"speciesId":7}},{"root":9,"progress":{"speciesId":9}}],
         "active":1,"followers":[1,42,4,4,7,9]}
        """
        let collection = try JSONDecoder().decode(PartnerCollection.self, from: Data(json.utf8))
        #expect(collection.followers == [4, 7])
        let garbled = #"{"partners":[{"root":1,"progress":{"speciesId":1}}],"active":1,"followers":"lots"}"#
        let kept = try JSONDecoder().decode(PartnerCollection.self, from: Data(garbled.utf8))
        #expect(kept.followers.isEmpty)
        #expect(kept.active == 1)
    }

    @Test func anUnreadablePartnerIsDroppedAndTheRestKept() throws {
        let json = #"{"partners":[{"root":1,"progress":{"speciesId":1,"level":8}},{"root":4},{"root":1,"progress":{"speciesId":2}}],"active":4}"#
        let collection = try JSONDecoder().decode(PartnerCollection.self, from: Data(json.utf8))
        #expect(collection.partners == [Partner(root: 1, progress: Progress(speciesId: 1, level: 8, xp: 0))])
        #expect(collection.active == 1)
    }
}

/// The state file 0.2.3 writes, in the shape `StateStore` saves it.
enum StateFixtures {
    static let v023 = """
    {
      "preferences" : {
        "clickToOpen" : false,
        "fidgets" : true,
        "focusMinutes" : 25,
        "focusSound" : "off",
        "hopsOnApproach" : true,
        "idleStyle" : "calm",
        "sleepEnabled" : true,
        "virtualNotchEnabled" : true,
        "wander" : "topEdgeAndDock"
      },
      "progress" : {
        "level" : 5,
        "speciesId" : 25,
        "xp" : 100
      },
      "stash" : [

      ],
      "totalFocusMinutes" : 25
    }
    """

    /// The same companion after the stats release, before the collection.
    static let withStats = """
    {"preferences":{"focusMinutes":45},"progress":{"level":12,"speciesId":5,"xp":40},"stash":[],"stats":{"focusMinutes":300,"focusSessions":12,"hops":7}}
    """
}

struct CollectionMigrationTests {
    let directory = Fixtures.temporaryDirectory()
    var store: StateStore { StateStore(url: directory.appendingPathComponent("state.json")) }

    func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.url)
    }

    @Test func theOneCompanionOf023BecomesTheFirstPartner() throws {
        try write(StateFixtures.v023)
        let state = store.load()
        #expect(state.collection.partners == [Partner(root: 25, progress: Progress(speciesId: 25, level: 5, xp: 100))])
        #expect(state.collection.active == 25)
        #expect(state.stats.focusMinutes == 25)
        #expect(state.preferences == Preferences())
    }

    @Test func aCompanionWithStatsKeepsThemAsItJoins() throws {
        try write(StateFixtures.withStats)
        let state = store.load()
        #expect(state.progress == Progress(speciesId: 5, level: 12, xp: 40))
        #expect(state.stats == Stats(hops: 7, focusSessions: 12, focusMinutes: 300))
        #expect(state.preferences.focusMinutes == 45)
    }

    @Test func theOldFileIsBackedUpOnceBeforeTheNewFormatIsSaved() throws {
        try write(StateFixtures.v023)
        var state = store.load()
        #expect(try Data(contentsOf: store.v1Backup) == Data(StateFixtures.v023.utf8))
        state.collection.updateActive { $0.progress.level = 6 }
        try store.save(state)
        #expect(!StateStore.predatesCollection(try Data(contentsOf: store.url)))
        try write(StateFixtures.withStats)
        _ = store.load()
        #expect(try Data(contentsOf: store.v1Backup) == Data(StateFixtures.v023.utf8))
    }

    @Test func aStateInTheNewFormatIsNeverBackedUp() throws {
        try store.save(CompanionState(collection: PartnerCollection(only: .starter(1))))
        _ = store.load()
        #expect(!FileManager.default.fileExists(atPath: store.v1Backup.path))
    }

    @Test func aFirstLaunchIsNeverBackedUp() {
        _ = store.load()
        #expect(!FileManager.default.fileExists(atPath: store.v1Backup.path))
    }
}

struct EngineCollectionTests {
    let clock = TestClock()
    let directory = Fixtures.temporaryDirectory()
    var store: StateStore { StateStore(url: directory.appendingPathComponent("state.json")) }

    func engine(provider: any CreatureProvider = FakeProvider()) -> CreatureEngine {
        CreatureEngine(
            provider: provider,
            store: store,
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 },
            now: { [clock] in clock.now },
            sessionSecondsOverride: nil
        )
    }

    func twoPartners() async -> CreatureEngine {
        let engine = engine()
        await engine.start()
        await engine.adopt(901)
        await engine.adopt(904)
        return engine
    }

    @Test func aNewPartnerJoinsAtTheStartingLevelAndGoesOut() async {
        let engine = await twoPartners()
        let collection = store.load().collection
        #expect(collection.partners.map(\.progress) == [.starter(901), .starter(904)])
        #expect(collection.active == 904)
        #expect(await engine.currentSnapshot.phase == .active(FakeProvider().roster[904]!, .starter(904)))
    }

    @Test func focusXPGoesToThePartnerThatIsOut() async {
        let engine = await twoPartners()
        await engine.startFocus()
        clock.advance(25 * 60)
        await engine.stopFocus()
        let collection = store.load().collection
        #expect(collection.partner(904)?.progress.xp == 100)
        #expect(collection.partner(901)?.progress == .starter(901))
    }

    @Test func switchingKeepsEveryPartnersProgressAndEvolvesOnlyItsOwn() async {
        let engine = await twoPartners()
        await engine.award(150)
        await engine.switchPartner(to: 901)
        await engine.award(200 + 240)
        await engine.switchPartner(to: 904)
        let collection = store.load().collection
        #expect(collection.partner(904)?.progress == Progress(speciesId: 904, level: 5, xp: 150))
        #expect(collection.partner(901)?.progress == Progress(speciesId: 903, level: 7, xp: 0))
        #expect(await engine.currentSnapshot.phase == .active(FakeProvider().roster[904]!, Progress(speciesId: 904, level: 5, xp: 150)))
    }

    @Test func adoptingAFamilyAlreadyInTheCollectionSendsThatPartnerOut() async {
        let engine = await twoPartners()
        await engine.award(150)
        await engine.adopt(904)
        await engine.switchPartner(to: 901)
        await engine.adopt(904)
        #expect(store.load().collection.partners.count == 2)
        #expect(store.load().progress == Progress(speciesId: 904, level: 5, xp: 150))
    }

    @Test func distanceIsTalliedForThePartnerThatWalkedIt() async {
        let engine = await twoPartners()
        await engine.record(.walked(points: 80, perch: .topEdge))
        await engine.switchPartner(to: 901)
        await engine.record(.walked(points: 40, perch: .dock))
        let collection = store.load().collection
        let metresPerPoint = Distance.creatureMetresPerPoint(heightMetres: nil)
        #expect(abs((collection.partner(904)?.creatureMetres ?? 0) - 80 * metresPerPoint) < 1e-9)
        #expect(abs((collection.partner(901)?.creatureMetres ?? 0) - 40 * metresPerPoint) < 1e-9)
        #expect(abs(store.load().stats.creatureMetres - 120 * metresPerPoint) < 1e-9)
    }

    @Test func partnerOptionsListThePartnersThenTheStartersNotYetJoined() async {
        let engine = engine()
        await engine.start()
        await engine.adopt(904)
        let options = await engine.partnerOptions()
        #expect(options.map(\.species.id) == [904, 901])
        #expect(options.map { $0.partner?.root } == [904, nil])
    }

    @Test func aPartnerSavedByItsCurrentStageIsKeyedByItsFamilyOnLoad() async throws {
        try store.save(CompanionState(collection: PartnerCollection(only: Progress(speciesId: 102, level: 20, xp: 0))))
        let engine = engine(provider: OriginalCreatureProvider())
        await engine.start()
        let collection = store.load().collection
        #expect(collection.partners.map(\.root) == [101])
        #expect(collection.active == 101)
        await engine.adopt(101)
        #expect(store.load().collection.partners.count == 1)
    }

    @Test func the023StateLoadsAsItsOnlyPartner() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(StateFixtures.v023.replacingOccurrences(of: #""speciesId" : 25"#, with: #""speciesId" : 904"#).utf8).write(to: store.url)
        let engine = engine()
        await engine.start()
        #expect(await engine.currentSnapshot.phase == .active(FakeProvider().roster[904]!, Progress(speciesId: 904, level: 5, xp: 100)))
    }
}

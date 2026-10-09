import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

struct SpriteCreditsTests {
    static let project = URL(string: "https://example.test/project")!

    static func collab(_ authors: [String]) -> Attribution {
        Attribution(authors: authors, source: "SpriteCollab", license: "CC BY-NC 4.0", url: project)
    }

    static func frames(_ attribution: Attribution?) -> SpriteFrames {
        SpriteFrames(frames: [FakeProvider.image()], durations: [0.2], directional: true, attribution: attribution)
    }

    /// Every front facing of idle and walking, credited as `credit` says.
    static func sprites(_ credit: (SpriteState, Facing) -> Attribution?) -> SpriteSet {
        var anims: [SpriteState: [Facing: SpriteFrames]] = [:]
        for state in [SpriteState.idle, .walking] {
            for facing in Facing.front {
                anims[state, default: [:]][facing] = frames(credit(state, facing))
            }
        }
        return SpriteSet(bounds: SpriteRenderingTests.measured, anims: anims)
    }

    static func species(_ id: Int, _ name: String) -> Species {
        Species(id: id, name: name, evolvesTo: nil, evolvesAtLevel: nil)
    }

    static func show(_ attribution: Attribution?) throws -> SpriteShow {
        try #require(sprites { _, _ in attribution }.show(for: .idle, style: .lively))
    }

    /// A leader credited to `leader`, with a follower for each of `followers`.
    static func snapshot(leader: Attribution?, followers: [Attribution?] = []) throws -> CompanionSnapshot {
        var snapshot = CompanionSnapshot()
        snapshot.phase = .active(species(1, "Leaf"), .starter(1))
        snapshot.sprite = try show(leader)
        snapshot.followers = followers.enumerated().map { (index: Int, credit: Attribution?) -> Follower in
            Follower(root: 10 + index, species: species(10 + index, "Follower \(index + 1)"), sprites: sprites { _, _ in credit })
        }
        return snapshot
    }

    @Test func oneSourceNamesItsAuthorsAndTerms() throws {
        let credits = try #require(SpriteCredits(try Self.snapshot(leader: Self.collab(["Ana", "Bo"])).drawnCreatures))
        #expect(credits.line == "Sprites by Ana, Bo · SpriteCollab (CC BY-NC 4.0)")
        #expect(credits.fullList == "Leaf: Ana, Bo\nSpriteCollab (CC BY-NC 4.0). Click to open the project page.")
        #expect(credits.sources.map(\.url) == [Self.project])
    }

    @Test func aPartyFromOneSourceSharesOneEntryWithEachAuthorOnce() throws {
        let snapshot = try Self.snapshot(
            leader: Self.collab(["Ana", "Bo"]), followers: [Self.collab(["Bo", "Cy"]), Self.collab(["Ana", "Ana", "Dee"])]
        )
        let credits = try #require(SpriteCredits(snapshot.drawnCreatures))
        #expect(credits.line == "Sprites by Ana, Bo, Cy, Dee · SpriteCollab (CC BY-NC 4.0)")
        #expect(credits.fullList == """
        Leaf: Ana, Bo
        Follower 1: Bo, Cy
        Follower 2: Ana, Dee
        SpriteCollab (CC BY-NC 4.0). Click to open the project page.
        """)
    }

    @Test func differentSourcesStaySeparate() throws {
        let other = Attribution(authors: ["Bo"], source: "Other", license: "MIT", url: URL(string: "https://other.test")!)
        let credits = try #require(SpriteCredits([
            DrawnCreature(name: "Leaf", attributions: [Self.collab(["Ana"])]),
            DrawnCreature(name: "Pip", attributions: [other, Self.collab(["Ana", "Cy"])]),
        ]))
        #expect(credits.line == "Sprites by Ana, Cy · SpriteCollab (CC BY-NC 4.0); Sprites by Bo · Other (MIT)")
        #expect(credits.fullList == """
        Leaf: Ana
        Pip: Bo, Ana, Cy
        SpriteCollab (CC BY-NC 4.0), Other (MIT). Click to open the project pages.
        """)
    }

    @Test func aSourceThatCreditsNoOneIsStillNamed() throws {
        let credits = try #require(SpriteCredits(try Self.snapshot(leader: Self.collab([])).drawnCreatures))
        #expect(credits.line == "Sprites from SpriteCollab (CC BY-NC 4.0)")
        #expect(credits.fullList.hasPrefix("Leaf: SpriteCollab (CC BY-NC 4.0)\n"))
    }

    @Test func aProviderWithoutAttributionShowsNoCredit() throws {
        #expect(SpriteCredits(try Self.snapshot(leader: nil, followers: [nil, nil]).drawnCreatures) == nil)
        #expect(SpriteCredits([]) == nil)
    }

    @Test func anUncreditedFollowerIsLeftOutOfTheList() throws {
        let snapshot = try Self.snapshot(leader: Self.collab(["Ana"]), followers: [nil])
        let credits = try #require(SpriteCredits(snapshot.drawnCreatures))
        #expect(credits.line == "Sprites by Ana · SpriteCollab (CC BY-NC 4.0)")
        #expect(!credits.fullList.contains("Follower"))
    }

    @Test func aFollowerIsCreditedForEveryAnimItCanBeDrawnIn() throws {
        let sprites = Self.sprites { state, facing in Self.collab([state == .walking ? "Walker" : "Idler", "\(facing)"]) }
        var snapshot = CompanionSnapshot()
        snapshot.followers = [Follower(root: 10, species: Self.species(10, "Pip"), sprites: sprites)]
        let credits = try #require(SpriteCredits(snapshot.drawnCreatures))
        let facings: [String] = Facing.front.map { "\($0)" }
        #expect(credits.sources.first?.authors == ["Idler"] + facings + ["Walker"])
    }

    @Test func aVisitorIsCreditedOnlyWhileItVisits() throws {
        var snapshot = try Self.snapshot(leader: Self.collab(["Ana"]), followers: [Self.collab(["Bo"])])
        let before = try #require(SpriteCredits(snapshot.drawnCreatures))
        #expect(before.line == "Sprites by Ana, Bo · SpriteCollab (CC BY-NC 4.0)")

        snapshot.encounter = Encounter(serial: 1, species: Self.species(50, "Wisp"), show: try Self.show(Self.collab(["Cy", "Ana"])))
        let visiting = try #require(SpriteCredits(snapshot.drawnCreatures))
        #expect(visiting.line == "Sprites by Ana, Bo, Cy · SpriteCollab (CC BY-NC 4.0)")
        #expect(visiting.fullList.contains("Wisp: Cy, Ana"))

        snapshot.encounter?.caught = true
        #expect(SpriteCredits(snapshot.drawnCreatures) == visiting)

        snapshot.encounter = nil
        #expect(SpriteCredits(snapshot.drawnCreatures) == before)
    }
}

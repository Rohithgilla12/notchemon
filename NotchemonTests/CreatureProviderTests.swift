import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Notchemon

struct DiskCacheTests {
    let url = URL(string: "https://example.test/thing/1/")!

    @Test func storedBytesRoundTripAcrossInstances() async throws {
        let root = Fixtures.temporaryDirectory()
        try await DiskCache(root: root).store(Data("hello".utf8), for: url)
        #expect(await DiskCache(root: root).cached(url) == Data("hello".utf8))
        #expect(await DiskCache(root: root).cached(URL(string: "https://example.test/other")!) == nil)
    }

    @Test func servesCachedCopyWhenOffline() async throws {
        let fetcher = StubFetcher([url: Data("fresh".utf8)])
        let root = Fixtures.temporaryDirectory()
        #expect(try await DiskCache(root: root).data(for: url, using: fetcher) == Data("fresh".utf8))
        fetcher.goOffline()
        #expect(try await DiskCache(root: root).data(for: url, using: fetcher) == Data("fresh".utf8))
        #expect(fetcher.requests == [url])
    }

    @Test func coldCacheOfflinePropagatesTheError() async {
        let fetcher = StubFetcher()
        fetcher.goOffline()
        await #expect(throws: URLError.self) {
            try await DiskCache(root: Fixtures.temporaryDirectory()).data(for: url, using: fetcher)
        }
    }

    @Test func networkFetcherKeepsNoSecondCopy() {
        let configuration = URLSessionFetcher().session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }
}

struct PokeAPIParsingTests {
    @Test func levelUpTriggerGivesTargetAndLowestMinLevel() throws {
        let dto = try PokeAPIParser.species(Fixtures.speciesJSON(id: 901, name: "testmon", chain: 90))
        let species = try PokeAPIParser.species(dto, chainJSON: Fixtures.chainJSON)
        #expect(species == Species(id: 901, name: "Testmon", evolvesTo: 902, evolvesAtLevel: 18))
    }

    @Test func nonLevelUpTriggerNeverEvolves() throws {
        let dto = try PokeAPIParser.species(Fixtures.speciesJSON(id: 902, name: "testmid", chain: 90))
        let species = try PokeAPIParser.species(dto, chainJSON: Fixtures.chainJSON)
        #expect(species.evolvesTo == nil)
        #expect(species.evolvesAtLevel == nil)
    }

    @Test func finalStageHasNoEvolution() throws {
        let dto = try PokeAPIParser.species(Fixtures.speciesJSON(id: 903, name: "testmax", chain: 90))
        #expect(try PokeAPIParser.species(dto, chainJSON: Fixtures.chainJSON).evolvesTo == nil)
    }

    @Test func spriteSourcesListLoopsAndPortraitsBestFirst() throws {
        let showdown = URL(string: "https://sprites.test/sd/901.gif")!
        let animated = URL(string: "https://sprites.test/a/901.gif")!
        let still = URL(string: "https://sprites.test/s/901.png")!
        let home = URL(string: "https://sprites.test/h/901.png")!
        let artwork = URL(string: "https://sprites.test/o/901.png")!
        let json = Fixtures.pokemonJSON(id: 901, showdown: showdown, animated: animated, still: still, home: home, artwork: artwork)
        let sources = try PokeAPIParser.spriteSources(json)
        #expect(sources.animations == [showdown, animated, still])
        #expect(sources.portraits == [home, artwork])
        #expect(try PokeAPIParser.spriteSources(Fixtures.pokemonJSON(id: 901, still: still)) == SpriteSources(animations: [still], portraits: []))
    }
}

struct PokeAPICreatureProviderTests {
    let showdown = URL(string: "https://sprites.test/sd/901.gif")!
    let gif = URL(string: "https://sprites.test/a/901.gif")!
    let png = URL(string: "https://sprites.test/s/901.png")!
    let home = URL(string: "https://sprites.test/h/901.png")!
    let artwork = URL(string: "https://sprites.test/o/901.png")!
    let pokemonURL = Fixtures.api.appendingPathComponent("pokemon/901/")
    let testmon = Species(id: 901, name: "Testmon", evolvesTo: 902, evolvesAtLevel: 18)

    func provider(_ fetcher: StubFetcher, root: URL = Fixtures.temporaryDirectory()) -> PokeAPICreatureProvider {
        PokeAPICreatureProvider(cache: DiskCache(root: root), fetcher: fetcher)
    }

    @Test func fetchesSpeciesThroughSpeciesAndChainEndpoints() async throws {
        let fetcher = StubFetcher([
            Fixtures.api.appendingPathComponent("pokemon-species/901/"): Fixtures.speciesJSON(id: 901, name: "testmon", chain: 90),
            URL(string: "https://pokeapi.co/api/v2/evolution-chain/90/")!: Fixtures.chainJSON,
        ])
        #expect(try await provider(fetcher).species(id: 901) == testmon)
    }

    @Test func unknownSpeciesIsReportedAsSuch() async {
        await #expect(throws: CreatureError.unknownSpecies) {
            try await provider(StubFetcher()).species(id: 4242)
        }
    }

    @Test func spriteCollabServesTheFacingRowWithDurationsAndCredits() async throws {
        let fetcher = StubFetcher(Fixtures.spriteCollab(dex: 901))
        let frames = try await provider(fetcher).sprite(for: testmon, state: .idle, facing: .left)
        #expect(frames.frames.map(SpriteFixtures.cell) == (0..<3).map { Cell(column: $0, row: Facing.left.rawValue) })
        #expect(frames.durations == [0.1, 0.2, 0.3])
        #expect(frames.groundPoints == [CGPoint(x: 3, y: 9), CGPoint(x: 4, y: 9), CGPoint(x: 5, y: 9)])
        #expect(frames.directional)
        #expect(frames.pixelated)
        #expect(frames.loops)
        #expect(frames.attribution == Attribution(
            authors: ["STUDIO"],
            source: "SpriteCollab",
            license: "CC BY-NC 4.0",
            url: URL(string: "https://github.com/PMDCollab/SpriteCollab")!
        ))
        #expect(!fetcher.requests.contains(pokemonURL))
    }

    @Test func oneShotWithItsOwnAnimPlaysOnce() async throws {
        let frames = try await provider(StubFetcher(Fixtures.spriteCollab(dex: 901))).sprite(for: testmon, state: .hop, facing: .down)
        #expect(frames.frames.map(\.height) == [30, 30])
        #expect(!frames.loops)
        #expect(frames.attribution?.authors == ["HOPPER"])
    }

    @Test func oneShotThatFellBackToIdleLoopsSoTheRendererAddsMotion() async throws {
        let frames = try await provider(StubFetcher(Fixtures.spriteCollab(dex: 901))).sprite(for: testmon, state: .wake, facing: .down)
        #expect(frames.frames.count == 3)
        #expect(frames.loops)
    }

    @Test func spriteCollabMissFallsBackToShowdown() async throws {
        let fetcher = StubFetcher([
            pokemonURL: Fixtures.pokemonJSON(id: 901, showdown: showdown, animated: gif, still: png),
            showdown: Fixtures.image(.gif, frames: 4, delay: 0.05),
            gif: Fixtures.image(.gif, frames: 2),
        ])
        let frames = try await provider(fetcher).sprite(for: testmon, state: .hop, facing: .right)
        #expect(fetcher.requests.first == SpriteCollabEndpoint.animData(dex: 901))
        #expect(frames.frames.count == 4)
        #expect(frames.durations.allSatisfy { abs($0 - 0.05) < 0.001 })
        #expect(!frames.directional)
        #expect(frames.loops)
        #expect(frames.attribution == nil)
        #expect(frames.groundPoints == nil)
        #expect(!fetcher.requests.contains(gif))
    }

    @Test func sittingWithoutItsOwnArtHasNoStandIn() async throws {
        let fetcher = StubFetcher(Fixtures.spriteCollab(dex: 901).merging([
            pokemonURL: Fixtures.pokemonJSON(id: 901, showdown: showdown, still: png),
            showdown: Fixtures.image(.gif, frames: 4, delay: 0.05),
            png: Fixtures.image(.png, frames: 1),
        ]) { first, _ in first })
        await #expect(throws: CreatureError.missingSprite) {
            try await provider(fetcher).sprite(for: testmon, state: .sitting, facing: .down)
        }
        #expect(!fetcher.requests.contains(showdown))
        #expect(!fetcher.requests.contains(png))
    }

    @Test func missingShowdownFallsBackToGen5() async throws {
        let fetcher = StubFetcher([
            pokemonURL: Fixtures.pokemonJSON(id: 901, animated: gif, still: png),
            gif: Fixtures.image(.gif, frames: 3, delay: 0.08),
        ])
        let frames = try await provider(fetcher).sprite(for: testmon, state: .idle, facing: .down)
        #expect(frames.frames.count == 3)
        #expect(frames.durations.allSatisfy { abs($0 - 0.08) < 0.001 })
    }

    @Test func fallsBackToStillWhenNoAnimatedSprite() async throws {
        let fetcher = StubFetcher([
            pokemonURL: Fixtures.pokemonJSON(id: 901, showdown: showdown, still: png),
            png: Fixtures.image(.png, frames: 1),
        ])
        let frames = try await provider(fetcher).sprite(for: testmon, state: .sleeping, facing: .down)
        #expect(frames.frames.count == 1)
        #expect(!frames.directional)
    }

    @Test func portraitPrefersHomeThenOfficialArtwork() async throws {
        let both = StubFetcher([
            pokemonURL: Fixtures.pokemonJSON(id: 901, home: home, artwork: artwork),
            home: Fixtures.image(.png, frames: 1),
            artwork: Fixtures.image(.png, frames: 1),
        ])
        _ = try await provider(both).portrait(for: testmon)
        #expect(both.requests.last == home)

        let artworkOnly = StubFetcher([
            pokemonURL: Fixtures.pokemonJSON(id: 901, home: home, artwork: artwork),
            artwork: Fixtures.image(.png, frames: 1),
        ])
        _ = try await provider(artworkOnly).portrait(for: testmon)
        #expect(artworkOnly.requests.suffix(2) == [home, artwork])
    }

    @Test func secondLaunchWorksOffline() async throws {
        let root = Fixtures.temporaryDirectory()
        var responses = Fixtures.spriteCollab(dex: 901)
        responses[Fixtures.api.appendingPathComponent("pokemon-species/901/")] = Fixtures.speciesJSON(id: 901, name: "testmon", chain: 90)
        responses[URL(string: "https://pokeapi.co/api/v2/evolution-chain/90/")!] = Fixtures.chainJSON
        let fetcher = StubFetcher(responses)
        _ = try await provider(fetcher, root: root).species(id: 901)
        _ = try await provider(fetcher, root: root).sprite(for: testmon, state: .idle, facing: .down)
        fetcher.goOffline()
        #expect(try await provider(fetcher, root: root).species(id: 901) == testmon)
        let offline = try await provider(fetcher, root: root).sprite(for: testmon, state: .idle, facing: .up)
        #expect(offline.frames.map(SpriteFixtures.cell) == (0..<3).map { Cell(column: $0, row: Facing.up.rawValue) })
        #expect(offline.attribution?.authors == ["STUDIO"])
    }
}

struct OriginalCreatureProviderTests {
    let provider = OriginalCreatureProvider()

    @Test func everyStarterResolvesAndEvolutionTargetsExist() async throws {
        for id in provider.starterIDs {
            var species = try await provider.species(id: id)
            while let next = species.evolvesTo {
                #expect(species.evolvesAtLevel != nil)
                species = try await provider.species(id: next)
            }
        }
    }

    @Test func drawsTwoFrameSpritesForEveryStateButSittingAndFacing() async throws {
        let species = try await provider.species(id: provider.starterIDs[0])
        await #expect(throws: CreatureError.missingSprite) { try await provider.sprite(for: species, state: .sitting, facing: .down) }
        for state in SpriteState.allCases where state != .sitting {
            for facing in Facing.allCases {
                let frames = try await provider.sprite(for: species, state: state, facing: facing)
                #expect(frames.frames.count == 2)
                #expect(frames.directional)
                #expect(frames.loops)
                #expect(frames.attribution == nil)
            }
        }
    }

    @Test func eyesFollowTheFacing() async throws {
        let species = try await provider.species(id: provider.starterIDs[0])
        let left = try await provider.sprite(for: species, state: .idle, facing: .left).frames[0]
        let right = try await provider.sprite(for: species, state: .idle, facing: .right).frames[0]
        #expect(left.dataProvider?.data != right.dataProvider?.data)
    }

    @Test func portraitIsLargeAndSmooth() async throws {
        let portrait = try await provider.portrait(for: try await provider.species(id: provider.starterIDs[1]))
        #expect(portrait.width >= 256)
    }

    @Test func foreignIDsAreUnknown() async {
        await #expect(throws: CreatureError.unknownSpecies) { try await provider.species(id: 1) }
    }
}

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

    @Test func spriteURLsPreferAnimatedButKeepStill() throws {
        let animated = URL(string: "https://sprites.test/a/901.gif")!
        let still = URL(string: "https://sprites.test/s/901.png")!
        let urls = try PokeAPIParser.spriteURLs(Fixtures.pokemonJSON(id: 901, animated: animated, still: still))
        #expect(urls.animated == animated)
        #expect(urls.still == still)
    }
}

struct PokeAPICreatureProviderTests {
    let gif = URL(string: "https://sprites.test/a/901.gif")!
    let png = URL(string: "https://sprites.test/s/901.png")!
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

    @Test func animatedGIFDecodesToAllFramesWithTheirDelays() async throws {
        let fetcher = StubFetcher([
            Fixtures.api.appendingPathComponent("pokemon/901/"): Fixtures.pokemonJSON(id: 901, animated: gif, still: png),
            gif: Fixtures.image(.gif, frames: 3, delay: 0.08),
        ])
        let frames = try await provider(fetcher).sprite(for: testmon, state: .idle, facing: .down)
        #expect(frames.frames.count == 3)
        #expect(frames.durations.allSatisfy { abs($0 - 0.08) < 0.001 })
    }

    @Test func fallsBackToStillWhenNoAnimatedSprite() async throws {
        let fetcher = StubFetcher([
            Fixtures.api.appendingPathComponent("pokemon/901/"): Fixtures.pokemonJSON(id: 901, animated: nil, still: png),
            png: Fixtures.image(.png, frames: 1),
        ])
        let frames = try await provider(fetcher).sprite(for: testmon, state: .idle, facing: .down)
        #expect(frames.frames.count == 1)
    }

    @Test func secondLaunchWorksOffline() async throws {
        let root = Fixtures.temporaryDirectory()
        let fetcher = StubFetcher([
            Fixtures.api.appendingPathComponent("pokemon-species/901/"): Fixtures.speciesJSON(id: 901, name: "testmon", chain: 90),
            URL(string: "https://pokeapi.co/api/v2/evolution-chain/90/")!: Fixtures.chainJSON,
            Fixtures.api.appendingPathComponent("pokemon/901/"): Fixtures.pokemonJSON(id: 901, animated: gif, still: png),
            gif: Fixtures.image(.gif, frames: 2),
        ])
        _ = try await provider(fetcher, root: root).species(id: 901)
        _ = try await provider(fetcher, root: root).sprite(for: testmon, state: .idle, facing: .down)
        fetcher.goOffline()
        #expect(try await provider(fetcher, root: root).species(id: 901) == testmon)
        #expect(try await provider(fetcher, root: root).sprite(for: testmon, state: .sleeping, facing: .left).frames.count == 2)
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

    @Test func drawsTwoFrameSpritesForEveryState() async throws {
        let species = try await provider.species(id: provider.starterIDs[0])
        for state in SpriteState.allCases {
            let frames = try await provider.sprite(for: species, state: state, facing: .down)
            #expect(frames.frames.count == 2)
        }
    }

    @Test func foreignIDsAreUnknown() async {
        await #expect(throws: CreatureError.unknownSpecies) { try await provider.species(id: 1) }
    }
}

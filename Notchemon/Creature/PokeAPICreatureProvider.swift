import CoreGraphics
import Foundation

/// Species data from PokéAPI; sprites from SpriteCollab, falling back to
/// PokéAPI's own sprites. Nothing it serves is ever bundled; everything
/// lands in the user's cache directory.
struct PokeAPICreatureProvider: CreatureProvider {
    let starterIDs = [1, 4, 7, 25]
    /// Today's starters, then each later generation's three starters in their first stage.
    let unlockTiers: [[Int]] = [
        [1, 4, 7, 25],
        [152, 155, 158],
        [252, 255, 258],
        [387, 390, 393],
        [495, 498, 501],
        [650, 653, 656],
        [722, 725, 728],
        [810, 813, 816],
        [906, 909, 912],
    ]
    /// More than PokeAPI lists, so one page holds them all.
    static let indexLimit = 2_000
    /// How many random species to look at before giving up on one visit.
    static let encounterAttempts = 12
    let cache: DiskCache
    let fetcher: any DataFetcher
    let spriteCollab: SpriteCollabClient
    let baseURL = URL(string: "https://pokeapi.co/api/v2/")!

    init(cache: DiskCache, fetcher: any DataFetcher) {
        self.cache = cache
        self.fetcher = fetcher
        spriteCollab = SpriteCollabClient { url in try await cache.data(for: url, using: fetcher) }
    }

    func species(id: Int) async throws -> Species {
        let speciesJSON = try await load(baseURL.appendingPathComponent("pokemon-species/\(id)/"))
        let dto = try PokeAPIParser.species(speciesJSON)
        let chainJSON = try await load(dto.evolutionChain.url)
        // Height is a nicety for stats; a species still loads without it.
        let height = try? PokeAPIParser.heightMetres(try await load(baseURL.appendingPathComponent("pokemon/\(id)/")))
        return try PokeAPIParser.species(dto, chainJSON: chainJSON, heightMetres: height)
    }

    func speciesIndex() async throws -> [SpeciesEntry] {
        var components = URLComponents(url: baseURL.appendingPathComponent("pokemon-species/"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(Self.indexLimit))]
        guard let url = components?.url else { return [] }
        return try PokeAPIParser.speciesIndex(try await cache.data(for: url, using: fetcher))
    }

    /// A random first-stage species that is neither legendary nor mythical
    /// and that SpriteCollab draws idling and walking. Most species pass,
    /// so a few draws find one; every fetch lands in the disk cache.
    func encounterCandidate(using rng: inout some RandomNumberGenerator) async throws -> Species? {
        let index = try await speciesIndex()
        for _ in 0..<Self.encounterAttempts {
            guard let entry = index.randomElement(using: &rng) else { return nil }
            guard let dto = try? PokeAPIParser.species(try await load(baseURL.appendingPathComponent("pokemon-species/\(entry.id)/"))),
                  dto.isWildCandidate,
                  await spriteCollab.hasAnims(["Idle", "Walk"], dex: entry.id)
            else { continue }
            return try await species(id: entry.id)
        }
        return nil
    }

    /// SpriteCollab has a sheet per anim and facing. Species or anims it lacks
    /// fall back to one left-facing loop that serves every state but sitting,
    /// which nothing else draws.
    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        if let sprite = try? await spriteCollab.sprite(dex: species.id, animation: PMDAnimation(state), facing: facing) {
            // A one-shot that fell back to the idle anim has no motion of its own.
            let ownMotion = !state.loops && !PMDAnimation.idle.fallbackNames.contains(sprite.animName)
            return SpriteFrames(
                frames: sprite.frames,
                durations: sprite.durations,
                directional: true,
                loops: !ownMotion,
                attribution: sprite.attribution,
                groundPoints: sprite.groundPoints
            )
        }
        guard state != .sitting else { throw CreatureError.missingSprite }
        for url in try await sources(of: species).animations {
            if let data = try? await cache.data(for: url, using: fetcher), let frames = SpriteDecoder.decode(data) {
                return frames
            }
        }
        throw CreatureError.missingSprite
    }

    func portrait(for species: Species) async throws -> CGImage {
        for url in try await sources(of: species).portraits {
            if let data = try? await cache.data(for: url, using: fetcher), let image = SpriteDecoder.firstImage(data) {
                return image
            }
        }
        throw CreatureError.missingSprite
    }

    private func sources(of species: Species) async throws -> SpriteSources {
        try PokeAPIParser.spriteSources(try await load(baseURL.appendingPathComponent("pokemon/\(species.id)/")))
    }

    private func load(_ url: URL) async throws -> Data {
        do {
            return try await cache.data(for: url, using: fetcher)
        } catch FetchError.http(status: 404) {
            throw CreatureError.unknownSpecies
        }
    }
}

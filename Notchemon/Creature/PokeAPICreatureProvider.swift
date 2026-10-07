import CoreGraphics
import Foundation

/// Species data from PokéAPI; sprites from SpriteCollab, falling back to
/// PokéAPI's own sprites. Nothing it serves is ever bundled; everything
/// lands in the user's cache directory.
struct PokeAPICreatureProvider: CreatureProvider {
    let starterIDs = [1, 4, 7, 25]
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
        return try PokeAPIParser.species(dto, chainJSON: chainJSON)
    }

    /// SpriteCollab has a sheet per anim and facing. Species or anims it lacks
    /// fall back to one left-facing loop that serves every state.
    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        if let sprite = try? await spriteCollab.sprite(dex: species.id, animation: PMDAnimation(state), facing: facing) {
            // A one-shot that fell back to the idle anim has no motion of its own.
            let ownMotion = !state.loops && !PMDAnimation.idle.fallbackNames.contains(sprite.animName)
            return SpriteFrames(
                frames: sprite.frames,
                durations: sprite.durations,
                directional: true,
                loops: !ownMotion,
                credits: sprite.authors
            )
        }
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

import CoreGraphics
import Foundation

/// Fetches species and sprites from PokéAPI at runtime. Nothing it serves is
/// ever bundled; everything lands in the user's cache directory.
struct PokeAPICreatureProvider: CreatureProvider {
    let starterIDs = [1, 4, 7, 25]
    let cache: DiskCache
    let fetcher: any DataFetcher
    var baseURL = URL(string: "https://pokeapi.co/api/v2/")!

    func species(id: Int) async throws -> Species {
        let speciesJSON = try await load(baseURL.appendingPathComponent("pokemon-species/\(id)/"))
        let dto = try PokeAPIParser.species(speciesJSON)
        let chainJSON = try await load(dto.evolutionChain.url)
        return try PokeAPIParser.species(dto, chainJSON: chainJSON)
    }

    /// PokéAPI has one sprite per species, so every state shares it; the
    /// renderer expresses sleep and celebration through motion.
    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        let pokemonJSON = try await load(baseURL.appendingPathComponent("pokemon/\(species.id)/"))
        let urls = try PokeAPIParser.spriteURLs(pokemonJSON)
        for url in [urls.animated, urls.still].compactMap({ $0 }) {
            if let data = try? await cache.data(for: url, using: fetcher), let frames = SpriteDecoder.decode(data) {
                return frames
            }
        }
        throw CreatureError.missingSprite
    }

    func portrait(for species: Species) async throws -> CGImage {
        throw CreatureError.missingSprite
    }

    private func load(_ url: URL) async throws -> Data {
        do {
            return try await cache.data(for: url, using: fetcher)
        } catch FetchError.http(status: 404) {
            throw CreatureError.unknownSpecies
        }
    }
}

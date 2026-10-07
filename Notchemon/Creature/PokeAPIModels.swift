import Foundation

struct NamedResource: Decodable, Sendable {
    let name: String
    let url: URL

    /// PokéAPI resource URLs end in `/{id}/`.
    var id: Int? { Int(url.lastPathComponent) }
}

struct PokemonDTO: Decodable, Sendable {
    struct Sprites: Decodable, Sendable {
        struct Versions: Decodable, Sendable {
            struct GenerationV: Decodable, Sendable {
                struct BlackWhite: Decodable, Sendable {
                    struct Animated: Decodable, Sendable {
                        let frontDefault: URL?
                    }
                    let animated: Animated?
                }
                let blackWhite: BlackWhite?

                // Hyphenated keys are untouched by .convertFromSnakeCase.
                enum CodingKeys: String, CodingKey { case blackWhite = "black-white" }
            }
            let generationV: GenerationV?

            enum CodingKeys: String, CodingKey { case generationV = "generation-v" }
        }
        struct Other: Decodable, Sendable {
            struct Front: Decodable, Sendable {
                let frontDefault: URL?
            }
            let home: Front?
            let showdown: Front?
            let officialArtwork: Front?

            enum CodingKeys: String, CodingKey { case home, showdown, officialArtwork = "official-artwork" }
        }
        let frontDefault: URL?
        let other: Other?
        let versions: Versions?
    }

    let id: Int
    let sprites: Sprites
}

struct SpeciesDTO: Decodable, Sendable {
    struct LocalizedName: Decodable, Sendable {
        let name: String
        let language: NamedResource
    }
    struct ChainReference: Decodable, Sendable {
        let url: URL
    }

    let id: Int
    let name: String
    let names: [LocalizedName]
    let evolutionChain: ChainReference
}

struct EvolutionChainDTO: Decodable, Sendable {
    struct Link: Decodable, Sendable {
        struct Detail: Decodable, Sendable {
            let trigger: NamedResource
            let minLevel: Int?
        }
        let species: NamedResource
        let evolutionDetails: [Detail]
        let evolvesTo: [Link]
    }

    let chain: Link
}

/// Where a species' images live, each list best first.
struct SpriteSources: Sendable, Equatable {
    /// Left-facing loops: Showdown GIF, then Gen 5 GIF, then the still sprite.
    let animations: [URL]
    /// Large smooth art: HOME render, then official artwork.
    let portraits: [URL]
}

enum PokeAPIParser {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func species(_ speciesJSON: Data) throws -> SpeciesDTO {
        try decoder.decode(SpeciesDTO.self, from: speciesJSON)
    }

    static func species(_ dto: SpeciesDTO, chainJSON: Data) throws -> Species {
        let chain = try decoder.decode(EvolutionChainDTO.self, from: chainJSON)
        let evolution = levelUpEvolution(of: dto.id, in: chain.chain)
        return Species(id: dto.id, name: displayName(dto), evolvesTo: evolution?.to, evolvesAtLevel: evolution?.level)
    }

    static func displayName(_ dto: SpeciesDTO) -> String {
        dto.names.first { $0.language.name == "en" }?.name ?? dto.name.capitalized
    }

    /// The first branch reachable by levelling up. Item, trade, and friendship
    /// evolutions have no level, so a species with only those never evolves here.
    static func levelUpEvolution(of speciesID: Int, in chain: EvolutionChainDTO.Link) -> (to: Int, level: Int)? {
        guard let node = find(speciesID, in: chain) else { return nil }
        for next in node.evolvesTo {
            guard let target = next.species.id else { continue }
            let levels = next.evolutionDetails.filter { $0.trigger.name == "level-up" }.compactMap(\.minLevel)
            if let level = levels.min() { return (target, level) }
        }
        return nil
    }

    static func spriteSources(_ pokemonJSON: Data) throws -> SpriteSources {
        let sprites = try decoder.decode(PokemonDTO.self, from: pokemonJSON).sprites
        return SpriteSources(
            animations: [
                sprites.other?.showdown?.frontDefault,
                sprites.versions?.generationV?.blackWhite?.animated?.frontDefault,
                sprites.frontDefault,
            ].compactMap { $0 },
            portraits: [sprites.other?.home?.frontDefault, sprites.other?.officialArtwork?.frontDefault].compactMap { $0 }
        )
    }

    private static func find(_ id: Int, in link: EvolutionChainDTO.Link) -> EvolutionChainDTO.Link? {
        if link.species.id == id { return link }
        for child in link.evolvesTo {
            if let found = find(id, in: child) { return found }
        }
        return nil
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Notchemon

/// A fetcher that serves canned bytes and records what was asked for.
final class StubFetcher: DataFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: Data]
    private var offline = false
    private(set) var requests: [URL] = []

    init(_ responses: [URL: Data] = [:]) {
        self.responses = responses
    }

    func goOffline() {
        lock.withLock { offline = true }
    }

    func data(from url: URL) async throws -> Data {
        try lock.withLock {
            requests.append(url)
            if offline { throw URLError(.notConnectedToInternet) }
            guard let data = responses[url] else { throw FetchError.http(status: 404) }
            return data
        }
    }
}

enum Fixtures {
    static let api = URL(string: "https://pokeapi.co/api/v2/")!

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("notchemon-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func speciesJSON(id: Int, name: String, chain: Int) -> Data {
        Data("""
        {"id": \(id), "name": "\(name)",
         "names": [{"name": "\(name.uppercased())-ja", "language": {"name": "ja", "url": "https://pokeapi.co/api/v2/language/1/"}},
                   {"name": "\(name.capitalized)", "language": {"name": "en", "url": "https://pokeapi.co/api/v2/language/9/"}}],
         "evolution_chain": {"url": "https://pokeapi.co/api/v2/evolution-chain/\(chain)/"}}
        """.utf8)
    }

    /// testmon (901) -> levels into testmid (902) at 18 -> stone-only into testmax (903).
    static let chainJSON = Data("""
    {"id": 90, "chain": {
      "species": {"name": "testmon", "url": "https://pokeapi.co/api/v2/pokemon-species/901/"},
      "evolution_details": [],
      "evolves_to": [{
        "species": {"name": "testmid", "url": "https://pokeapi.co/api/v2/pokemon-species/902/"},
        "evolution_details": [
          {"trigger": {"name": "level-up", "url": "https://pokeapi.co/api/v2/evolution-trigger/1/"}, "min_level": 20},
          {"trigger": {"name": "level-up", "url": "https://pokeapi.co/api/v2/evolution-trigger/1/"}, "min_level": 18}
        ],
        "evolves_to": [{
          "species": {"name": "testmax", "url": "https://pokeapi.co/api/v2/pokemon-species/903/"},
          "evolution_details": [
            {"trigger": {"name": "use-item", "url": "https://pokeapi.co/api/v2/evolution-trigger/3/"}, "min_level": null}
          ],
          "evolves_to": []
        }]
      }]
    }}
    """.utf8)

    static func pokemonJSON(
        id: Int,
        showdown: URL? = nil,
        animated: URL? = nil,
        still: URL? = nil,
        home: URL? = nil,
        artwork: URL? = nil
    ) -> Data {
        func json(_ url: URL?) -> String { url.map { "\"\($0.absoluteString)\"" } ?? "null" }
        return Data("""
        {"id": \(id), "name": "testmon",
         "sprites": {"front_default": \(json(still)),
           "other": {"home": {"front_default": \(json(home))},
                     "official-artwork": {"front_default": \(json(artwork))},
                     "showdown": {"front_default": \(json(showdown))}},
           "versions": {"generation-v": {"black-white": {"animated": {"front_default": \(json(animated))}}}}}}
        """.utf8)
    }

    /// Idle and Hop with eight facing rows; Wake, Pose, and their fallbacks absent.
    static func spriteCollab(dex: Int) -> [URL: Data] {
        [
            SpriteCollabEndpoint.animData(dex: dex): SpriteFixtures.animData("""
            \(SpriteFixtures.anim("Idle", width: 10, height: 12, durations: [6, 12, 18]))
            \(SpriteFixtures.anim("Hop", width: 10, height: 30, durations: [3, 3]))
            """),
            SpriteCollabEndpoint.sheet(dex: dex, name: "Idle"): SpriteFixtures.png(
                SpriteFixtures.sheet(frameWidth: 10, frameHeight: 12, columns: 3, rows: 8)
            ),
            SpriteCollabEndpoint.sheet(dex: dex, name: "Hop"): SpriteFixtures.png(
                SpriteFixtures.sheet(frameWidth: 10, frameHeight: 30, columns: 2, rows: 8)
            ),
            SpriteCollabEndpoint.shadow(dex: dex, name: "Idle"): SpriteFixtures.png(SpriteFixtures.shadowSheet(
                frameWidth: 10, frameHeight: 12, columns: 3, rows: 8, shadow: CGRect(x: 2, y: 8, width: 6, height: 3)
            ) { cell in CGPoint(x: 3 + cell.column, y: 9) }),
            SpriteCollabEndpoint.shadow(dex: dex, name: "Hop"): SpriteFixtures.png(SpriteFixtures.shadowSheet(
                frameWidth: 10, frameHeight: 30, columns: 2, rows: 8, shadow: CGRect(x: 2, y: 24, width: 6, height: 3)
            ) { _ in CGPoint(x: 5, y: 25) }),
            SpriteCollabEndpoint.credits(dex: dex): Data("t\tSTUDIO\tCUR\tU\tIdle\nt\tHOPPER\tCUR\tU\tHop".utf8),
        ]
    }

    static func image(_ type: UTType, frames: Int, delay: Double = 0.08) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil)!
        for index in 0..<frames {
            let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: CGFloat(index) / CGFloat(frames), green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(destination, context.makeImage()!, type == .gif ? properties : nil)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

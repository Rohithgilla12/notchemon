import CoreGraphics
import Foundation

struct Species: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let evolvesTo: Int?
    let evolvesAtLevel: Int?
}

enum SpriteState: String, Codable, Sendable, CaseIterable {
    case idle, sleeping, happy, levelUp
}

/// Decoded animation frames. `NSImage` is not `Sendable`, so providers hand back
/// `CGImage` frames that the render layer can cross actor boundaries with.
struct SpriteFrames: @unchecked Sendable {
    let frames: [CGImage]
    let frameDuration: TimeInterval

    var isAnimated: Bool { frames.count > 1 }
}

/// The only seam between app logic and any creature IP. App code must never
/// reference a concrete provider outside `CreatureProviderFactory`.
protocol CreatureProvider: Sendable {
    var starterIDs: [Int] { get }
    func species(id: Int) async throws -> Species
    func sprite(for species: Species, state: SpriteState) async throws -> SpriteFrames
}

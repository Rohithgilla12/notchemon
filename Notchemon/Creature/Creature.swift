import CoreGraphics
import Foundation

struct Species: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let evolvesTo: Int?
    let evolvesAtLevel: Int?
}

/// What the creature is doing, as far as its sprite is concerned. `idle` and
/// `sleeping` loop; the rest are one-shots played over the loop.
enum SpriteState: String, Sendable, CaseIterable {
    case idle, sleeping, celebrating, hop, wake

    var loops: Bool { self == .idle || self == .sleeping }
}

/// Eight facings in the row order PMD-style sheets use, counter-clockwise
/// from facing the viewer.
enum Facing: Int, Sendable, CaseIterable {
    case down, downRight, right, upRight, up, upLeft, left, downLeft

    /// Vectors shorter than this are treated as "on top of the sprite".
    static let deadZone: Double = 0.5

    /// Maps a vector from the sprite to a target onto the nearest facing.
    /// `dy` follows AppKit screen space, where positive y points up.
    static func toward(dx: Double, dy: Double) -> Facing {
        guard (dx * dx + dy * dy).squareRoot() >= deadZone else { return .down }
        let degrees = atan2(dy, dx) * 180 / .pi
        // Rows run counter-clockwise from straight down in 45 degree steps.
        let step = Int(((degrees + 90) / 45).rounded())
        let row = ((step % 8) + 8) % 8
        return Facing(rawValue: row) ?? .down
    }

    /// The nearest facing that shows the creature's face. A companion never
    /// turns its back: a target above it is looked at from the front.
    var frontFacing: Facing {
        switch self {
        case .up: .down
        case .upLeft: .left
        case .upRight: .right
        case .down, .downRight, .right, .left, .downLeft: self
        }
    }

    /// Every facing the creature can show, in sheet row order.
    static let front = allCases.filter { $0.frontFacing == $0 }

    /// -1 for facings with a leftward component, 1 for rightward, 0 otherwise.
    var horizontal: Int {
        switch self {
        case .downRight, .right, .upRight: 1
        case .downLeft, .left, .upLeft: -1
        case .down, .up: 0
        }
    }
}

/// One animation: a frame per entry in `durations`.
struct SpriteFrames: Sendable {
    let frames: [CGImage]
    let durations: [TimeInterval]
    /// Pixel art scales with nearest-neighbour; smooth drawings do not.
    let pixelated: Bool
    /// True when the frames were drawn for the requested facing. Otherwise
    /// they face left and the renderer mirrors them for rightward facings.
    let directional: Bool
    /// False only for a dedicated one-shot anim that carries its own motion.
    /// A looping fallback asks the renderer to add the motion itself.
    let loops: Bool
    /// Artists to credit wherever these frames are shown; empty when none apply.
    let credits: [String]

    init(frames: [CGImage], durations: [TimeInterval], pixelated: Bool = true, directional: Bool = false, loops: Bool = true, credits: [String] = []) {
        precondition(!frames.isEmpty && frames.count == durations.count, "one duration per frame")
        self.frames = frames
        self.durations = durations
        self.pixelated = pixelated
        self.directional = directional
        self.loops = loops
        self.credits = credits
    }

    var totalDuration: TimeInterval { durations.reduce(0, +) }
}

enum CreatureError: Error, Equatable {
    /// The provider has no such species, for example after switching providers.
    case unknownSpecies
    case missingSprite
}

/// The only seam between app logic and any creature IP. App code must never
/// reference a concrete provider outside `CreatureProviderFactory`.
protocol CreatureProvider: Sendable {
    var starterIDs: [Int] { get }
    func species(id: Int) async throws -> Species
    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames
    /// Large, smooth art for the starter picker and the evolution reveal.
    func portrait(for species: Species) async throws -> CGImage
}

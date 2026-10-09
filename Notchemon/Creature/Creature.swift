import CoreGraphics
import Foundation

struct Species: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let evolvesTo: Int?
    let evolvesAtLevel: Int?
    /// How tall the species really is, which sets its creature-scale stride.
    var heightMetres: Double? = nil
    /// The first stage of its evolution family, or nil when the provider
    /// cannot say. A collection keeps one partner per family.
    var familyRoot: Int? = nil
}

/// What the creature is doing, as far as its sprite is concerned. `idle`,
/// `sleeping`, `sitting`, and `walking` loop; the rest are one-shots played
/// over the loop.
enum SpriteState: String, Sendable, CaseIterable {
    case idle, sleeping, celebrating, hop, wake, sitting, walking

    var loops: Bool { self == .idle || self == .sleeping || self == .sitting || self == .walking }
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

/// Who made a sprite and on what terms. The provider supplies it so the view
/// names no artwork source of its own.
struct Attribution: Sendable, Equatable {
    /// Display names where known, raw ids otherwise; may be empty when the
    /// source credits no one for this sprite.
    let authors: [String]
    let source: String
    let license: String
    let url: URL
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
    /// Shown wherever these frames are; nil when the provider owes no credit.
    let attribution: Attribution?
    /// The point in each frame, in pixels from its top-left corner, that
    /// stands on the ground. Every frame of every anim of a species is drawn
    /// with its ground point on one shared line, as the original game does.
    /// Nil when the source has no such data.
    let groundPoints: [CGPoint]?

    init(
        frames: [CGImage], durations: [TimeInterval], pixelated: Bool = true, directional: Bool = false, loops: Bool = true,
        attribution: Attribution? = nil, groundPoints: [CGPoint]? = nil
    ) {
        precondition(!frames.isEmpty && frames.count == durations.count, "one duration per frame")
        precondition(groundPoints.map { $0.count == frames.count } ?? true, "one ground point per frame")
        self.frames = frames
        self.durations = durations
        self.pixelated = pixelated
        self.directional = directional
        self.loops = loops
        self.attribution = attribution
        self.groundPoints = groundPoints
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
    /// Species that open together as the user's stats grow, as numeric ids.
    /// Tier 0 is open from the start.
    var unlockTiers: [[Int]] { get }
    /// Every species the provider can show, for the developer search.
    func speciesIndex() async throws -> [SpeciesEntry]
    func species(id: Int) async throws -> Species
    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames
    /// Large, smooth art for the starter picker and the evolution reveal.
    func portrait(for species: Species) async throws -> CGImage
}

extension CreatureProvider {
    var unlockTiers: [[Int]] { [starterIDs] }

    func speciesIndex() async throws -> [SpeciesEntry] { [] }
}

/// A species as an index lists it: its id and the provider's own name for it.
struct SpeciesEntry: Sendable, Equatable {
    let id: Int
    let name: String
}

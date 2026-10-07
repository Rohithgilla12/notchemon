import CoreGraphics
import Foundation

/// Original creatures drawn procedurally with Core Graphics. Needs no network
/// and carries no third-party IP, so it is the takedown fallback.
struct OriginalCreatureProvider: CreatureProvider {
    enum Crest: Sendable { case leaf, flame, fin, bolt }

    struct Design: Sendable {
        let name: String
        let stage: Int
        let crest: Crest
        let body: (r: CGFloat, g: CGFloat, b: CGFloat)
        let evolvesTo: Int?
        let evolvesAtLevel: Int?
    }

    static let roster: [Int: Design] = [
        101: Design(name: "Sprigget", stage: 1, crest: .leaf, body: (0.45, 0.78, 0.45), evolvesTo: 102, evolvesAtLevel: 16),
        102: Design(name: "Thornbun", stage: 2, crest: .leaf, body: (0.30, 0.66, 0.38), evolvesTo: 103, evolvesAtLevel: 32),
        103: Design(name: "Grovemane", stage: 3, crest: .leaf, body: (0.18, 0.52, 0.30), evolvesTo: nil, evolvesAtLevel: nil),
        104: Design(name: "Emberpup", stage: 1, crest: .flame, body: (0.98, 0.58, 0.30), evolvesTo: 105, evolvesAtLevel: 16),
        105: Design(name: "Cindermaw", stage: 2, crest: .flame, body: (0.92, 0.42, 0.22), evolvesTo: 106, evolvesAtLevel: 36),
        106: Design(name: "Pyrolion", stage: 3, crest: .flame, body: (0.80, 0.28, 0.18), evolvesTo: nil, evolvesAtLevel: nil),
        107: Design(name: "Driplet", stage: 1, crest: .fin, body: (0.42, 0.70, 0.98), evolvesTo: 108, evolvesAtLevel: 16),
        108: Design(name: "Tidewhelp", stage: 2, crest: .fin, body: (0.28, 0.55, 0.90), evolvesTo: 109, evolvesAtLevel: 36),
        109: Design(name: "Maelstride", stage: 3, crest: .fin, body: (0.18, 0.40, 0.78), evolvesTo: nil, evolvesAtLevel: nil),
        110: Design(name: "Zapling", stage: 1, crest: .bolt, body: (0.99, 0.85, 0.30), evolvesTo: 111, evolvesAtLevel: 22),
        111: Design(name: "Stormling", stage: 2, crest: .bolt, body: (0.95, 0.72, 0.18), evolvesTo: nil, evolvesAtLevel: nil),
    ]

    let starterIDs = [101, 104, 107, 110]

    func species(id: Int) async throws -> Species {
        guard let design = Self.roster[id] else { throw CreatureError.unknownSpecies }
        return Species(id: id, name: design.name, evolvesTo: design.evolvesTo, evolvesAtLevel: design.evolvesAtLevel)
    }

    /// The eyes follow the facing; the body is symmetric, so nothing else
    /// changes. Every state is a gentle two-frame squash that loops, and the
    /// renderer adds the hop, wake, and celebration motion. There is no
    /// sitting pose.
    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        guard let design = Self.roster[species.id] else { throw CreatureError.unknownSpecies }
        guard state != .sitting else { throw CreatureError.missingSprite }
        let frames = [0.0, 1.0].compactMap { squash in
            Self.draw(design, state: state, facing: facing, squash: squash, pixels: Self.canvas)
        }
        guard !frames.isEmpty else { throw CreatureError.missingSprite }
        let duration = state == .celebrating ? 0.2 : 0.45
        return SpriteFrames(frames: frames, durations: frames.map { _ in duration }, pixelated: false, directional: true)
    }

    func portrait(for species: Species) async throws -> CGImage {
        guard let design = Self.roster[species.id] else { throw CreatureError.unknownSpecies }
        guard let image = Self.draw(design, state: .idle, facing: .down, squash: 0, pixels: Self.portraitPixels) else {
            throw CreatureError.missingSprite
        }
        return image
    }

    static let canvas = 96
    static let portraitPixels = 384

    /// Draws in `canvas` units onto a `pixels`-square bitmap.
    static func draw(_ design: Design, state: SpriteState, facing: Facing, squash: CGFloat, pixels: Int) -> CGImage? {
        let side = CGFloat(canvas)
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: CGFloat(pixels) / side, y: CGFloat(pixels) / side)

        let scale = 0.62 + 0.13 * CGFloat(design.stage)
        let width = side * 0.62 * scale * (1 + 0.04 * squash)
        let height = side * 0.56 * scale * (1 - 0.06 * squash)
        let body = CGRect(x: (side - width) / 2, y: 6, width: width, height: height)
        let fill = CGColor(red: design.body.r, green: design.body.g, blue: design.body.b, alpha: 1)
        let shade = CGColor(red: design.body.r * 0.7, green: design.body.g * 0.7, blue: design.body.b * 0.7, alpha: 1)

        drawCrest(design.crest, on: body, stage: design.stage, in: context, color: shade)
        context.setFillColor(fill)
        context.fillEllipse(in: body)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
        context.fillEllipse(in: CGRect(x: body.midX - width * 0.22, y: body.minY + 4, width: width * 0.44, height: height * 0.35))
        drawFace(on: body, state: state, facing: facing, in: context)
        return context.makeImage()
    }

    private static func drawCrest(_ crest: Crest, on body: CGRect, stage: Int, in context: CGContext, color: CGColor) {
        context.setFillColor(color)
        let top = body.maxY - 4
        let size = 8 + CGFloat(stage) * 4
        switch crest {
        case .leaf:
            for dx in [-size * 0.6, size * 0.6] {
                context.fillEllipse(in: CGRect(x: body.midX + dx - size / 2, y: top - 2, width: size, height: size * 1.4))
            }
        case .flame:
            context.move(to: CGPoint(x: body.midX - size, y: top - 4))
            context.addQuadCurve(to: CGPoint(x: body.midX, y: top + size * 1.8), control: CGPoint(x: body.midX - size, y: top + size))
            context.addQuadCurve(to: CGPoint(x: body.midX + size, y: top - 4), control: CGPoint(x: body.midX + size, y: top + size))
            context.fillPath()
        case .fin:
            context.move(to: CGPoint(x: body.midX - size * 0.4, y: top - 6))
            context.addLine(to: CGPoint(x: body.midX + size * 0.2, y: top + size * 1.3))
            context.addLine(to: CGPoint(x: body.midX + size * 0.8, y: top - 6))
            context.fillPath()
        case .bolt:
            for side in [-1.0, 1.0] {
                let x = body.midX + side * body.width * 0.28
                context.move(to: CGPoint(x: x - 5, y: top - 6))
                context.addLine(to: CGPoint(x: x + side * 4, y: top + size * 1.6))
                context.addLine(to: CGPoint(x: x + 5, y: top - 6))
                context.fillPath()
            }
        }
    }

    private static func drawFace(on body: CGRect, state: SpriteState, facing: Facing, in context: CGContext) {
        // Row 0 faces the viewer (straight down); rows turn counter-clockwise.
        let angle = (-90 + 45 * Double(facing.rawValue)) * .pi / 180
        let look = facing == .down ? CGPoint.zero : CGPoint(x: 2 * cos(angle), y: 2 * sin(angle))
        let eyeY = body.minY + body.height * 0.55
        let spacing = body.width * 0.18
        let ink = CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        context.setStrokeColor(ink)
        context.setLineWidth(2.5)
        context.setLineCap(.round)
        for dx in [-spacing, spacing] {
            let centre = CGPoint(x: body.midX + dx, y: eyeY)
            switch state {
            case .sleeping:
                context.move(to: CGPoint(x: centre.x - 4, y: centre.y))
                context.addLine(to: CGPoint(x: centre.x + 4, y: centre.y))
                context.strokePath()
            case .celebrating:
                context.addArc(center: CGPoint(x: centre.x, y: centre.y - 2), radius: 4, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                context.strokePath()
            case .idle, .hop, .wake, .sitting, .walking:
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fillEllipse(in: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10))
                context.setFillColor(ink)
                context.fillEllipse(in: CGRect(x: centre.x - 2.5 + look.x, y: centre.y - 3 + look.y, width: 5, height: 6))
            }
        }
    }
}

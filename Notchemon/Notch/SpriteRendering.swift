import CoreGraphics
import Foundation

/// The box a creature's opaque pixels cover, in pixels from its frame's
/// centre, x rightwards and y downwards. `right` and `bottom` are the edges
/// past the last opaque column and row, so `bottom - top` is the visible height.
struct Footprint: Sendable, Equatable {
    let left: Int
    let right: Int
    let top: Int
    let bottom: Int

    var height: Int { bottom - top }

    /// Half the width of a box centred on the frame that holds the creature
    /// facing either way, since the renderer mirrors frames to face right.
    var halfWidth: Int { max(-left, right) }

    func union(_ other: Footprint) -> Footprint {
        Footprint(left: min(left, other.left), right: max(right, other.right), top: min(top, other.top), bottom: max(bottom, other.bottom))
    }
}

/// One anim's pixels across its frames in every front facing, and how far
/// the renderer lifts it on top of them.
struct AnimBounds: Sendable, Equatable {
    let footprint: Footprint
    let lift: CGFloat
    /// The edge below each facing's lowest opaque row. Sheets draw some
    /// facings a pixel or two lower, so each one stands on its own.
    var bottoms: [Facing: Int] = [:]
}

/// Where a species' pixels fall, measured once per species. Each mode has
/// one scale for every anim, so switching anims never resizes the creature.
struct SpriteBounds: Sendable, Equatable {
    /// The idle frames facing the viewer.
    let rest: Footprint
    let anims: [SpriteState: AnimBounds]
}

enum SpriteFit: Sendable, Equatable {
    /// Below the notch: the resting creature fills the box. Taller frames,
    /// like a hop with its arc drawn in, rise up behind the notch.
    case peek
    /// In the panel: every anim the panel plays, plus the renderer's own
    /// motion, stays inside the box.
    case contain
}

struct SpritePlacement: Equatable {
    let bounds: SpriteBounds
    let pointsPerPixel: CGFloat

    /// How far the anim's frame centre sits above the box's bottom edge, in
    /// points, so that its lowest opaque row rests on that edge.
    func centreHeight(of state: SpriteState, facing: Facing) -> CGFloat {
        let anim = bounds.anims[state]
        return CGFloat(anim?.bottoms[facing] ?? anim?.footprint.bottom ?? bounds.rest.bottom) * pointsPerPixel
    }
}

/// The pure arithmetic behind `SpriteLayer`.
enum SpriteRendering {
    /// Key times for a discrete keyframe animation. Frame `i` shows from
    /// `keyTimes[i]` to `keyTimes[i + 1]`, so there is one more key time than
    /// frames and the last is 1.
    static func keyTimes(for durations: [TimeInterval]) -> [Double] {
        let total = durations.reduce(0, +)
        guard total > 0 else { return [0, 1] }
        var elapsed = 0.0
        var times: [Double] = []
        for duration in durations {
            times.append(elapsed / total)
            elapsed += duration
        }
        return times + [1]
    }

    /// The union of every frame's opaque pixels. Sprite sheets centre each
    /// frame on the creature whatever the frame's size (a tall hop frame has
    /// room above for the jump, not below the feet), so measuring from the
    /// centre keeps the frames of one anim in step with each other.
    static func footprint(of frames: [CGImage]) -> Footprint? {
        frames.compactMap(opaqueFootprint).reduce(nil) { union, next in union?.union(next) ?? next }
    }

    /// `rest` must not be empty. A species with nothing opaque at rest is
    /// measured by its whole idle frame, so it still gets a sensible scale.
    /// `anims` holds each anim's frames in every front facing.
    static func bounds(rest: [CGImage], anims: [SpriteState: [Facing: SpriteFrames]]) -> SpriteBounds {
        let first = rest[0]
        let resting = footprint(of: rest) ?? Footprint(
            left: -first.width / 2, right: first.width - first.width / 2,
            top: -first.height / 2, bottom: first.height - first.height / 2
        )
        var measured: [SpriteState: AnimBounds] = [:]
        for (state, facings) in anims {
            let footprints = facings.compactMapValues { footprint(of: $0.frames) }
            guard let union = footprints.values.reduce(nil, { union, next in union?.union(next) ?? next }) else { continue }
            measured[state] = AnimBounds(
                footprint: union,
                lift: facings.values.map { lift(state, $0) }.max() ?? 0,
                bottoms: footprints.mapValues(\.bottom)
            )
        }
        return SpriteBounds(rest: resting, anims: measured)
    }

    /// The renderer's own motion, in points, added on top of the frames.
    static let hopLift: CGFloat = 8
    static let wakeLift: CGFloat = 6
    static let celebrationLift: CGFloat = 10
    static let bobLift: CGFloat = 2
    static let facingLean: CGFloat = 3
    static let sidestep: ClosedRange<CGFloat> = 2...4

    static let maxSway = facingLean + sidestep.upperBound

    /// Frames that loop get their motion from the renderer: a one-shot
    /// borrowing them is lifted, and a single frame bobs.
    static func lift(_ state: SpriteState, _ frames: SpriteFrames) -> CGFloat {
        let motion: CGFloat = switch state {
        case .hop: hopLift
        case .wake: wakeLift
        case .celebrating: celebrationLift
        case .idle, .sleeping: 0
        }
        guard frames.loops else { return 0 }
        return motion + (frames.frames.count == 1 ? bobLift : 0)
    }

    static func placement(_ bounds: SpriteBounds, fit: SpriteFit, in box: CGSize, backingScale: CGFloat, pixelated: Bool) -> SpritePlacement {
        let points: CGFloat
        switch fit {
        case .peek:
            points = pointsPerPixel(visibleHeight: bounds.rest.height, boxHeight: box.height, backingScale: backingScale, pixelated: pixelated)
        case .contain:
            let played = bounds.anims.filter { SpriteChoreography.plays($0.key, panelExpanded: true) }.values
            let anims = played.isEmpty ? [AnimBounds(footprint: bounds.rest, lift: 0)] : Array(played)
            points = pointsPerPixel(containing: anims, in: box, backingScale: backingScale, pixelated: pixelated)
        }
        return SpritePlacement(bounds: bounds, pointsPerPixel: points)
    }

    /// How far the visible creature stops short of the top of its box, and
    /// how far a rounded-up scale may overshoot it.
    static let headroom: CGFloat = 4

    /// How many points one sprite pixel covers, so that `visibleHeight`
    /// pixels come out near `boxHeight - headroom` points. Pixel art gets a
    /// whole number of screen pixels per sprite pixel (half-point steps on
    /// Retina), never less than one, rounded to the nearest unless that
    /// overshoots the box by more than the headroom. Smooth art scales freely.
    static func pointsPerPixel(visibleHeight: Int, boxHeight: CGFloat, backingScale: CGFloat, pixelated: Bool) -> CGFloat {
        let visible = CGFloat(max(1, visibleHeight))
        let target = boxHeight - headroom
        guard pixelated else { return target / visible }
        var screenPixels = max(1, (target * backingScale / visible).rounded())
        if screenPixels > 1, screenPixels * visible / backingScale > boxHeight + headroom {
            screenPixels -= 1
        }
        return screenPixels / backingScale
    }

    /// The largest scale at which each anim, standing on the box's bottom
    /// edge and centred across it, stays inside the box with room for its
    /// lift above and the renderer's sway either side. Pixel art rounds down
    /// to whole screen pixels, never below one.
    static func pointsPerPixel(containing anims: [AnimBounds], in box: CGSize, backingScale: CGFloat, pixelated: Bool) -> CGFloat {
        let fit = anims.map { anim in
            min(
                (box.height - anim.lift) / CGFloat(max(1, anim.footprint.height)),
                (box.width / 2 - maxSway) / CGFloat(max(1, anim.footprint.halfWidth))
            )
        }.min() ?? 1
        guard pixelated else { return fit }
        return max(1, (fit * backingScale).rounded(.down)) / backingScale
    }

    /// Fainter pixels, like a soft shadow, are not the creature's body.
    static let opaqueAlpha: UInt8 = 64

    private static func opaqueFootprint(_ image: CGImage) -> Footprint? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var left = Int.max, right = Int.min, top = Int.max, bottom = Int.min
        // Memory row 0 is the image's top row.
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] >= opaqueAlpha {
                left = min(left, column)
                right = max(right, column)
                top = min(top, row)
                bottom = max(bottom, row)
            }
        }
        guard top <= bottom else { return nil }
        let centreX = width / 2
        let centreY = height / 2
        return Footprint(left: left - centreX, right: right + 1 - centreX, top: top - centreY, bottom: bottom + 1 - centreY)
    }
}

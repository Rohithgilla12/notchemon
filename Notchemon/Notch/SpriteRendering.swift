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

/// Where a species' pixels fall, measured once per species so every anim
/// and facing shares one scale and one anchor: switching them never resizes
/// the creature or moves where it stands.
struct SpriteBounds: Sendable, Equatable {
    /// The idle frames facing the viewer.
    let rest: Footprint
    /// Every frame of every anim in every facing the creature shows.
    let reach: Footprint
}

enum SpriteFit: Sendable, Equatable {
    /// Below the notch: the resting creature fills the box and stands on its
    /// bottom edge. Taller frames, like a hop with its arc drawn in, rise up
    /// behind the notch.
    case peek
    /// In the panel: every frame of every anim, plus the renderer's own
    /// motion, stays inside the box.
    case contain
}

struct SpritePlacement: Equatable {
    let pointsPerPixel: CGFloat
    /// How far the frames' centre sits above the box's bottom edge, in points.
    let centreHeight: CGFloat
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
    /// centre lets every anim of a species share one anchor.
    static func footprint(of frames: [CGImage]) -> Footprint? {
        frames.compactMap(opaqueFootprint).reduce(nil) { union, next in union?.union(next) ?? next }
    }

    /// `rest` must not be empty. A species with nothing opaque at rest is
    /// measured by its whole idle frame, so it still gets a sensible scale.
    static func bounds(rest: [CGImage], shown: [CGImage]) -> SpriteBounds {
        let first = rest[0]
        let resting = footprint(of: rest) ?? Footprint(
            left: -first.width / 2, right: first.width - first.width / 2,
            top: -first.height / 2, bottom: first.height - first.height / 2
        )
        return SpriteBounds(rest: resting, reach: footprint(of: shown).map(resting.union) ?? resting)
    }

    /// The renderer's own motion, in points, added on top of the frames.
    static let hopLift: CGFloat = 8
    static let wakeLift: CGFloat = 6
    static let celebrationLift: CGFloat = 10
    static let bobLift: CGFloat = 2
    static let facingLean: CGFloat = 3
    static let sidestep: ClosedRange<CGFloat> = 2...4

    static let maxLift = max(hopLift, wakeLift, celebrationLift, bobLift)
    static let maxSway = facingLean + sidestep.upperBound

    static func placement(_ bounds: SpriteBounds, fit: SpriteFit, in box: CGSize, backingScale: CGFloat, pixelated: Bool) -> SpritePlacement {
        let points: CGFloat
        let footprint: Footprint
        switch fit {
        case .peek:
            footprint = bounds.rest
            points = pointsPerPixel(visibleHeight: footprint.height, boxHeight: box.height, backingScale: backingScale, pixelated: pixelated)
        case .contain:
            footprint = bounds.reach
            points = pointsPerPixel(containing: footprint, in: box, backingScale: backingScale, pixelated: pixelated)
        }
        return SpritePlacement(pointsPerPixel: points, centreHeight: CGFloat(footprint.bottom) * points)
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

    /// The largest scale at which `footprint`, standing on the box's bottom
    /// edge and centred across it, stays inside the box with room for the
    /// renderer's lift above and sway either side. Pixel art rounds down to
    /// whole screen pixels, never below one.
    static func pointsPerPixel(containing footprint: Footprint, in box: CGSize, backingScale: CGFloat, pixelated: Bool) -> CGFloat {
        let fit = min(
            (box.height - maxLift) / CGFloat(max(1, footprint.height)),
            (box.width / 2 - maxSway) / CGFloat(max(1, footprint.halfWidth))
        )
        guard pixelated else { return fit }
        return max(1, (fit * backingScale).rounded(.down)) / backingScale
    }

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
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 0 {
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

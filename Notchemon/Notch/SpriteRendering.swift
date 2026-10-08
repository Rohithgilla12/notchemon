import CoreGraphics
import Foundation

/// The box a creature's opaque pixels cover, in pixels from its frame's
/// ground point, x rightwards and y downwards. `right` and `bottom` are the
/// edges past the last opaque column and row, so `bottom - top` is the
/// visible height and a positive `bottom` reaches below the ground line.
struct Footprint: Sendable, Equatable {
    let left: Int
    let right: Int
    let top: Int
    let bottom: Int

    var height: Int { bottom - top }

    /// Half the width of a box centred on the ground point that holds the
    /// creature facing either way, since the renderer mirrors frames to face right.
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
}

/// Where a species' pixels fall once every frame stands on the ground line,
/// measured once per species. Each mode has one scale and one ground line
/// for every anim, so switching anims or facings never resizes or moves it.
struct SpriteBounds: Sendable, Equatable {
    /// The idle frames facing the viewer.
    let rest: Footprint
    let anims: [SpriteState: AnimBounds]
    /// For frames without ground points: how far below the frame centre the
    /// ground lies, in pixels. It is where idle facing the viewer stands.
    let baseline: Int
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
    let pointsPerPixel: CGFloat
    /// How far the ground line every standing anim shares sits above the
    /// box's bottom edge, in points.
    let groundHeight: CGFloat
    let baseline: Int
    /// The lying loop's own ground line, which puts its lowest pixel on the
    /// box's bottom edge. Nil when the mode does not play it.
    var lyingGroundHeight: CGFloat? = nil

    func groundHeight(of state: SpriteState) -> CGFloat {
        state == .sitting ? lyingGroundHeight ?? groundHeight : groundHeight
    }

    /// Where each frame's centre goes so its ground point lands on the ground
    /// line of `state` midway across the box: points from that spot, y up.
    func centres(of frames: SpriteFrames, as state: SpriteState, mirrored: Bool) -> [CGPoint] {
        let ground = groundHeight(of: state)
        return zip(frames.frames, SpriteRendering.groundPoints(of: frames, baseline: baseline)).map { frame, point in
            let across = (CGFloat(frame.width) / 2 - point.x) * pointsPerPixel
            return CGPoint(
                x: mirrored ? -across : across,
                y: ground + (point.y - CGFloat(frame.height) / 2) * pointsPerPixel
            )
        }
    }
}

extension SpriteFrames {
    /// The same loop begun at frame `start`, so one pass from a held frame
    /// ends where it began.
    func starting(at start: Int) -> SpriteFrames {
        func rotated<Element>(_ elements: [Element]) -> [Element] {
            Array(elements[start...] + elements[..<start])
        }
        return SpriteFrames(
            frames: rotated(frames), durations: rotated(durations), pixelated: pixelated, directional: directional,
            loops: loops, attribution: attribution, groundPoints: groundPoints.map(rotated)
        )
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

    /// Frames without ground points stand where idle facing the viewer does,
    /// the frame's centre `baseline` pixels above the ground.
    static func groundPoints(of frames: SpriteFrames, baseline: Int) -> [CGPoint] {
        frames.groundPoints ?? frames.frames.map { CGPoint(x: CGFloat($0.width) / 2, y: CGFloat($0.height / 2 + baseline)) }
    }

    /// The union of every frame's opaque pixels, each frame measured from
    /// its own ground point.
    static func footprint(of frames: SpriteFrames, baseline: Int) -> Footprint? {
        zip(frames.frames, groundPoints(of: frames, baseline: baseline))
            .compactMap { frame, ground in opaqueBox(frame).map { registered($0, on: ground) } }
            .reduce(nil) { union, next in union?.union(next) ?? next }
    }

    /// A species with nothing opaque at rest is measured by its whole idle
    /// frame, so it still gets a sensible scale. `anims` holds each anim's
    /// frames in every front facing.
    static func bounds(rest: SpriteFrames, anims: [SpriteState: [Facing: SpriteFrames]]) -> SpriteBounds {
        let first = rest.frames[0]
        let whole = PixelBox(left: 0, right: first.width, top: 0, bottom: first.height)
        let lowest = rest.frames.compactMap { frame in opaqueBox(frame).map { $0.bottom - frame.height / 2 } }.max()
        let baseline = lowest ?? first.height - first.height / 2
        let resting = footprint(of: rest, baseline: baseline)
            ?? registered(whole, on: groundPoints(of: rest, baseline: baseline)[0])
        var measured: [SpriteState: AnimBounds] = [:]
        for (state, facings) in anims {
            let footprints = facings.values.compactMap { footprint(of: $0, baseline: baseline) }
            guard let union = footprints.reduce(nil, { union, next in union?.union(next) ?? next }) else { continue }
            measured[state] = AnimBounds(footprint: union, lift: facings.values.map { lift(state, $0) }.max() ?? 0)
        }
        return SpriteBounds(rest: resting, anims: measured, baseline: baseline)
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
        case .idle, .sleeping, .sitting, .walking: 0
        }
        guard frames.loops else { return 0 }
        return motion + (frames.frames.count == 1 ? bobLift : 0)
    }

    /// The shared ground line sits as far above the box's bottom edge as the
    /// lowest pixel of any standing anim the mode plays reaches below it, so
    /// that pixel touches the edge and nothing drops out of the box. A lying
    /// creature's tail can hang well below its ground point, so the lying
    /// loop stands on a line of its own and the standing anims keep theirs.
    static func placement(
        _ bounds: SpriteBounds, fit: SpriteFit, style: IdleStyle, in box: CGSize, backingScale: CGFloat, pixelated: Bool
    ) -> SpritePlacement {
        let played = bounds.anims.filter { SpriteChoreography.plays($0.key, panelExpanded: fit == .contain, style: style) }
        let lying = played[.sitting]
        let standing = [AnimBounds(footprint: bounds.rest, lift: 0)] + played.filter { $0.key != .sitting }.values
        let lowest = standing.map(\.footprint.bottom).max() ?? bounds.rest.bottom
        let points = switch fit {
        case .peek:
            pointsPerPixel(visibleHeight: bounds.rest.height, boxHeight: box.height, backingScale: backingScale, pixelated: pixelated)
        case .contain:
            min(
                pointsPerPixel(containing: standing, above: lowest, in: box, backingScale: backingScale, pixelated: pixelated),
                lying.map { pointsPerPixel(containing: [$0], above: $0.footprint.bottom, in: box, backingScale: backingScale, pixelated: pixelated) }
                    ?? .infinity
            )
        }
        return SpritePlacement(
            pointsPerPixel: points,
            groundHeight: CGFloat(lowest) * points,
            baseline: bounds.baseline,
            lyingGroundHeight: lying.map { CGFloat($0.footprint.bottom) * points }
        )
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

    /// The largest scale at which every anim, with the ground line `lowest`
    /// pixels above the box's bottom edge and centred across it, stays inside
    /// the box with room for its lift above and the renderer's sway either
    /// side. Pixel art rounds down to whole screen pixels, never below one.
    static func pointsPerPixel(containing anims: [AnimBounds], above lowest: Int, in box: CGSize, backingScale: CGFloat, pixelated: Bool) -> CGFloat {
        let fits: [CGFloat] = anims.map { (anim: AnimBounds) -> CGFloat in
            let rise = CGFloat(max(1, lowest - anim.footprint.top))
            let reach = CGFloat(max(1, anim.footprint.halfWidth))
            let tall: CGFloat = (box.height - anim.lift) / rise
            let wide: CGFloat = (box.width / 2 - maxSway) / reach
            return min(tall, wide)
        }
        let fit: CGFloat = fits.min() ?? 1
        guard pixelated else { return fit }
        return max(1, (fit * backingScale).rounded(.down)) / backingScale
    }

    /// Fainter pixels, like a soft shadow, are not the creature's body.
    static let opaqueAlpha: UInt8 = 64

    /// Edges in pixels from the frame's top-left corner.
    private struct PixelBox {
        let left: Int
        let right: Int
        let top: Int
        let bottom: Int
    }

    /// Whole pixels outward, so a ground point between two pixels still
    /// counts the full width of the creature.
    private static func registered(_ box: PixelBox, on ground: CGPoint) -> Footprint {
        Footprint(
            left: Int((CGFloat(box.left) - ground.x).rounded(.down)),
            right: Int((CGFloat(box.right) - ground.x).rounded(.up)),
            top: Int((CGFloat(box.top) - ground.y).rounded(.down)),
            bottom: Int((CGFloat(box.bottom) - ground.y).rounded(.up))
        )
    }

    private static func opaqueBox(_ image: CGImage) -> PixelBox? {
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
        return PixelBox(left: left, right: right + 1, top: top, bottom: bottom + 1)
    }
}

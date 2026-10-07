import CoreGraphics
import Foundation

/// The rows a creature's opaque pixels cover, in pixels from its frame's
/// vertical centre, positive downwards. `bottom` is the edge below the
/// lowest opaque row, so `bottom - top` is the visible height.
struct Footprint: Sendable, Equatable {
    let top: Int
    let bottom: Int

    var height: Int { bottom - top }
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

    /// The union of every frame's opaque rows. Sprite sheets centre each frame
    /// on the creature whatever the frame's size (a tall hop frame has room
    /// above for the jump, not below the feet), so measuring from the centre
    /// lets every anim of a species share one anchor.
    static func footprint(of frames: [CGImage]) -> Footprint? {
        var top = Int.max
        var bottom = Int.min
        for frame in frames {
            guard let rows = opaqueRows(frame) else { continue }
            let centre = frame.height / 2
            top = min(top, rows.lowerBound - centre)
            bottom = max(bottom, rows.upperBound + 1 - centre)
        }
        return top <= bottom ? Footprint(top: top, bottom: bottom) : nil
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

    /// Image rows (0 at the top) that hold any pixel with alpha.
    private static func opaqueRows(_ image: CGImage) -> ClosedRange<Int>? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let opaque = (0..<height).filter { row in
            (0..<width).contains { column in pixels[(row * width + column) * 4 + 3] > 0 }
        }
        guard let first = opaque.first, let last = opaque.last else { return nil }
        return first...last
    }
}

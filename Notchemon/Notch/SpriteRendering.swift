import CoreGraphics
import Foundation

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

    /// How many points one sprite pixel covers, chosen so a frame of
    /// `referenceHeight` pixels fits `boxHeight`. Pixel art gets a whole
    /// number of screen pixels per sprite pixel, never less than one, so it
    /// stays crisp; smooth art scales freely.
    static func pointsPerPixel(referenceHeight: Int, boxHeight: CGFloat, backingScale: CGFloat, pixelated: Bool) -> CGFloat {
        let reference = CGFloat(max(1, referenceHeight))
        guard pixelated else { return boxHeight / reference }
        let screenPixels = max(1, (boxHeight * backingScale / reference).rounded(.down))
        return screenPixels / backingScale
    }
}

import Foundation
import ImageIO

enum SpriteDecoder {
    static let defaultFrameDuration: TimeInterval = 0.1
    /// Browsers clamp GIF delays below 20 ms the same way.
    static let minimumFrameDuration: TimeInterval = 0.02

    /// Decodes a GIF into all its frames with their own delays, or a still
    /// image into one frame. The result faces left and loops.
    static func decode(_ data: Data) -> SpriteFrames? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var frames: [CGImage] = []
        var durations: [TimeInterval] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(image)
            durations.append(max(minimumFrameDuration, gifDelay(source, index) ?? defaultFrameDuration))
        }
        guard !frames.isEmpty else { return nil }
        return SpriteFrames(frames: frames, durations: durations)
    }

    static func firstImage(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    private static func gifDelay(_ source: CGImageSource, _ index: Int) -> TimeInterval? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return nil }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
        return delay.flatMap { $0 > 0 ? $0 : nil }
    }
}

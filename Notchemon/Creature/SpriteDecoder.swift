import Foundation
import ImageIO

enum SpriteDecoder {
    static let defaultFrameDuration: TimeInterval = 0.1

    /// Decodes a GIF into all its frames, or a still image into one frame.
    /// GIFs carry a delay per frame; the renderer plays at their mean.
    static func decode(_ data: Data) -> SpriteFrames? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [CGImage] = []
        var delays: [TimeInterval] = []
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(image)
            if let delay = gifDelay(source, index) { delays.append(delay) }
        }
        guard !frames.isEmpty else { return nil }
        let mean = delays.isEmpty ? defaultFrameDuration : delays.reduce(0, +) / Double(delays.count)
        return SpriteFrames(frames: frames, frameDuration: max(0.02, mean))
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

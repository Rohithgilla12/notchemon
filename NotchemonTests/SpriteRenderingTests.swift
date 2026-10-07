import CoreGraphics
import Testing
@testable import Notchemon

struct SpriteRenderingTests {
    @Test func keyTimesStartEachFrameAtItsShareOfTheTotal() {
        #expect(SpriteRendering.keyTimes(for: [0.1, 0.3, 0.6]) == [0, 0.1, 0.4, 1])
        #expect(SpriteRendering.keyTimes(for: [0.5]) == [0, 1])
    }

    @Test func pixelArtGetsTheLargestWholeScreenPixelScaleThatFits() {
        // A 40 px idle in a 48 pt box on a 2x display: 2 screen px per sprite px.
        #expect(SpriteRendering.pointsPerPixel(referenceHeight: 40, boxHeight: 48, backingScale: 2, pixelated: true) == 1)
        #expect(SpriteRendering.pointsPerPixel(referenceHeight: 24, boxHeight: 48, backingScale: 2, pixelated: true) == 2)
        #expect(SpriteRendering.pointsPerPixel(referenceHeight: 30, boxHeight: 48, backingScale: 2, pixelated: true) == 1.5)
        #expect(SpriteRendering.pointsPerPixel(referenceHeight: 30, boxHeight: 48, backingScale: 1, pixelated: true) == 1)
    }

    @Test func tooTallPixelArtNeverDropsBelowOneScreenPixel() {
        #expect(SpriteRendering.pointsPerPixel(referenceHeight: 136, boxHeight: 48, backingScale: 2, pixelated: true) == 0.5)
    }

    @Test func smoothArtScalesToFitExactly() {
        #expect(SpriteRendering.pointsPerPixel(referenceHeight: 96, boxHeight: 48, backingScale: 2, pixelated: false) == 0.5)
    }
}

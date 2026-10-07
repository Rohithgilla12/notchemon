import CoreGraphics
import Testing
@testable import Notchemon

struct SpriteRenderingTests {
    @Test func keyTimesStartEachFrameAtItsShareOfTheTotal() {
        #expect(SpriteRendering.keyTimes(for: [0.1, 0.3, 0.6]) == [0, 0.1, 0.4, 1])
        #expect(SpriteRendering.keyTimes(for: [0.5]) == [0, 1])
    }

    @Test func pixelArtAimsForFortyPointsInTheCollapsedPeekInWholeScreenPixels() {
        let peek = NotchGeometry.peekHeight
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: 20, boxHeight: peek, backingScale: 2, pixelated: true) == 2)
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: 30, boxHeight: peek, backingScale: 2, pixelated: true) == 1.5)
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: 36, boxHeight: peek, backingScale: 2, pixelated: true) == 1)
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: 30, boxHeight: peek, backingScale: 1, pixelated: true) == 1)
    }

    @Test func roundingUpNeverOvershootsTheBoxByMoreThanTheHeadroom() {
        // 53 px at the nearest scale (2 screen px) would be 53 pt in a 44 pt peek.
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: 53, boxHeight: 44, backingScale: 2, pixelated: true) == 0.5)
    }

    @Test func tooTallPixelArtNeverDropsBelowOneScreenPixel() {
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: 136, boxHeight: 44, backingScale: 2, pixelated: true) == 0.5)
    }

    @Test func expandedSlotIsRoughlyTwoAndAHalfTimesTheCollapsedSize() {
        let collapsed = SpriteRendering.pointsPerPixel(visibleHeight: 20, boxHeight: NotchGeometry.peekHeight, backingScale: 2, pixelated: true)
        let expanded = SpriteRendering.pointsPerPixel(visibleHeight: 20, boxHeight: PanelMetrics.expandedSpriteSide, backingScale: 2, pixelated: true)
        #expect(expanded / collapsed >= 2.2 && expanded / collapsed <= 2.6)
    }

    @Test func smoothArtScalesToTheTargetExactly() {
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: 80, boxHeight: 44, backingScale: 2, pixelated: false) == 0.5)
    }

    @Test func paddedFrameScalesByItsVisibleHeightNotItsSize() throws {
        // A 56-row frame whose creature fills only rows 10...29: 20 px visible.
        let footprint = try #require(SpriteRendering.footprint(of: [Self.frame(height: 56, opaque: 10...29)]))
        #expect(footprint == Footprint(top: -18, bottom: 2))
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: footprint.height, boxHeight: NotchGeometry.peekHeight, backingScale: 2, pixelated: true) == 2)
    }

    @Test func footprintIsMeasuredFromEachFrameCentre() {
        // A 10-row frame with rows 3...6 opaque, and a 30-row frame (room to
        // jump above) with rows 12...16 opaque: both centred on the creature.
        let idle = Self.frame(height: 10, opaque: 3...6)
        let hop = Self.frame(height: 30, opaque: 12...16)
        #expect(SpriteRendering.footprint(of: [idle]) == Footprint(top: -2, bottom: 2))
        #expect(SpriteRendering.footprint(of: [idle, hop]) == Footprint(top: -3, bottom: 2))
        #expect(SpriteRendering.footprint(of: [Self.frame(height: 8, opaque: nil)]) == nil)
    }

    private static func frame(height: Int, opaque rows: ClosedRange<Int>?) -> CGImage {
        let context = CGContext(data: nil, width: 4, height: height, bitsPerComponent: 8, bytesPerRow: 16,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let rows {
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            // Rows count from the top; the context's origin is bottom-left.
            context.fill(CGRect(x: 0, y: height - rows.upperBound - 1, width: 4, height: rows.count))
        }
        return context.makeImage()!
    }
}

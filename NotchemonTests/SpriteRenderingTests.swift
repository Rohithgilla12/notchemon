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
        #expect(footprint == Footprint(left: -2, right: 2, top: -18, bottom: 2))
        #expect(SpriteRendering.pointsPerPixel(visibleHeight: footprint.height, boxHeight: NotchGeometry.peekHeight, backingScale: 2, pixelated: true) == 2)
    }

    @Test func footprintIsMeasuredFromEachFrameCentre() {
        // A 10-row frame with rows 3...6 opaque, and a 30-row frame (room to
        // jump above) with rows 12...16 opaque: both centred on the creature.
        let idle = Self.frame(height: 10, opaque: 3...6)
        let hop = Self.frame(height: 30, opaque: 12...16)
        #expect(SpriteRendering.footprint(of: [idle]) == Footprint(left: -2, right: 2, top: -2, bottom: 2))
        #expect(SpriteRendering.footprint(of: [idle, hop]) == Footprint(left: -2, right: 2, top: -3, bottom: 2))
        #expect(SpriteRendering.footprint(of: [Self.frame(height: 8, opaque: nil)]) == nil)
    }

    @Test func footprintMeasuresColumnsFromTheCentreAndMirrorsForWidth() throws {
        // A 20-column frame with columns 4...11 opaque: 6 left of centre, 2 right.
        let footprint = try #require(SpriteRendering.footprint(of: [Self.frame(width: 20, height: 10, opaque: 3...6, columns: 4...11)]))
        #expect(footprint == Footprint(left: -6, right: 2, top: -2, bottom: 2))
        #expect(footprint.halfWidth == 6)
    }

    @Test func boundsReachCoversEveryShownFrameAndRestStaysTheIdle() {
        let idle = Self.frame(height: 10, opaque: 3...6)
        let hop = Self.frame(height: 30, opaque: 2...16)
        let bounds = SpriteRendering.bounds(rest: [idle], shown: [idle, hop])
        #expect(bounds.rest == Footprint(left: -2, right: 2, top: -2, bottom: 2))
        #expect(bounds.reach == Footprint(left: -2, right: 2, top: -13, bottom: 2))
    }

    @Test func transparentRestIsMeasuredByItsWholeFrame() {
        let bounds = SpriteRendering.bounds(rest: [Self.frame(height: 8, opaque: nil)], shown: [])
        #expect(bounds.rest == Footprint(left: -2, right: 2, top: -4, bottom: 4))
        #expect(bounds.reach == bounds.rest)
    }

    @Test func peekFitsTheRestingCreatureAndLetsTheReachRiseAbove() {
        let bounds = SpriteBounds(
            rest: Footprint(left: -20, right: 20, top: -25, bottom: 5),
            reach: Footprint(left: -20, right: 20, top: -44, bottom: 15)
        )
        let box = CGSize(width: NotchGeometry.peekHeight, height: NotchGeometry.peekHeight)
        let placement = SpriteRendering.placement(bounds, fit: .peek, in: box, backingScale: 2, pixelated: true)
        #expect(placement == SpritePlacement(pointsPerPixel: 1.5, centreHeight: 7.5))
    }

    /// Measured from the 100 pt panel slot: idle 30 px tall, a hop arc
    /// reaching 44 px above the frame centre, and a wake anim lying 15 px below it.
    @Test(arguments: [
        Footprint(left: -20, right: 20, top: -44, bottom: 15),
        Footprint(left: -14, right: 16, top: -37, bottom: 7),
        Footprint(left: -40, right: 10, top: -10, bottom: 10),
        Footprint(left: -3, right: 3, top: -5, bottom: 1),
    ])
    func containKeepsEveryFrameAndTheRenderersMotionInsideTheSlot(reach: Footprint) {
        let bounds = SpriteBounds(rest: reach, reach: reach)
        let box = CGSize(width: PanelMetrics.expandedSpriteSide, height: PanelMetrics.expandedSpriteSide)
        for pixelated in [true, false] {
            let placement = SpriteRendering.placement(bounds, fit: .contain, in: box, backingScale: 2, pixelated: pixelated)
            let points = placement.pointsPerPixel
            // y up from the slot's bottom edge; footprint rows count downwards.
            let lowest = placement.centreHeight - CGFloat(reach.bottom) * points
            let highest = placement.centreHeight - CGFloat(reach.top) * points
            let rounding = 1e-9
            #expect(lowest == 0)
            #expect(highest + SpriteRendering.maxLift <= box.height + rounding)
            #expect(CGFloat(reach.halfWidth) * points + SpriteRendering.maxSway <= box.width / 2 + rounding)
        }
    }

    @Test func containUsesTheSlotsFullHeightLessTheRenderersLift() {
        let reach = Footprint(left: -10, right: 10, top: -40, bottom: 5)
        let box = CGSize(width: PanelMetrics.expandedSpriteSide, height: PanelMetrics.expandedSpriteSide)
        let placement = SpriteRendering.placement(SpriteBounds(rest: reach, reach: reach), fit: .contain, in: box, backingScale: 2, pixelated: true)
        #expect(placement.pointsPerPixel == 2)
        #expect(CGFloat(reach.height) * placement.pointsPerPixel == box.height - SpriteRendering.maxLift)
    }

    @Test func containNeverDropsPixelArtBelowOneScreenPixel() {
        let huge = Footprint(left: -300, right: 300, top: -300, bottom: 300)
        let box = CGSize(width: 100, height: 100)
        #expect(SpriteRendering.pointsPerPixel(containing: huge, in: box, backingScale: 2, pixelated: true) == 0.5)
    }

    private static func frame(width: Int = 4, height: Int, opaque rows: ClosedRange<Int>?, columns: ClosedRange<Int>? = nil) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let rows {
            let columns = columns ?? 0...(width - 1)
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            // Rows count from the top; the context's origin is bottom-left.
            context.fill(CGRect(x: columns.lowerBound, y: height - rows.upperBound - 1, width: columns.count, height: rows.count))
        }
        return context.makeImage()!
    }
}

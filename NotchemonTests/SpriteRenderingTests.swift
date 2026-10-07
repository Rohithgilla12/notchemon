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

    @Test func eachAnimIsMeasuredAcrossItsFacingsAndStandsOnEachFacingsLowestRow() {
        let idle = SpriteFrames(frames: [Self.frame(height: 10, opaque: 3...6), Self.frame(height: 10, opaque: 2...6)], durations: [1, 1])
        let wakeDown = SpriteFrames(frames: [Self.frame(height: 20, opaque: 4...17)], durations: [1], loops: false)
        let wakeLeft = SpriteFrames(frames: [Self.frame(width: 20, height: 20, opaque: 6...12, columns: 1...12)], durations: [1], loops: false)
        let poseFallback = SpriteFrames(frames: [Self.frame(height: 10, opaque: 3...6), Self.frame(height: 10, opaque: 3...6)], durations: [1, 1])
        let bounds = SpriteRendering.bounds(rest: idle.frames, anims: [.idle: [.down: idle], .wake: [.down: wakeDown, .left: wakeLeft], .celebrating: [.down: poseFallback]])
        #expect(bounds.rest == Footprint(left: -2, right: 2, top: -3, bottom: 2))
        #expect(bounds.anims[.idle] == AnimBounds(footprint: Footprint(left: -2, right: 2, top: -3, bottom: 2), lift: 0, bottoms: [.down: 2]))
        #expect(bounds.anims[.wake] == AnimBounds(footprint: Footprint(left: -9, right: 3, top: -6, bottom: 8), lift: 0, bottoms: [.down: 8, .left: 3]))
        #expect(bounds.anims[.celebrating] == AnimBounds(footprint: Footprint(left: -2, right: 2, top: -2, bottom: 2), lift: SpriteRendering.celebrationLift, bottoms: [.down: 2]))
        #expect(bounds.anims[.hop] == nil)
    }

    @Test func singleFrameLoopsBob() {
        let still = SpriteFrames(frames: [Self.frame(height: 10, opaque: 3...6)], durations: [1])
        #expect(SpriteRendering.lift(.idle, still) == SpriteRendering.bobLift)
        #expect(SpriteRendering.lift(.hop, still) == SpriteRendering.hopLift + SpriteRendering.bobLift)
    }

    @Test func faintPixelsAreNotTheCreature() {
        // Rows 3...6 are solid; rows 7...9 are a shadow at alpha 0.2.
        let context = CGContext(data: nil, width: 4, height: 10, bitsPerComponent: 8, bytesPerRow: 16,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.2))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 3, width: 4, height: 4))
        #expect(SpriteRendering.footprint(of: [context.makeImage()!]) == Footprint(left: -2, right: 2, top: -2, bottom: 2))
    }

    @Test func transparentRestIsMeasuredByItsWholeFrame() {
        let bounds = SpriteRendering.bounds(rest: [Self.frame(height: 8, opaque: nil)], anims: [:])
        #expect(bounds.rest == Footprint(left: -2, right: 2, top: -4, bottom: 4))
        #expect(bounds.anims.isEmpty)
    }

    /// Shaped like a real species: idle 32 px tall across its facings, with
    /// the feet 5 px below the frame centre facing the viewer and 7 px on the
    /// diagonals, a hop arc 51 px tall, and a wake whose first frame reaches
    /// 15 px below the centre.
    static let measured = SpriteBounds(
        rest: Footprint(left: -14, right: 14, top: -25, bottom: 5),
        anims: [
            .idle: AnimBounds(footprint: Footprint(left: -20, right: 20, top: -25, bottom: 7), lift: 0, bottoms: [.down: 5, .downLeft: 7]),
            .sleeping: AnimBounds(footprint: Footprint(left: -8, right: 16, top: -17, bottom: 7), lift: 0),
            .celebrating: AnimBounds(footprint: Footprint(left: -11, right: 14, top: -20, bottom: 6), lift: 0),
            .hop: AnimBounds(footprint: Footprint(left: -20, right: 20, top: -44, bottom: 7), lift: 0),
            .wake: AnimBounds(footprint: Footprint(left: -18, right: 18, top: -18, bottom: 15), lift: 0),
        ]
    )

    @Test func peekSizesTheRestingCreatureAndStandsEachAnimOnItsOwnLowestRow() {
        let box = CGSize(width: NotchGeometry.peekHeight, height: NotchGeometry.peekHeight)
        let placement = SpriteRendering.placement(Self.measured, fit: .peek, in: box, backingScale: 2, pixelated: true)
        #expect(placement.pointsPerPixel == 1.5)
        #expect(placement.centreHeight(of: .idle, facing: .down) == 7.5)
        #expect(placement.centreHeight(of: .idle, facing: .downLeft) == 10.5)
        #expect(placement.centreHeight(of: .hop, facing: .down) == 10.5)
        #expect(placement.centreHeight(of: .wake, facing: .down) == 22.5)
    }

    @Test func containLeavesTheHopOutBecauseThePanelNeverPlaysIt() {
        let box = PanelMetrics.expandedSpriteSize
        let placement = SpriteRendering.placement(Self.measured, fit: .contain, in: box, backingScale: 2, pixelated: true)
        // 33 wake rows at 3 pt fill 99 of 100 pt; the 51-row hop would allow only 1.5.
        #expect(placement.pointsPerPixel == 3)
        #expect(placement.centreHeight(of: .wake, facing: .down) == 45)
        #expect(placement.centreHeight(of: .idle, facing: .down) == 15)
        #expect(placement.centreHeight(of: .idle, facing: .downLeft) == 21)
    }

    @Test func expandedCreatureIsAboutTwiceTheCollapsedOne() {
        let peek = CGSize(width: NotchGeometry.peekHeight, height: NotchGeometry.peekHeight)
        let collapsed = SpriteRendering.placement(Self.measured, fit: .peek, in: peek, backingScale: 2, pixelated: true)
        let expanded = SpriteRendering.placement(Self.measured, fit: .contain, in: PanelMetrics.expandedSpriteSize, backingScale: 2, pixelated: true)
        #expect(expanded.pointsPerPixel / collapsed.pointsPerPixel >= 2)
        #expect(CGFloat(Self.measured.rest.height) * expanded.pointsPerPixel >= 90)
    }

    @Test(arguments: [
        AnimBounds(footprint: Footprint(left: -20, right: 20, top: -18, bottom: 15), lift: 0),
        AnimBounds(footprint: Footprint(left: -14, right: 16, top: -37, bottom: 7), lift: 6),
        AnimBounds(footprint: Footprint(left: -40, right: 10, top: -10, bottom: 10), lift: 2),
        AnimBounds(footprint: Footprint(left: -3, right: 3, top: -5, bottom: 1), lift: 10),
    ])
    func containKeepsEachAnimAndItsMotionInsideTheSlot(anim: AnimBounds) {
        let bounds = SpriteBounds(rest: anim.footprint, anims: [.idle: anim])
        let box = PanelMetrics.expandedSpriteSize
        for pixelated in [true, false] {
            let placement = SpriteRendering.placement(bounds, fit: .contain, in: box, backingScale: 2, pixelated: pixelated)
            let points = placement.pointsPerPixel
            // y up from the slot's bottom edge; footprint rows count downwards.
            let lowest = placement.centreHeight(of: .idle, facing: .down) - CGFloat(anim.footprint.bottom) * points
            let highest = placement.centreHeight(of: .idle, facing: .down) - CGFloat(anim.footprint.top) * points
            let rounding = 1e-9
            #expect(lowest == 0)
            #expect(highest + anim.lift <= box.height + rounding)
            #expect(CGFloat(anim.footprint.halfWidth) * points + SpriteRendering.maxSway <= box.width / 2 + rounding)
        }
    }

    @Test func containPicksTheScaleFromWhicheverDimensionBinds() {
        let tall = AnimBounds(footprint: Footprint(left: -5, right: 5, top: -45, bottom: 5), lift: 0)
        let wide = AnimBounds(footprint: Footprint(left: -30, right: 2, top: -5, bottom: 5), lift: 0)
        let box = CGSize(width: 136, height: 100)
        #expect(SpriteRendering.pointsPerPixel(containing: [tall], in: box, backingScale: 2, pixelated: true) == 2)
        #expect(SpriteRendering.pointsPerPixel(containing: [wide], in: box, backingScale: 2, pixelated: true) == 2)
        #expect(SpriteRendering.pointsPerPixel(containing: [tall, wide], in: CGSize(width: 100, height: 100), backingScale: 2, pixelated: true) == 1)
    }

    @Test func containNeverDropsPixelArtBelowOneScreenPixel() {
        let huge = AnimBounds(footprint: Footprint(left: -300, right: 300, top: -300, bottom: 300), lift: 0)
        #expect(SpriteRendering.pointsPerPixel(containing: [huge], in: CGSize(width: 100, height: 100), backingScale: 2, pixelated: true) == 0.5)
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

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

    @Test func footprintIsMeasuredFromEachFramesGroundPoint() {
        // A 10-row frame standing on row 7, and a 30-row hop frame whose
        // ground point is row 25 with the creature drawn high above it.
        let idle = SpriteFrames(frames: [Self.frame(height: 10, opaque: 3...6)], durations: [1], groundPoints: [CGPoint(x: 2, y: 7)])
        let hop = SpriteFrames(frames: [Self.frame(height: 30, opaque: 2...9)], durations: [1], groundPoints: [CGPoint(x: 2, y: 25)])
        let both = SpriteFrames(frames: idle.frames + hop.frames, durations: [1, 1], groundPoints: [CGPoint(x: 2, y: 7), CGPoint(x: 2, y: 25)])
        #expect(SpriteRendering.footprint(of: idle, baseline: 0) == Footprint(left: -2, right: 2, top: -4, bottom: 0))
        #expect(SpriteRendering.footprint(of: hop, baseline: 0) == Footprint(left: -2, right: 2, top: -23, bottom: -15))
        #expect(SpriteRendering.footprint(of: both, baseline: 0) == Footprint(left: -2, right: 2, top: -23, bottom: 0))
        #expect(SpriteRendering.footprint(of: SpriteFrames(frames: [Self.frame(height: 8, opaque: nil)], durations: [1]), baseline: 0) == nil)
    }

    @Test func footprintMeasuresColumnsFromTheGroundPointAndMirrorsForWidth() throws {
        // A 20-column frame with columns 4...11 opaque and its ground point at column 10.
        let frames = SpriteFrames(frames: [Self.frame(width: 20, height: 10, opaque: 3...6, columns: 4...11)], durations: [1], groundPoints: [CGPoint(x: 10, y: 7)])
        let footprint = try #require(SpriteRendering.footprint(of: frames, baseline: 0))
        #expect(footprint == Footprint(left: -6, right: 2, top: -4, bottom: 0))
        #expect(footprint.halfWidth == 6)
    }

    @Test func framesWithoutGroundPointsStandWhereIdleFacingTheViewerStands() {
        // Idle's lowest row is row 6 of 10, 2 rows below the centre. A wake
        // frame with no ground points then stands 2 rows below its own centre.
        let idle = SpriteFrames(frames: [Self.frame(height: 10, opaque: 3...6), Self.frame(height: 10, opaque: 2...5)], durations: [1, 1])
        let wake = SpriteFrames(frames: [Self.frame(height: 20, opaque: 4...14)], durations: [1], loops: false)
        let bounds = SpriteRendering.bounds(rest: idle, anims: [.idle: [.down: idle], .wake: [.down: wake]])
        #expect(bounds.baseline == 2)
        #expect(SpriteRendering.groundPoints(of: wake, baseline: bounds.baseline) == [CGPoint(x: 2, y: 12)])
        #expect(bounds.rest == Footprint(left: -2, right: 2, top: -5, bottom: 0))
        #expect(bounds.anims[.wake] == AnimBounds(footprint: Footprint(left: -2, right: 2, top: -8, bottom: 3), lift: 0))
    }

    @Test func eachAnimIsMeasuredAcrossItsFacings() {
        let idle = SpriteFrames(frames: [Self.frame(height: 10, opaque: 3...6)], durations: [1], groundPoints: [CGPoint(x: 2, y: 7)])
        let wakeDown = SpriteFrames(frames: [Self.frame(height: 20, opaque: 4...17)], durations: [1], loops: false, groundPoints: [CGPoint(x: 2, y: 14)])
        let wakeLeft = SpriteFrames(frames: [Self.frame(width: 20, height: 20, opaque: 6...12, columns: 1...12)], durations: [1], loops: false, groundPoints: [CGPoint(x: 10, y: 14)])
        let poseFallback = SpriteFrames(frames: idle.frames, durations: [1], groundPoints: [CGPoint(x: 2, y: 7)])
        let bounds = SpriteRendering.bounds(rest: idle, anims: [.idle: [.down: idle], .wake: [.down: wakeDown, .left: wakeLeft], .celebrating: [.down: poseFallback]])
        #expect(bounds.anims[.idle] == AnimBounds(footprint: Footprint(left: -2, right: 2, top: -4, bottom: 0), lift: SpriteRendering.bobLift))
        #expect(bounds.anims[.wake] == AnimBounds(footprint: Footprint(left: -9, right: 3, top: -10, bottom: 4), lift: 0))
        #expect(bounds.anims[.celebrating] == AnimBounds(footprint: Footprint(left: -2, right: 2, top: -4, bottom: 0), lift: SpriteRendering.celebrationLift + SpriteRendering.bobLift))
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
        let frames = SpriteFrames(frames: [context.makeImage()!], durations: [1], groundPoints: [CGPoint(x: 2, y: 7)])
        #expect(SpriteRendering.footprint(of: frames, baseline: 0) == Footprint(left: -2, right: 2, top: -4, bottom: 0))
    }

    @Test func transparentRestIsMeasuredByItsWholeFrame() {
        let bounds = SpriteRendering.bounds(rest: SpriteFrames(frames: [Self.frame(height: 8, opaque: nil)], durations: [1]), anims: [:])
        #expect(bounds.rest == Footprint(left: -2, right: 2, top: -8, bottom: 0))
        #expect(bounds.anims.isEmpty)
    }

    @Test func everyFrameStandsItsGroundPointOnTheGroundLine() {
        // Frames of different sizes whose ground points sit in different
        // places: each centre moves so its ground point lands on one spot.
        let placement = SpritePlacement(pointsPerPixel: 3, groundHeight: 30, baseline: 0)
        let frames = SpriteFrames(
            frames: [Self.frame(width: 40, height: 40, opaque: nil), Self.frame(width: 40, height: 40, opaque: nil)],
            durations: [1, 1],
            groundPoints: [CGPoint(x: 20, y: 24), CGPoint(x: 18, y: 31)]
        )
        #expect(placement.centres(of: frames, mirrored: false) == [CGPoint(x: 0, y: 42), CGPoint(x: 6, y: 63)])
        #expect(placement.centres(of: frames, mirrored: true) == [CGPoint(x: 0, y: 42), CGPoint(x: -6, y: 63)])
        let tall = SpriteFrames(frames: [Self.frame(width: 40, height: 88, opaque: nil)], durations: [1], groundPoints: [CGPoint(x: 20, y: 48)])
        #expect(placement.centres(of: tall, mirrored: false) == [CGPoint(x: 0, y: 42)])
    }

    @Test func wakeHandsOverToIdleWithoutAJump() throws {
        // A wake whose first frame curls its tail 11 rows below the ground,
        // then stands with its feet 2 rows below it, and an idle in a frame
        // of another size with its feet 1 row below the ground.
        let wake = SpriteFrames(
            frames: [Self.frame(height: 40, opaque: 12...34), Self.frame(height: 40, opaque: 2...25)],
            durations: [1, 1], loops: false, groundPoints: [CGPoint(x: 2, y: 24), CGPoint(x: 2, y: 24)]
        )
        let idle = SpriteFrames(frames: [Self.frame(height: 56, opaque: 8...32)], durations: [1], groundPoints: [CGPoint(x: 2, y: 32)])
        let bounds = SpriteRendering.bounds(rest: idle, anims: [.idle: [.down: idle], .wake: [.down: wake]])
        let placement = SpriteRendering.placement(bounds, fit: .contain, in: PanelMetrics.expandedSpriteSize, backingScale: 2, pixelated: true)
        let feet = { (frames: SpriteFrames, index: Int, lowestRow: Int) -> CGFloat in
            placement.centres(of: frames, mirrored: false)[index].y - (CGFloat(lowestRow + 1) - CGFloat(frames.frames[index].height) / 2) * placement.pointsPerPixel
        }
        #expect(feet(wake, 0, 34) == 0)
        #expect(feet(wake, 1, 25) == placement.groundHeight - 2 * placement.pointsPerPixel)
        #expect(feet(idle, 0, 32) == placement.groundHeight - 1 * placement.pointsPerPixel)
    }

    /// Registered on the ground points of a real species: idle facing the
    /// viewer 30 rows tall with its feet a row below the ground, idle turned
    /// to the side 2 rows lower, a hop arc 48 rows above the ground, and a
    /// wake whose first frame curls its tail 11 rows below it.
    static let measured = SpriteBounds(
        rest: Footprint(left: -9, right: 11, top: -29, bottom: 1),
        anims: [
            .idle: AnimBounds(footprint: Footprint(left: -20, right: 20, top: -29, bottom: 3), lift: 0),
            .sleeping: AnimBounds(footprint: Footprint(left: -8, right: 16, top: -21, bottom: 3), lift: 0),
            .celebrating: AnimBounds(footprint: Footprint(left: -11, right: 14, top: -24, bottom: 2), lift: 0),
            .hop: AnimBounds(footprint: Footprint(left: -20, right: 20, top: -48, bottom: 3), lift: 0),
            .wake: AnimBounds(footprint: Footprint(left: -18, right: 18, top: -22, bottom: 11), lift: 0),
        ],
        baseline: 0
    )

    @Test func peekSizesTheRestingCreatureAndStandsItsLowestRowOnTheBottomEdge() {
        let box = CGSize(width: NotchGeometry.peekHeight, height: NotchGeometry.peekHeight)
        let placement = SpriteRendering.placement(Self.measured, fit: .peek, in: box, backingScale: 2, pixelated: true)
        #expect(placement.pointsPerPixel == 1.5)
        #expect(placement.groundHeight == 1.5)
    }

    @Test func containRaisesTheGroundOverTheDeepestDipAndLeavesTheHopOut() {
        let box = PanelMetrics.expandedSpriteSize
        let placement = SpriteRendering.placement(Self.measured, fit: .contain, in: box, backingScale: 2, pixelated: true)
        // Idle's head 29 rows up and wake's tail 11 rows down: 40 rows in 100 pt.
        #expect(placement.pointsPerPixel == 2.5)
        #expect(placement.groundHeight == 27.5)
    }

    @Test(arguments: [
        AnimBounds(footprint: Footprint(left: -20, right: 20, top: -33, bottom: 0), lift: 0),
        AnimBounds(footprint: Footprint(left: -14, right: 16, top: -37, bottom: 7), lift: 6),
        AnimBounds(footprint: Footprint(left: -40, right: 10, top: -20, bottom: 0), lift: 2),
        AnimBounds(footprint: Footprint(left: -3, right: 3, top: -5, bottom: 1), lift: 10),
    ])
    func containKeepsEachAnimAndItsMotionInsideTheSlot(anim: AnimBounds) {
        let bounds = SpriteBounds(rest: anim.footprint, anims: [.idle: anim], baseline: 0)
        let box = PanelMetrics.expandedSpriteSize
        for pixelated in [true, false] {
            let placement = SpriteRendering.placement(bounds, fit: .contain, in: box, backingScale: 2, pixelated: pixelated)
            let points = placement.pointsPerPixel
            // y up from the slot's bottom edge; footprint rows count downwards.
            let lowest = placement.groundHeight - CGFloat(anim.footprint.bottom) * points
            let highest = placement.groundHeight - CGFloat(anim.footprint.top) * points
            let rounding = 1e-9
            #expect(abs(lowest) < rounding)
            #expect(highest + anim.lift <= box.height + rounding)
            #expect(CGFloat(anim.footprint.halfWidth) * points + SpriteRendering.maxSway <= box.width / 2 + rounding)
        }
    }

    @Test func containPicksTheScaleFromWhicheverDimensionBinds() {
        let tall = AnimBounds(footprint: Footprint(left: -5, right: 5, top: -45, bottom: 5), lift: 0)
        let wide = AnimBounds(footprint: Footprint(left: -30, right: 2, top: -5, bottom: 5), lift: 0)
        let box = CGSize(width: 136, height: 100)
        #expect(SpriteRendering.pointsPerPixel(containing: [tall], above: 5, in: box, backingScale: 2, pixelated: true) == 2)
        #expect(SpriteRendering.pointsPerPixel(containing: [wide], above: 5, in: box, backingScale: 2, pixelated: true) == 2)
        #expect(SpriteRendering.pointsPerPixel(containing: [tall, wide], above: 5, in: CGSize(width: 100, height: 100), backingScale: 2, pixelated: true) == 1)
    }

    @Test func containNeverDropsPixelArtBelowOneScreenPixel() {
        let huge = AnimBounds(footprint: Footprint(left: -300, right: 300, top: -300, bottom: 300), lift: 0)
        #expect(SpriteRendering.pointsPerPixel(containing: [huge], above: 300, in: CGSize(width: 100, height: 100), backingScale: 2, pixelated: true) == 0.5)
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

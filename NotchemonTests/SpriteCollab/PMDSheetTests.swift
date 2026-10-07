import Foundation
import Testing
@testable import Notchemon

struct PMDSheetTests {
    @Test(arguments: Facing.allCases)
    func eightRowSheetReturnsTheFacingRow(facing: Facing) throws {
        let image = SpriteFixtures.sheet(frameWidth: 10, frameHeight: 14, columns: 3, rows: 8)
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 10, frameHeight: 14, durations: [6, 6, 6])

        let frames = try PMDSheet(image: image, spec: spec).frames(facing: facing)

        #expect(frames.map(SpriteFixtures.cell) == (0..<3).map { Cell(column: $0, row: facing.rawValue) })
        #expect(frames.allSatisfy { $0.width == 10 && $0.height == 14 })
    }

    @Test func singleRowSheetServesEveryFacing() throws {
        let image = SpriteFixtures.sheet(frameWidth: 32, frameHeight: 40, columns: 2, rows: 1)
        let spec = PMDAnimSpec(sheetName: "Sleep", frameWidth: 32, frameHeight: 40, durations: [30, 35])
        let sheet = try PMDSheet(image: image, spec: spec)

        for facing in Facing.allCases {
            #expect(sheet.frames(facing: facing).map(SpriteFixtures.cell) == [Cell(column: 0, row: 0), Cell(column: 1, row: 0)])
        }
    }

    @Test func convertsTicksToSeconds() throws {
        let image = SpriteFixtures.sheet(frameWidth: 4, frameHeight: 4, columns: 3, rows: 1)
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 4, frameHeight: 4, durations: [6, 30, 60])

        #expect(try PMDSheet(image: image, spec: spec).durations == [0.1, 0.5, 1.0])
    }

    @Test func rejectsWidthThatDoesNotMatchTheDurations() {
        let image = SpriteFixtures.sheet(frameWidth: 10, frameHeight: 10, columns: 3, rows: 1)
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 10, frameHeight: 10, durations: [1, 1])

        #expect(throws: PMDSheetError.widthMismatch(sheetWidth: 30, expected: 20)) {
            try PMDSheet(image: image, spec: spec)
        }
    }

    @Test func rejectsHeightNotDivisibleByFrameHeight() {
        let image = SpriteFixtures.sheet(frameWidth: 10, frameHeight: 15, columns: 2, rows: 1)
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 10, frameHeight: 10, durations: [1, 1])

        #expect(throws: PMDSheetError.heightNotDivisible(sheetHeight: 15, frameHeight: 10)) {
            try PMDSheet(image: image, spec: spec)
        }
    }

    @Test func rejectsRowCountsOtherThanOneOrEight() {
        let image = SpriteFixtures.sheet(frameWidth: 10, frameHeight: 10, columns: 2, rows: 3)
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 10, frameHeight: 10, durations: [1, 1])

        #expect(throws: PMDSheetError.unsupportedRowCount(3)) {
            try PMDSheet(image: image, spec: spec)
        }
    }
}

struct PMDShadowSheetTests {
    private static let shadow = CGRect(x: 4, y: 10, width: 8, height: 4)

    @Test(arguments: Facing.allCases)
    func eightRowSheetReadsEachFramesWhitePixelForTheFacing(facing: Facing) throws {
        // The white pixel moves with the cell, so each frame's point is distinct.
        let image = SpriteFixtures.shadowSheet(frameWidth: 16, frameHeight: 20, columns: 3, rows: 8, shadow: Self.shadow) { cell in
            CGPoint(x: 5 + cell.column, y: 10 + cell.row % 4)
        }
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 16, frameHeight: 20, durations: [6, 6, 6])

        let points = try PMDShadowSheet(image: image, spec: spec).groundPoints(facing: facing)

        #expect(points == (0..<3).map { CGPoint(x: 5 + $0, y: 10 + facing.rawValue % 4) })
    }

    @Test func singleRowSheetServesEveryFacing() throws {
        let image = SpriteFixtures.shadowSheet(frameWidth: 16, frameHeight: 20, columns: 2, rows: 1, shadow: Self.shadow) { cell in
            CGPoint(x: 7 + cell.column, y: 12)
        }
        let spec = PMDAnimSpec(sheetName: "Sleep", frameWidth: 16, frameHeight: 20, durations: [30, 30])
        let sheet = try PMDShadowSheet(image: image, spec: spec)

        for facing in Facing.allCases {
            #expect(sheet.groundPoints(facing: facing) == [CGPoint(x: 7, y: 12), CGPoint(x: 8, y: 12)])
        }
    }

    @Test func withoutAWhitePixelTheShadowsCentreStandsIn() throws {
        // Columns 4...11 and rows 10...13: the mean pixel is (7.5, 11.5), kept whole.
        let image = SpriteFixtures.shadowSheet(frameWidth: 16, frameHeight: 20, columns: 1, rows: 1, shadow: Self.shadow) { _ in nil }
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 16, frameHeight: 20, durations: [1])

        #expect(try PMDShadowSheet(image: image, spec: spec).groundPoints(facing: .down) == [CGPoint(x: 7, y: 11)])
    }

    @Test func anEmptyCellFallsBackToTheFrameCentre() throws {
        let image = SpriteFixtures.shadowSheet(frameWidth: 16, frameHeight: 20, columns: 2, rows: 1, shadow: .zero) { _ in nil }
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 16, frameHeight: 20, durations: [1, 1])

        #expect(try PMDShadowSheet(image: image, spec: spec).groundPoints(facing: .left) == [CGPoint(x: 8, y: 10), CGPoint(x: 8, y: 10)])
    }

    @Test func rejectsAGridThatDoesNotMatchTheAnim() {
        let image = SpriteFixtures.shadowSheet(frameWidth: 16, frameHeight: 20, columns: 3, rows: 1, shadow: Self.shadow) { _ in nil }
        let spec = PMDAnimSpec(sheetName: "Idle", frameWidth: 16, frameHeight: 20, durations: [1, 1])

        #expect(throws: PMDSheetError.widthMismatch(sheetWidth: 48, expected: 32)) {
            try PMDShadowSheet(image: image, spec: spec)
        }
    }
}

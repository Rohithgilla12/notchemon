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

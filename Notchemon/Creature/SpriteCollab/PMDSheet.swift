import CoreGraphics
import Foundation

enum PMDSheetError: Error, Equatable {
    case widthMismatch(sheetWidth: Int, expected: Int)
    case heightNotDivisible(sheetHeight: Int, frameHeight: Int)
    case unsupportedRowCount(Int)
    case cropFailed
}

/// One anim sheet sliced into frames. Columns are frames; rows are facings,
/// either all eight or a single row shared by every facing.
struct PMDSheet: Sendable {
    let durations: [TimeInterval]
    private let rows: [[CGImage]]

    init(image: CGImage, spec: PMDAnimSpec) throws {
        let columns = spec.durations.count
        let expectedWidth = spec.frameWidth * columns
        guard image.width == expectedWidth else {
            throw PMDSheetError.widthMismatch(sheetWidth: image.width, expected: expectedWidth)
        }
        guard image.height % spec.frameHeight == 0 else {
            throw PMDSheetError.heightNotDivisible(sheetHeight: image.height, frameHeight: spec.frameHeight)
        }
        let rowCount = image.height / spec.frameHeight
        guard rowCount == 1 || rowCount == PMDFacing.allCases.count else {
            throw PMDSheetError.unsupportedRowCount(rowCount)
        }

        rows = try (0..<rowCount).map { row in
            try (0..<columns).map { column in
                let rect = CGRect(
                    x: column * spec.frameWidth,
                    y: row * spec.frameHeight,
                    width: spec.frameWidth,
                    height: spec.frameHeight
                )
                guard let frame = image.cropping(to: rect) else { throw PMDSheetError.cropFailed }
                return frame
            }
        }
        durations = spec.durations.map { TimeInterval($0) / 60 }
    }

    func frames(facing: PMDFacing) -> [CGImage] {
        rows.count == 1 ? rows[0] : rows[facing.rawValue]
    }
}

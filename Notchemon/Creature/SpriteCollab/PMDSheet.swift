import CoreGraphics
import Foundation

enum PMDSheetError: Error, Equatable {
    case widthMismatch(sheetWidth: Int, expected: Int)
    case heightNotDivisible(sheetHeight: Int, frameHeight: Int)
    case unsupportedRowCount(Int)
    case cropFailed
    /// The sheet's pixels could not be read back.
    case undrawable
}

/// One anim sheet sliced into frames. Columns are frames; rows are facings,
/// either all eight or a single row shared by every facing.
struct PMDSheet: Sendable {
    let durations: [TimeInterval]
    private let rows: [[CGImage]]

    init(image: CGImage, spec: PMDAnimSpec) throws {
        rows = try Self.cells(of: image, spec: spec).map { row in
            try row.map { rect in
                guard let frame = image.cropping(to: rect) else { throw PMDSheetError.cropFailed }
                return frame
            }
        }
        durations = spec.durations.map { TimeInterval($0) / 60 }
    }

    func frames(facing: Facing) -> [CGImage] {
        rows.count == 1 ? rows[0] : rows[facing.rawValue]
    }

    /// The frame rects of a sheet laid out by `spec`, by row then column.
    static func cells(of image: CGImage, spec: PMDAnimSpec) throws -> [[CGRect]] {
        let columns = spec.durations.count
        let expectedWidth = spec.frameWidth * columns
        guard image.width == expectedWidth else {
            throw PMDSheetError.widthMismatch(sheetWidth: image.width, expected: expectedWidth)
        }
        guard image.height % spec.frameHeight == 0 else {
            throw PMDSheetError.heightNotDivisible(sheetHeight: image.height, frameHeight: spec.frameHeight)
        }
        let rowCount = image.height / spec.frameHeight
        guard rowCount == 1 || rowCount == Facing.allCases.count else {
            throw PMDSheetError.unsupportedRowCount(rowCount)
        }
        return (0..<rowCount).map { row in
            (0..<columns).map { column in
                CGRect(x: column * spec.frameWidth, y: row * spec.frameHeight, width: spec.frameWidth, height: spec.frameHeight)
            }
        }
    }
}

/// An anim's `{Name}-Shadow.png`, laid out on the same grid as its anim
/// sheet. Each cell holds a shadow whose white centre pixel is the frame's
/// ground point: the spot the game puts on the creature's position.
struct PMDShadowSheet: Sendable {
    private let rows: [[CGPoint]]

    init(image: CGImage, spec: PMDAnimSpec, context: RGBAPixels.MakeContext = RGBAPixels.sRGBContext) throws {
        let cells = try PMDSheet.cells(of: image, spec: spec)
        let pixels = try RGBAPixels(image, context: context)
        rows = cells.map { row in row.map { pixels.groundPoint(in: $0) } }
    }

    /// Pixel coordinates within each frame, from its top-left corner, y down.
    func groundPoints(facing: Facing) -> [CGPoint] {
        rows.count == 1 ? rows[0] : rows[facing.rawValue]
    }
}

struct RGBAPixels {
    /// A context drawing 8-bit premultiplied RGBA into `data`, `width` pixels a row.
    typealias MakeContext = (_ data: UnsafeMutableRawPointer?, _ width: Int, _ height: Int) -> CGContext?

    let width: Int
    let bytes: [UInt8]

    /// Throws rather than leave the bytes blank, which would read as a
    /// sheet of empty cells.
    init(_ image: CGImage, context makeContext: MakeContext) throws {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = makeContext(buffer.baseAddress, image.width, image.height) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw PMDSheetError.undrawable }
        self.bytes = bytes
    }

    static func sRGBContext(data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(
            data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// The white pixel if the cell has one, else the centre of whatever
    /// shadow it holds, else the cell's centre. Whole pixels, so frames
    /// registered on it stay on the screen's pixel grid.
    func groundPoint(in cell: CGRect) -> CGPoint {
        var white: (x: Int, y: Int)?
        var opaque = (x: 0, y: 0, count: 0)
        // Memory row 0 is the image's top row, the same as the sheet's.
        for y in Int(cell.minY)..<Int(cell.maxY) {
            for x in Int(cell.minX)..<Int(cell.maxX) {
                let offset = (y * width + x) * 4
                guard bytes[offset + 3] > 0 else { continue }
                if white == nil, bytes[offset + 3] == 255, bytes[offset] == 255, bytes[offset + 1] == 255, bytes[offset + 2] == 255 {
                    white = (x, y)
                }
                opaque = (opaque.x + x, opaque.y + y, opaque.count + 1)
            }
        }
        let point: CGPoint
        if let white {
            point = CGPoint(x: white.x, y: white.y)
        } else if opaque.count > 0 {
            point = CGPoint(x: opaque.x / opaque.count, y: opaque.y / opaque.count)
        } else {
            point = CGPoint(x: Int(cell.midX), y: Int(cell.midY))
        }
        return CGPoint(x: point.x - cell.minX, y: point.y - cell.minY)
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Cell: Equatable, CustomStringConvertible {
    let column: Int
    let row: Int

    var description: String { "(\(column), \(row))" }
}

/// Synthetic sheets whose every cell is a flat colour encoding its grid position,
/// so a sliced frame can be traced back to the cell it came from.
enum SpriteFixtures {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let step = 20

    static func sheet(frameWidth: Int, frameHeight: Int, columns: Int, rows: Int) -> CGImage {
        let width = frameWidth * columns
        let height = frameHeight * rows
        let context = bitmap(width: width, height: height)
        for row in 0..<rows {
            for column in 0..<columns {
                context.setFillColor(
                    red: CGFloat(column * step) / 255,
                    green: CGFloat(row * step) / 255,
                    blue: 1,
                    alpha: 1
                )
                // CGContext's origin is bottom-left; sheet rows count from the top.
                context.fill(CGRect(
                    x: column * frameWidth,
                    y: height - (row + 1) * frameHeight,
                    width: frameWidth,
                    height: frameHeight
                ))
            }
        }
        return context.makeImage()!
    }

    static func cell(of frame: CGImage) -> Cell {
        let context = bitmap(width: 1, height: 1)
        context.interpolationQuality = .none
        context.draw(
            frame,
            in: CGRect(x: -frame.width / 2, y: -frame.height / 2, width: frame.width, height: frame.height)
        )
        let pixel = context.data!.assumingMemoryBound(to: UInt8.self)
        return Cell(column: (Int(pixel[0]) + step / 2) / step, row: (Int(pixel[1]) + step / 2) / step)
    }

    static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func animData(_ anims: String) -> Data {
        Data("""
        <?xml version="1.0" ?>
        <AnimData>
            <ShadowSize>1</ShadowSize>
            <Anims>
        \(anims)
            </Anims>
        </AnimData>
        """.utf8)
    }

    static func anim(_ name: String, width: Int, height: Int, durations: [Int]) -> String {
        """
        <Anim>
            <Name>\(name)</Name>
            <Index>0</Index>
            <FrameWidth>\(width)</FrameWidth>
            <FrameHeight>\(height)</FrameHeight>
            <Durations>\(durations.map { "<Duration>\($0)</Duration>" }.joined())</Durations>
        </Anim>
        """
    }

    static func alias(_ name: String, of target: String) -> String {
        "<Anim><Name>\(name)</Name><Index>1</Index><CopyOf>\(target)</CopyOf></Anim>"
    }

    private static func bitmap(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }
}

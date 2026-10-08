import CoreGraphics
import Foundation

struct NotesDisplay: Equatable, Sendable {
    let id: String
    let visibleFrame: CGRect
}

/// Where the floating notes window opens. Frames are remembered per display
/// and pulled back onto the display's visible area, so a frame saved on a
/// larger or since-rearranged screen never opens off-screen.
enum NotesWindowFrame {
    static let minimumSize = CGSize(width: 280, height: 200)
    static let defaultSize = CGSize(width: 420, height: 460)
    static let margin: CGFloat = 24

    static func resolve(saved: [String: CGRect], on display: NotesDisplay) -> CGRect {
        guard let frame = saved[display.id] else { return defaultFrame(in: display.visibleFrame) }
        return clamp(frame, into: display.visibleFrame)
    }

    /// Top right of the visible area, clear of the menu bar and the edge.
    static func defaultFrame(in visible: CGRect) -> CGRect {
        let size = CGSize(
            width: min(defaultSize.width, visible.width - 2 * margin),
            height: min(defaultSize.height, visible.height - 2 * margin)
        )
        let origin = CGPoint(x: visible.maxX - margin - size.width, y: visible.maxY - margin - size.height)
        return clamp(CGRect(origin: origin, size: size), into: visible)
    }

    /// Shrinks `frame` to fit `visible`, not below the minimum size unless the
    /// display itself is smaller, then slides it fully inside.
    static func clamp(_ frame: CGRect, into visible: CGRect) -> CGRect {
        let width = min(max(frame.width, minimumSize.width), visible.width)
        let height = min(max(frame.height, minimumSize.height), visible.height)
        let x = min(max(frame.minX, visible.minX), visible.maxX - width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The display a saved frame belongs to: the one holding most of it.
    static func display(for frame: CGRect, among displays: [NotesDisplay]) -> NotesDisplay? {
        let overlaps: [(NotesDisplay, CGFloat)] = displays.map { display in
            let overlap = display.visibleFrame.intersection(frame)
            return (display, overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        guard let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    static func encode(_ frames: [String: CGRect]) -> [String: String] {
        frames.mapValues { NSStringFromRect($0) }
    }

    static func decode(_ stored: [String: String]) -> [String: CGRect] {
        stored.compactMapValues { string in
            let rect = NSRectFromString(string)
            return rect.width > 0 && rect.height > 0 ? rect : nil
        }
    }
}

enum NotesCommand: Equatable, Sendable {
    case newNote
    case quickSwitcher
    case previous
    case next
    case delete
    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
}

/// The window's own shortcuts. The edit commands are routed here too because
/// a menu-bar-only app may have no Edit menu to supply them.
enum NotesShortcut {
    static let deleteKeyCode: UInt16 = 51

    static func command(characters: String, keyCode: UInt16, command: Bool, shift: Bool, option: Bool, control: Bool) -> NotesCommand? {
        guard command, !option, !control else { return nil }
        if keyCode == deleteKeyCode { return shift ? nil : .delete }
        switch (characters.lowercased(), shift) {
        case ("n", false): return .newNote
        case ("p", false), ("k", false): return .quickSwitcher
        case ("[", false): return .previous
        case ("]", false): return .next
        case ("z", false): return .undo
        case ("z", true): return .redo
        case ("x", false): return .cut
        case ("c", false): return .copy
        case ("v", false): return .paste
        case ("a", false): return .selectAll
        default: return nil
        }
    }
}

import AppKit
import QuartzCore

/// Lays out markup marked `.notesHidden` at zero width, so the note stays
/// plain Markdown while it reads as formatted text, and draws the bullets,
/// checkboxes, quote bars, and rules that stand in for hidden line prefixes.
final class NotesLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    struct CheckAnimation {
        /// The `[` of the box being ticked.
        let box: Int
        let start: CFTimeInterval
    }

    static let checkDuration: CFTimeInterval = 0.12
    private static let bulletSize: CGFloat = 5
    private static let boxSize: CGFloat = 14
    /// From the text's left edge back to the decoration's centre.
    private static let decorationInset: CGFloat = 15

    var checkAnimation: CheckAnimation?
    private lazy var tick: NSImage? = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold).applying(.init(paletteColors: [.white])))

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        let count = glyphRange.length
        let first = characterIndexes[0]
        let span = NSRange(location: first, length: characterIndexes[count - 1] - first + 1)
        var anyHidden = false
        storage.enumerateAttribute(.notesHidden, in: span) { value, _, stop in
            if value != nil {
                anyHidden = true
                stop.pointee = true
            }
        }
        // Zero lets the layout manager generate the glyphs as usual.
        guard anyHidden else { return 0 }
        var adjusted = Array(UnsafeBufferPointer(start: properties, count: count))
        var run = NSRange(location: NSNotFound, length: 0)
        var runHidden = false
        for index in 0..<count {
            let character = characterIndexes[index]
            if !NSLocationInRange(character, run) {
                runHidden = storage.attribute(.notesHidden, at: character, effectiveRange: &run) != nil
            }
            if runHidden { adjusted[index] = .controlCharacter }
        }
        adjusted.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        }
        return count
    }

    // Hidden markup is laid out in place at zero width. Null glyphs would be
    // simpler, but at a line's start TextKit moves them onto the line before,
    // which then grows taller.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt characterIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        layoutManager.textStorage?.attribute(.notesHidden, at: characterIndex, effectiveRange: nil) == nil ? action : .zeroAdvancement
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.notesDecoration, in: characters) { value, marker, _ in
            guard let raw = value as? Int, let block = MarkdownSpan.Block(rawValue: raw),
                  let frame = decorationFrame(block, marker: marker) else { return }
            draw(block, marker: marker, in: frame.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    /// Where the decoration for the hidden prefix `marker` sits, in text
    /// container coordinates: hung off the first visible glyph after the
    /// prefix, which may be the newline.
    func decorationFrame(_ block: MarkdownSpan.Block, marker: NSRange) -> NSRect? {
        guard let storage = textStorage, let anchor = firstShown(after: marker, in: storage) else { return nil }
        let glyph = glyphIndexForCharacter(at: anchor)
        guard glyph < numberOfGlyphs else { return nil }
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = location(forGlyphAt: glyph)
        let textX = line.minX + position.x
        let baseline = line.minY + position.y
        let font = storage.attribute(.font, at: marker.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
        let centreX = textX - Self.decorationInset
        switch block {
        case .bullet:
            let size = Self.bulletSize
            return NSRect(x: centreX - size / 2, y: baseline - font.xHeight / 2 - size / 2, width: size, height: size)
        case .task, .doneTask:
            let size = Self.boxSize
            return NSRect(x: centreX - size / 2, y: baseline - font.capHeight / 2 - size / 2, width: size, height: size)
        case .quote:
            let paragraph = storage.mutableString.paragraphRange(for: marker)
            let lastGlyph = glyphIndexForCharacter(at: NSMaxRange(paragraph) - 1)
            let lastLine = lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let top = baseline - font.ascender
            let bottom = lastLine.minY + location(forGlyphAt: lastGlyph).y - font.descender
            return NSRect(x: textX - MarkdownTheme.gutter(.quote), y: top, width: 3, height: bottom - top)
        case .rule:
            return NSRect(x: line.minX, y: line.midY - 3, width: line.width, height: 1)
        }
    }

    /// The first character after `marker` on its line that is not hidden.
    private func firstShown(after marker: NSRange, in storage: NSTextStorage) -> Int? {
        var index = NSMaxRange(marker)
        while index < storage.length {
            var run = NSRange()
            guard storage.attribute(.notesHidden, at: index, effectiveRange: &run) != nil else { return index }
            index = NSMaxRange(run)
        }
        return nil
    }

    private func draw(_ block: MarkdownSpan.Block, marker: NSRange, in frame: NSRect) {
        let accent = NotesPalette.accent
        switch block {
        case .bullet:
            accent.setFill()
            NSBezierPath(ovalIn: frame).fill()
        case .task:
            strokeBox(frame, color: accent)
        case .doneTask:
            let progress = checkProgress(for: marker)
            if progress < 1 { strokeBox(frame, color: accent) }
            accent.withAlphaComponent(progress).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
            guard let tick else { return }
            let scale = 0.9 + 0.1 * progress
            let size = NSSize(width: tick.size.width * scale, height: tick.size.height * scale)
            let rect = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
            tick.draw(in: rect, from: .zero, operation: .sourceOver, fraction: progress, respectFlipped: true, hints: nil)
        case .quote:
            accent.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 1.5, yRadius: 1.5).fill()
        case .rule:
            NSColor.white.withAlphaComponent(0.15).setFill()
            frame.fill()
        }
    }

    private func strokeBox(_ frame: NSRect, color: NSColor) {
        let box = NSBezierPath(roundedRect: frame.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
        box.lineWidth = 1.5
        color.setStroke()
        box.stroke()
    }

    /// Eased from 0 to 1 while the box under `marker` is being ticked; 1 otherwise.
    private func checkProgress(for marker: NSRange) -> CGFloat {
        guard let checkAnimation, NSLocationInRange(checkAnimation.box, marker) else { return 1 }
        let linear = min(max((CACurrentMediaTime() - checkAnimation.start) / Self.checkDuration, 0), 1)
        return 1 - pow(1 - linear, 3)
    }
}

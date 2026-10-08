import AppKit

/// Lays out markup marked `.notesHidden` at zero width, so the note stays
/// plain Markdown while it reads as formatted text.
final class NotesLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
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
            if runHidden { adjusted[index] = .null }
        }
        adjusted.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        }
        return count
    }
}

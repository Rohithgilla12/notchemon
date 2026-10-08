import AppKit
import SwiftUI
import Testing
@testable import Notchemon

/// Renders the window offscreen and times restyling, when
/// `NOTCHEMON_NOTES_RENDER_DIR` names a folder for the output. Pass it to
/// xcodebuild as `TEST_RUNNER_NOTCHEMON_NOTES_RENDER_DIR=<dir>`.
let notesRenderFolder = ProcessInfo.processInfo.environment["NOTCHEMON_NOTES_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }

@MainActor
@Suite(.enabled(if: notesRenderFolder != nil))
struct NotesRenderTests {

    static let styledNote = """
    # Launch checklist
    Ship the **floating notes** before *Friday*.

    ## Tasks
    - [x] Store notes as Markdown files
    - [x] Live styling for `**bold**` and `code`
    - [ ] Write the [README section](https://github.com/Rohithgilla12/notchemon)
    - [ ] Record a demo

    ### Notes
    1. Run `xcodegen generate -q` first
    2. Then the tests
    - Plain bullet with _emphasis_
    """

    @Test func rendersAStyledNoteAndTheQuickSwitcher() throws {
        let folder = try #require(notesRenderFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sandbox = try NotesSandbox()
        let store = sandbox.store
        _ = try store.create("Standup\nasked about the release date", at: october8)
        _ = try store.create("Groceries\n- [ ] milk\n- [x] eggs\n- [ ] coffee beans", at: october8)
        _ = try store.create("Reading list\n- Designing Data-Intensive Applications", at: october8)
        let launch = try store.create(Self.styledNote, at: october8)
        let defaults = try #require(UserDefaults(suiteName: "NotchemonNotesRender-\(UUID().uuidString)"))
        let notes = FloatingNotes(store: store, defaults: defaults)
        notes.session.load(selecting: launch.url.lastPathComponent)

        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"
            try render(notes.preparePanel(), appearance: appearance, to: folder.appendingPathComponent("styled-note-\(suffix).png"))
        }

        for hovering in [false, true] {
            let frame = CGRect(x: 0, y: 0, width: 420, height: NotesHeader.height)
            let header = NSHostingView(rootView: NotesHeader(notes: notes, hovering: hovering))
            header.frame = frame
            let strip = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
            strip.contentView = NSView(frame: frame)
            strip.contentView?.addSubview(header)
            try render(strip, appearance: .darkAqua, to: folder.appendingPathComponent(hovering ? "header-hover.png" : "header-idle.png"))
        }

        let switcher = NSHostingView(rootView: QuickSwitcher(session: notes.session, query: "milk", onClose: { _ in }).frame(width: 400).padding(10))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = switcher
        try render(window, appearance: .darkAqua, to: folder.appendingPathComponent("quick-switcher-search.png"), material: false)

        notes.openSwitcher()
        try render(notes.preparePanel(), appearance: .darkAqua, to: folder.appendingPathComponent("quick-switcher-in-window.png"))
    }

    @Test func timesRestylingPerKeystrokeOnAFiveThousandLineNote() throws {
        let folder = try #require(notesRenderFolder)
        let lines: [String] = (0..<5_000).map { index in
            switch index % 10 {
            case 0: "## Section \(index / 10)"
            case 1: "- [ ] task \(index) with `code` and a [link](https://example.com)"
            case 2: "- [x] done \(index) **bold** and *italic*"
            case 3: "1. numbered item \(index)"
            default: "Plain prose line \(index) with a little **emphasis** and some words to make it realistic."
            }
        }
        let text = lines.joined(separator: "\n")
        let length = (text as NSString).length
        let locations: [Int] = (0..<400).map { (length / 400) * $0 + 7 }
        let clock = ContinuousClock()

        let styled = EditorHarness("")
        let initial = clock.measure { styled.textView.string = text }
        let fullRestyle = clock.measure { styled.textView.restyleAll() }
        let plain = EditorHarness("")
        plain.storage.delegate = nil
        plain.textView.string = text

        let styledFirst = Self.type(into: styled, at: locations, clock: clock)
        let styledAgain = Self.type(into: styled, at: locations, clock: clock)
        let plainFirst = Self.type(into: plain, at: locations, clock: clock)
        let plainAgain = Self.type(into: plain, at: locations, clock: clock)

        let restyles: [Duration] = locations.map { location in
            clock.measure {
                styled.storage.beginEditing()
                styled.highlighter.theme.restyle(styled.storage, range: NSRange(location: location, length: 1), active: styled.textView.activeLines)
                styled.storage.endEditing()
            }
        }
        let parses: [Duration] = locations.map { location in
            clock.measure { _ = MarkdownStyler.spans(in: styled.storage.mutableString, range: NSRange(location: location, length: 1)) }
        }
        let copies: [Duration] = locations.map { _ in clock.measure { _ = styled.textView.string } }

        let report = """
        5,000 lines, \(length) UTF-16 units, one keystroke at each of 400 places spread through the note
        initial load (set text, styles all lines): \(Self.ms(initial))
        full restyle of every line: \(Self.ms(fullRestyle))
        keystroke, highlighter attached, first visit: \(Self.summary(styledFirst.keystrokes))
        keystroke, highlighter attached, second visit: \(Self.summary(styledAgain.keystrokes))
        keystroke, highlighter detached, first visit: \(Self.summary(plainFirst.keystrokes))
        keystroke, highlighter detached, second visit: \(Self.summary(plainAgain.keystrokes))
        caret move to a new line and its layout, attached, second visit: \(Self.summary(styledAgain.moves))
        caret move to a new line and its layout, detached, second visit: \(Self.summary(plainAgain.moves))
        paragraph restyle alone, one editing pass: \(Self.summary(restyles))
        styler parse of that paragraph alone: \(Self.summary(parses))
        textView.string copy handed to the session: \(Self.summary(copies))
        """
        print(report)
        try report.write(to: folder.appendingPathComponent("restyle-timing.txt"), atomically: true, encoding: .utf8)
        #expect(styled.storage.length == length + 800)
        #expect(styled.storage.isEqual(to: styled.styledFromScratch))
    }

    /// Moves the caret to each place and settles layout as the display pass
    /// between keystrokes would, then types one character. Moving the caret
    /// restyles the old and new lines, so moves and keystrokes are timed apart.
    private static func type(into editor: EditorHarness, at locations: [Int], clock: ContinuousClock) -> (moves: [Duration], keystrokes: [Duration]) {
        var moves: [Duration] = []
        var keystrokes: [Duration] = []
        for location in locations {
            moves.append(clock.measure {
                editor.textView.setSelectedRange(NSRange(location: location, length: 0))
                editor.textView.layoutManager?.ensureLayout(for: editor.textView.textContainer!)
            })
            keystrokes.append(clock.measure { editor.textView.insertText("a", replacementRange: editor.textView.selectedRange()) })
        }
        return (moves, keystrokes)
    }

    /// Captures the window's content over a sample wallpaper. The behind-window
    /// material only renders on screen, so a dark tint in the window's shape
    /// stands in for it, drawn under the content for the capture.
    private func render(_ window: NSWindow, appearance: NSAppearance.Name, to url: URL, material: Bool = true) throws {
        window.appearance = NSAppearance(named: appearance)
        let view = try #require(window.contentView)
        let margin: CGFloat = 24
        let standIn = WallpaperStandIn(frame: view.bounds, margin: margin, material: material)
        standIn.autoresizingMask = [.width, .height]
        view.addSubview(standIn, positioned: .below, relativeTo: view.subviews.first)
        defer { standIn.removeFromSuperview() }
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let composite = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide + Int(margin * scale * 2), pixelsHigh: rep.pixelsHigh + Int(margin * scale * 2), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: composite)
        let canvas = CGRect(x: 0, y: 0, width: composite.pixelsWide, height: composite.pixelsHigh)
        WallpaperStandIn.wallpaper.draw(in: canvas, angle: -60)
        rep.draw(in: CGRect(x: margin * scale, y: margin * scale, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
        NSGraphicsContext.restoreGraphicsState()
        try #require(composite.representation(using: .png, properties: [:])).write(to: url)
    }

    private static func ms(_ duration: Duration) -> String {
        String(format: "%.3f ms", Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000)
    }

    private static func summary(_ samples: [Duration]) -> String {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        return "median \(ms(median)), p95 \(ms(p95)), max \(ms(sorted[sorted.count - 1])) (n=\(sorted.count))"
    }
}

/// Paints the slice of the sample wallpaper behind a captured view, plus a
/// stand-in for the window material, so the capture lines up with the canvas.
private final class WallpaperStandIn: NSView {
    static let wallpaper = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.22, blue: 0.14, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.16, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.55, blue: 0.25, alpha: 1),
    ])!

    let margin: CGFloat
    let material: Bool

    init(frame: CGRect, margin: CGFloat, material: Bool) {
        self.margin = margin
        self.material = material
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        Self.wallpaper.draw(in: bounds.insetBy(dx: -margin, dy: -margin), angle: -60)
        guard material else { return }
        let radius = NotesMaterial.windowCornerRadius
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        NSColor(white: 0.11, alpha: 0.72).setFill()
        shape.fill()
        NotesMaterial.highlight.setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}

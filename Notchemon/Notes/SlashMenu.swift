import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SlashMenuModel {
    var state: SlashMenuState?
    @ObservationIgnored var onChoose: (Int) -> Void = { _ in }
}

/// The `/` menu beside the caret. It appears and goes at once, with no
/// animation: it is typed into often and must keep up with the keys.
@MainActor
final class SlashMenu {
    static let width: CGFloat = 240
    private static let gap: CGFloat = 6

    let model = SlashMenuModel()
    private weak var textView: NotesTextView?
    private var panel: NSPanel?
    private var resignObserver: (any NSObjectProtocol)?

    init(textView: NotesTextView) {
        self.textView = textView
        model.onChoose = { [weak self] index in self?.choose(index) }
    }

    var isOpen: Bool { model.state != nil }
    /// The menu's panel, once it has opened.
    var window: NSWindow? { panel }

    func open(at slash: Int) {
        guard let textView, let storage = textView.textStorage else { return }
        update(SlashMenuState.after(nil, slash: slash, text: storage.mutableString, caret: textView.selectedRange().location))
    }

    /// Follows the text and caret, closing once the query no longer applies.
    func refresh() {
        guard let state = model.state, let textView, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return close() }
        update(SlashMenuState.after(state, slash: state.slash, text: storage.mutableString, caret: selection.location))
    }

    func close() {
        update(nil)
    }

    func handle(_ selector: Selector) -> Bool {
        guard let state = model.state else { return false }
        switch selector {
        case _ where state.results.isEmpty: return false
        case #selector(NSResponder.moveUp(_:)): update(state.moving(by: -1))
        case #selector(NSResponder.moveDown(_:)): update(state.moving(by: 1))
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): choose(state.selected)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func choose(_ index: Int) {
        guard let state = model.state, state.results.indices.contains(index) else { return }
        close()
        textView?.apply(state.results[index], replacing: state.trigger)
    }

    private func update(_ state: SlashMenuState?) {
        model.state = state
        guard let state else { return hide() }
        show(state)
    }

    private func show(_ state: SlashMenuState) {
        guard let textView, let parent = textView.window else { return }
        let panel = self.panel ?? makePanel()
        let caret = textView.firstRect(forCharacterRange: NSRange(location: state.slash, length: 1), actualRange: nil)
        let size = NSSize(width: Self.width, height: SlashMenuView.height(for: state))
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var origin = NSPoint(x: caret.minX - 12, y: caret.minY - Self.gap - size.height)
        if origin.y < screen.minY { origin.y = caret.maxY + Self.gap }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        guard parent.isVisible else { return }
        if panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: parent, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
        panel.orderFront(nil)
    }

    private func hide() {
        guard let panel, panel.parent != nil || panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func makePanel() -> NSPanel {
        let panel = SlashMenuPanel()
        let background = NotesMaterial.makeView(cornerRadius: NotesMaterial.menuCornerRadius)
        let hosting = NSHostingView(rootView: SlashMenuView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        self.panel = panel
        return panel
    }
}

/// Never key: the editor keeps the keyboard while the menu shows.
private final class SlashMenuPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SlashMenuView: View {
    static let padding: CGFloat = 6
    static let rowHeight: CGFloat = 30
    static let headerHeight: CGFloat = 26
    static let maxHeight: CGFloat = 320

    let model: SlashMenuModel

    static func height(for state: SlashMenuState) -> CGFloat {
        guard !state.results.isEmpty else { return padding * 2 + rowHeight }
        let groups = CGFloat(Set(state.results.map(\.group)).count)
        let rows = CGFloat(state.results.count)
        return min(padding * 2 + groups * headerHeight + rows * rowHeight, maxHeight)
    }

    var body: some View {
        let state = model.state
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let state {
                        rows(state)
                    }
                }
                .padding(Self.padding)
            }
            .onChange(of: state?.selected) {
                if let id = model.state?.selectedCommand?.id { proxy.scrollTo(id) }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func rows(_ state: SlashMenuState) -> some View {
        if state.results.isEmpty {
            Text("No matches")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 10)
                .frame(height: Self.rowHeight)
        }
        ForEach(SlashCommand.Group.allCases, id: \.self) { group in
            let members: [Int] = state.results.indices.filter { state.results[$0].group == group }
            if !members.isEmpty {
                Text(group.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 10)
                    .frame(height: Self.headerHeight, alignment: .bottom)
                ForEach(members, id: \.self) { index in
                    SlashMenuRow(command: state.results[index], selected: index == state.selected) {
                        model.onChoose(index)
                    }
                    .id(state.results[index].id)
                }
            }
        }
    }
}

private struct SlashMenuRow: View {
    let command: SlashCommand
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: command.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(command.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: SlashMenuView.rowHeight)
            .background(selected ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: .labelColor))
    }
}

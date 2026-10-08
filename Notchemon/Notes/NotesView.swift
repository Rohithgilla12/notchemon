import AppKit
import SwiftUI

struct NotesView: View {
    let notes: FloatingNotes

    var body: some View {
        let session = notes.session
        VStack(spacing: 0) {
            NotesHeader(notes: notes)
            NoteEditor(session: session, handle: notes.editor, monospaced: notes.monospaced)
            if let error = session.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .top) {
            if notes.switcherOpen {
                QuickSwitcher(session: session) { id in
                    notes.closeSwitcher(opening: id)
                }
                .padding(.horizontal, 10)
                .padding(.top, NotesHeader.height)
            }
        }
        .frame(minWidth: NotesWindowFrame.minimumSize.width, minHeight: NotesWindowFrame.minimumSize.height)
        // The title bar is hidden; the header takes its place.
        .ignoresSafeArea()
    }
}

/// A quiet centred title. The actions fade in only while the pointer is over
/// the strip; their shortcuts work either way.
struct NotesHeader: View {
    static let height: CGFloat = 40
    private static let actionsWidth: CGFloat = 104

    let notes: FloatingNotes
    @State private var hovering: Bool

    init(notes: FloatingNotes, hovering: Bool = false) {
        self.notes = notes
        _hovering = State(initialValue: hovering)
    }

    var body: some View {
        ZStack {
            HeaderStrip { hovering = $0 }
            Text(notes.session.current?.title ?? "Notes")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor).opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Self.actionsWidth)
                .allowsHitTesting(false)
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                actions
            }
            .padding(.trailing, 10)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .frame(height: Self.height)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var actions: some View {
        HeaderButton(symbol: "magnifyingglass", help: "Find a note (⌘P)") { notes.openSwitcher() }
        HeaderButton(symbol: "square.and.pencil", help: "New note (⌘N)") { notes.newNote() }
        HeaderButton(symbol: notes.keepOnTop ? "pin.fill" : "pin", help: notes.keepOnTop ? "Keep on Top is on" : "Keep on Top is off") {
            notes.setKeepOnTop(!notes.keepOnTop)
        }
        Menu {
            Toggle("Keep on Top", isOn: Binding(get: { notes.keepOnTop }, set: { notes.setKeepOnTop($0) }))
            Toggle("Monospaced Font", isOn: Binding(get: { notes.monospaced }, set: { notes.setMonospaced($0) }))
            Divider()
            Button("Show in Finder") { notes.revealFolder() }
            Button("Move to Trash…") { notes.confirmDelete() }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

/// The header's AppKit backing: it drags the window and reports hover from a
/// tracking area, which fires even while another app is active.
private struct HeaderStrip: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HeaderStripView {
        let view = HeaderStripView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: HeaderStripView, context: Context) {
        view.onHover = onHover
    }
}

final class HeaderStripView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

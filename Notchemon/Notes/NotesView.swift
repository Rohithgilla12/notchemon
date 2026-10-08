import SwiftUI

struct NotesView: View {
    let notes: FloatingNotes

    var body: some View {
        let session = notes.session
        VStack(spacing: 0) {
            NotesHeader(notes: notes)
            Divider().opacity(0.5)
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
                .padding(.top, 38)
            }
        }
        .frame(minWidth: NotesWindowFrame.minimumSize.width, minHeight: NotesWindowFrame.minimumSize.height)
        // The title bar is hidden; the header takes its place.
        .ignoresSafeArea()
    }
}

private struct NotesHeader: View {
    let notes: FloatingNotes

    var body: some View {
        let session = notes.session
        let position = session.notes.firstIndex { $0.id == session.selectedID }.map { $0 + 1 } ?? 0
        HStack(spacing: 2) {
            Text(session.current?.title ?? "Notes")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(position)/\(session.notes.count)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .padding(.leading, 6)
            Spacer(minLength: 8)
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
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 34)
        .foregroundStyle(.secondary)
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

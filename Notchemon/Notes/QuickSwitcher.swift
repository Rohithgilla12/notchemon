import SwiftUI

/// ⌘P / ⌘K: type to filter, arrows to move, Return to open, Esc to close.
struct QuickSwitcher: View {
    let session: NotesSession
    let onClose: (UUID?) -> Void
    @State private var query: String
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    init(session: NotesSession, query: String = "", onClose: @escaping (UUID?) -> Void) {
        self.session = session
        self.onClose = onClose
        _query = State(initialValue: query)
    }

    var body: some View {
        let results = NoteSearch.rank(query, in: session.notes)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($fieldFocused)
                    .onSubmit { onClose(results.indices.contains(highlighted) ? results[highlighted].id : nil) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if results.isEmpty {
                Text("No matching notes")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, match in
                                SwitcherRow(match: match, isCurrent: match.id == session.selectedID, isHighlighted: index == highlighted)
                                    .id(match.id)
                                    .onTapGesture { onClose(match.id) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 260)
                    .onChange(of: highlighted) { _, index in
                        if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onExitCommand { onClose(nil) }
        .onChange(of: query) { highlighted = 0 }
        .onAppear { fieldFocused = true }
    }
}

private struct SwitcherRow: View {
    let match: NoteMatch
    let isCurrent: Bool
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(match.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if isCurrent {
                    Text("Open").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            if let snippet = match.snippet {
                Text(snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHighlighted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

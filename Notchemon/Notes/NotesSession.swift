import Foundation
import Observation

enum NoteSavePolicy {
    static let debounce: Duration = .milliseconds(500)
    /// A new note gets its file name from its title at the first save, so its
    /// first save waits until the title line ends or the typing pauses.
    static let untitledDebounce: Duration = .seconds(3)

    static func delay(hasFile: Bool, text: String) -> Duration {
        hasFile || text.contains(where: \.isNewline) ? debounce : untitledDebounce
    }
}

/// The notes in the floating window and which one is open. Every write goes
/// through `NoteSync`, so a save never overwrites a file another editor changed.
@MainActor
@Observable
final class NotesSession {
    struct Document {
        var note: Note
        /// The text last read from or written to the file; "" before the first save.
        var base: String
        var diskModified: Date?
    }

    private(set) var documents: [Document] = []
    private(set) var selectedID: UUID?
    /// Bumps whenever the editor must take its text from the session again.
    private(set) var editorRevision = 0
    private(set) var lastError: String?

    @ObservationIgnored let store: NoteStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(store: NoteStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    var notes: [Note] { documents.map(\.note) }
    var current: Note? { selectedIndex.map { documents[$0].note } }
    var currentFileName: String? { current?.url?.lastPathComponent }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return index(of: selectedID)
    }

    /// Reads the folder and opens the note saved under `selecting`, else the newest.
    func load(selecting fileName: String? = nil) {
        documents = store.loadAll().map(Self.document(from:))
        let match = documents.first { $0.note.url?.lastPathComponent == fileName }
        selectedID = (match ?? documents.first)?.note.id
        if documents.isEmpty { insertBlankNote() }
        editorRevision += 1
    }

    func edit(_ text: String) {
        guard let index = selectedIndex, documents[index].note.body != text else { return }
        documents[index].note.body = text
        documents[index].note.modified = now()
        scheduleSave(of: documents[index])
    }

    func newNote(body: String = "") {
        flush()
        if body.isEmpty, let note = current, note.url == nil, note.body.isEmpty { return }
        dropBlankDraft()
        insertBlankNote(body: body)
        editorRevision += 1
        if !body.isEmpty { flush() }
    }

    func select(_ id: UUID) {
        guard id != selectedID, index(of: id) != nil else { return }
        flush()
        dropBlankDraft()
        selectedID = id
        editorRevision += 1
    }

    /// Moves through the list without wrapping.
    func step(by offset: Int) {
        guard let index = selectedIndex else { return }
        let target = min(max(index + offset, 0), documents.count - 1)
        select(documents[target].note.id)
    }

    /// Moves the note's file to the Trash. If it was open, its neighbour opens.
    func delete(_ id: UUID) {
        guard let index = index(of: id) else { return }
        if id == selectedID { saveTask?.cancel() }
        if let url = documents[index].note.url {
            do {
                try store.trash(url)
            } catch {
                lastError = "Couldn't move the note to the Trash: \(error.localizedDescription)"
                return
            }
        }
        remove(at: index)
    }

    /// Saves every note with unsaved edits now.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        for id in documents.map(\.note.id) {
            guard let index = index(of: id), documents[index].note.body != documents[index].base else { continue }
            sync(id)
        }
    }

    /// Picks up edits from other editors: changed, removed, and new files.
    func rescan() {
        for document in documents {
            guard let url = document.note.url else { continue }
            if store.modificationDate(url) != document.diskModified { sync(document.note.id) }
        }
        let known = Set(documents.compactMap { $0.note.url?.standardizedFileURL })
        let added = store.loadAll().filter { !known.contains($0.url.standardizedFileURL) }
        documents.insert(contentsOf: added.map(Self.document(from:)), at: 0)
    }

    private func scheduleSave(of document: Document) {
        saveTask?.cancel()
        let id = document.note.id
        let delay = NoteSavePolicy.delay(hasFile: document.note.url != nil, text: document.note.body)
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.sync(id)
        }
    }

    private func sync(_ id: UUID) {
        guard let index = index(of: id) else { return }
        let document = documents[index]
        do {
            guard let url = document.note.url else {
                guard !document.note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let file = try store.create(document.note.body, at: now())
                documents[index].note.url = file.url
                markSaved(index, file)
                return
            }
            let modified = store.modificationDate(url)
            switch NoteSync.decide(base: document.base, disk: store.disk(url), local: document.note.body) {
            case .none:
                documents[index].diskModified = modified
            case .write, .restore:
                markSaved(index, try store.write(document.note.body, to: url))
            case .reload(let text):
                documents[index].note.body = text
                documents[index].note.modified = modified ?? now()
                documents[index].base = text
                documents[index].diskModified = modified
                if id == selectedID { editorRevision += 1 }
            case .conflict(let text):
                try keepBoth(index, disk: text, diskModified: modified)
            case .remove:
                remove(at: index)
            }
            lastError = nil
        } catch {
            lastError = "Couldn't save “\(document.note.title)”: \(error.localizedDescription)"
        }
    }

    /// The editor's text goes to a new conflict copy, which stays open if the
    /// original was. The original takes the other editor's text, or, when the
    /// file is unreadable, goes back to its last saved text and is left alone.
    private func keepBoth(_ index: Int, disk text: String?, diskModified: Date?) throws {
        let local = documents[index].note
        let copy = try store.create(local.body, at: now(), suffix: " conflict")
        let original = text ?? documents[index].base
        documents[index].note.body = original
        documents[index].base = original
        documents[index].diskModified = diskModified
        let copied = Self.document(from: copy)
        documents.insert(copied, at: index)
        if local.id == selectedID {
            selectedID = copied.note.id
            editorRevision += 1
        }
    }

    private func markSaved(_ index: Int, _ file: NoteFile) {
        documents[index].base = file.text
        documents[index].diskModified = file.modified
        documents[index].note.modified = file.modified
    }

    private func remove(at index: Int) {
        let removed = documents.remove(at: index)
        guard removed.note.id == selectedID else { return }
        if documents.isEmpty {
            insertBlankNote()
        } else {
            selectedID = documents[min(index, documents.count - 1)].note.id
        }
        editorRevision += 1
    }

    private func insertBlankNote(body: String = "") {
        let note = Note(body: body, modified: now())
        documents.insert(Document(note: note, base: "", diskModified: nil), at: 0)
        selectedID = note.id
    }

    /// A new note left empty never got a file; leaving it discards it.
    private func dropBlankDraft() {
        guard let index = selectedIndex, documents[index].note.url == nil, documents[index].note.body.isEmpty else { return }
        documents.remove(at: index)
    }

    private func index(of id: UUID) -> Int? {
        documents.firstIndex { $0.note.id == id }
    }

    private static func document(from file: NoteFile) -> Document {
        Document(note: Note(url: file.url, body: file.text, modified: file.modified), base: file.text, diskModified: file.modified)
    }
}

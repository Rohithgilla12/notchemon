import Foundation
import Observation
import os

enum NoteSavePolicy {
    static let debounce: Duration = .milliseconds(500)
    /// A new note gets its file name from its title at the first save, so its
    /// first save waits until the title line ends or the typing pauses.
    static let untitledDebounce: Duration = .seconds(3)

    /// The longest a flush waits on the disk, so a hung volume cannot hold quitting.
    static let flushLimit: TimeInterval = 5

    static func delay(hasFile: Bool, text: String) -> Duration {
        hasFile || text.contains(where: \.isNewline) ? debounce : untitledDebounce
    }
}

/// The notes in the floating window and which one is open. Every write goes
/// through `NoteSync`, so a save never overwrites a file another editor changed.
@MainActor
@Observable
final class NotesSession {
    struct Document: Sendable {
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
    @ObservationIgnored private let job = OSAllocatedUnfairLock(initialState: SaveJob())

    /// Saves run one job at a time. A job that outlives its wait keeps
    /// `running` until its late results are applied, so no later save can
    /// overtake it on disk or start from a base it is about to change.
    private struct SaveJob: Sendable {
        var running = false
        var abandoned = false
        var results: [UUID: Result<NoteSaveResult, any Error>] = [:]
    }

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

    /// Saves every note with unsaved edits now and returns the ones that failed.
    @discardableResult
    func flush(within limit: TimeInterval = NoteSavePolicy.flushLimit) -> [NoteSaveFailure] {
        saveTask?.cancel()
        saveTask = nil
        let pending = documents.filter { $0.note.body != $0.base }
        guard !pending.isEmpty else { return [] }
        return save(pending, within: limit)
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
        save([documents[index]], within: NoteSavePolicy.flushLimit)
    }

    /// The writes run off the main thread and get `limit` seconds, so a hung
    /// disk cannot freeze the window or hold quitting. A save still running
    /// then counts as failed, and so does any save asked for before it ends.
    @discardableResult
    private func save(_ documents: [Document], within limit: TimeInterval) -> [NoteSaveFailure] {
        let sent = documents.map(\.note)
        let started = job.withLock { state in
            guard !state.running else { return false }
            state = SaveJob(running: true)
            return true
        }
        guard started else {
            let failures = sent.map { NoteSaveFailure($0, reason: NoteSaveTimeout.stillRunning) }
            lastError = failures.first?.message
            return failures
        }
        let store = store
        let date = now()
        let job = job
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            for document in documents {
                let result = Result { try store.save(document.note, base: document.base, at: date) }
                job.withLock { $0.results[document.note.id] = result }
            }
            let late = job.withLock { state in
                if !state.abandoned { state.running = false }
                return state.abandoned
            }
            done.signal()
            if late { Task { @MainActor in applyLate(sent) } }
        }
        let timedOut = done.wait(timeout: .now() + limit) == .timedOut
        let results = job.withLock { state in
            if timedOut { state.abandoned = true }
            defer { state.results = [:] }
            return state.results
        }
        let timeout = NoteSaveTimeout(seconds: limit).localizedDescription
        let failures = sent.compactMap { note in
            results[note.id].map { apply($0, to: note) } ?? NoteSaveFailure(note, reason: timeout)
        }
        lastError = failures.first?.message
        return failures
    }

    /// Results of a job that outlived its wait. They were reported as failed;
    /// what did reach the disk is taken in now so the next save builds on it.
    private func applyLate(_ sent: [Note]) {
        let results = job.withLock { state in
            state.running = false
            defer { state.results = [:] }
            return state.results
        }
        let failures = sent.compactMap { note in results[note.id].flatMap { apply($0, to: note) } }
        lastError = failures.first?.message
    }

    private func apply(_ result: Result<NoteSaveResult, any Error>, to sent: Note) -> NoteSaveFailure? {
        guard let index = index(of: sent.id) else { return nil }
        let saved: NoteSaveResult
        do {
            saved = try result.get()
        } catch {
            return NoteSaveFailure(sent, reason: error.localizedDescription)
        }
        // A late result can land after the user typed more; that newer text stays.
        let newer = documents[index].note.body == sent.body ? nil : documents[index].note.body
        switch saved {
        case .unchanged(let modified):
            documents[index].diskModified = modified
        case .saved(let file):
            documents[index].note.url = file.url
            markSaved(index, file)
        case .reloaded(let text, let modified):
            documents[index].base = text
            documents[index].diskModified = modified
            guard newer == nil else { break }
            documents[index].note.body = text
            documents[index].note.modified = modified ?? now()
            if sent.id == selectedID { editorRevision += 1 }
        case .keptBoth(let copy, let disk, let modified):
            keepBoth(index, copy: copy, newer: newer, disk: disk, diskModified: modified)
        case .removed:
            if newer == nil { remove(at: index) }
        }
        return nil
    }

    /// The conflict copy holding the editor's text stays open if the original
    /// was. The original takes the other editor's text, or, when the file is
    /// unreadable, goes back to its last saved text and is left alone.
    private func keepBoth(_ index: Int, copy: NoteFile, newer: String?, disk text: String?, diskModified: Date?) {
        let local = documents[index].note
        let original = text ?? documents[index].base
        documents[index].note.body = original
        documents[index].base = original
        documents[index].diskModified = diskModified
        var copied = Self.document(from: copy)
        if let newer { copied.note.body = newer }
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

extension NoteSaveFailure {
    init(_ note: Note, reason: String) {
        self.init(title: note.title, text: note.body, reason: reason)
    }

    var message: String { "Couldn't save “\(title)”: \(reason)" }
}

struct NoteSaveTimeout: LocalizedError {
    static let stillRunning = "An earlier save is still waiting for the disk."

    let seconds: TimeInterval

    var errorDescription: String? { "The disk did not answer within \(Int(seconds)) seconds." }
}

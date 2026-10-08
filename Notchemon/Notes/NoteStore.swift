import Foundation

/// A note's file as found on disk.
enum NoteDisk: Equatable, Sendable {
    case missing
    /// Present but not UTF-8 text, for instance saved in another encoding.
    case unreadable
    case text(String)
}

/// What to do with one note given its text as last read or written (`base`),
/// the file now (`disk`), and the editor (`local`). Neither side is ever
/// dropped: when both changed, the editor's text becomes a conflict copy and
/// the original file keeps the other editor's version, untouched.
enum NoteSync: Equatable, Sendable {
    case none
    case write
    case reload(String)
    /// `disk` is nil when the file is unreadable and stays as it is.
    case conflict(disk: String?)
    case remove
    case restore

    static func decide(base: String, disk: NoteDisk, local: String) -> NoteSync {
        switch disk {
        case .missing:
            return local == base ? .remove : .restore
        case .unreadable:
            return local == base ? .none : .conflict(disk: nil)
        case .text(let disk):
            if disk == base { return local == base ? .none : .write }
            if local == base || local == disk { return .reload(disk) }
            return .conflict(disk: disk)
        }
    }
}

struct NoteFile: Equatable, Sendable {
    let url: URL
    let text: String
    let modified: Date
}

/// The file layer for floating notes: one Markdown file per note, directly in
/// `folder`. It lists and writes only `*.md` files inside that folder, so the
/// quick-note log one level up is out of its reach.
struct NoteStore: Sendable {
    static let folderOverrideKey = "NotchemonNotesFolder"

    let folder: URL
    var timeZone: TimeZone = .current
    var trashItem: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// `~/Documents/Notchemon/Notes`, or the `NotchemonNotesFolder` default
    /// when set, so a debug launch can point at a scratch folder.
    static var standard: NoteStore {
        let fallback = AppPaths.notesFolder.appendingPathComponent("Notes", isDirectory: true)
        let override = UserDefaults.standard.string(forKey: folderOverrideKey) ?? ""
        return NoteStore(folder: folder(override: override, fallback: fallback, quickNoteFolder: AppPaths.notesFolder))
    }

    /// The override, unless it is empty or the quick-note log's own folder,
    /// which would list `notes.md` as a note.
    static func folder(override: String, fallback: URL, quickNoteFolder: URL) -> URL {
        guard !override.isEmpty else { return fallback }
        let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
        let quickNotes = quickNoteFolder.standardizedFileURL.resolvingSymlinksInPath().path
        return resolved == quickNotes ? fallback : url
    }

    /// Newest first. A missing folder is an empty list.
    func loadAll() -> [NoteFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let files: [NoteFile] = names
            .filter { $0.lowercased().hasSuffix(".md") && !$0.hasPrefix(".") }
            .compactMap { read(folder.appendingPathComponent($0)) }
        return files.sorted { $0.modified > $1.modified }
    }

    func read(_ url: URL) -> NoteFile? {
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return NoteFile(url: url, text: text, modified: modificationDate(url) ?? .distantPast)
    }

    func disk(_ url: URL) -> NoteDisk {
        if let file = read(url) { return .text(file.text) }
        return FileManager.default.fileExists(atPath: url.path) ? .unreadable : .missing
    }

    func modificationDate(_ url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    /// Names a new file from the text's title and writes it. The name is
    /// claimed with an exclusive create first, so a file another app made
    /// under the same name a moment earlier is never replaced.
    func create(_ text: String, at date: Date, suffix: String = "") throws -> NoteFile {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let title = Note.title(of: text) + suffix
        while true {
            let name = NoteFileName.make(title: title, date: date, timeZone: timeZone, taken: taken)
            let url = folder.appendingPathComponent(name)
            do {
                try Data().write(to: url, options: .withoutOverwriting)
            } catch CocoaError.fileWriteFileExists {
                taken.insert(name)
                continue
            }
            return try write(text, to: url)
        }
    }

    func write(_ text: String, to url: URL) throws -> NoteFile {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        return NoteFile(url: url, text: text, modified: modificationDate(url) ?? Date())
    }

    /// Moves the file to the Trash; never deletes it outright.
    func trash(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try trashItem(url)
    }
}

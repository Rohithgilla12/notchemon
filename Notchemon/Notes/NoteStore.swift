import Foundation

/// What to do with one note given its text as last read or written (`base`),
/// the file now (`disk`, nil when it is gone), and the editor (`local`).
/// Neither side is ever dropped: when both changed, the editor's text becomes
/// a conflict copy and the original file keeps the other editor's text.
enum NoteSync: Equatable, Sendable {
    case none
    case write
    case reload(String)
    case conflict(disk: String)
    case remove
    case restore

    static func decide(base: String, disk: String?, local: String) -> NoteSync {
        guard let disk else { return local == base ? .remove : .restore }
        if disk == base { return local == base ? .none : .write }
        if local == base || local == disk { return .reload(disk) }
        return .conflict(disk: disk)
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
        if let override = UserDefaults.standard.string(forKey: folderOverrideKey), !override.isEmpty {
            return NoteStore(folder: URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true))
        }
        return NoteStore(folder: AppPaths.notesFolder.appendingPathComponent("Notes", isDirectory: true))
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

    func modificationDate(_ url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    /// Names a new file from the text's title and writes it.
    func create(_ text: String, at date: Date, suffix: String = "") throws -> NoteFile {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let title = Note.title(of: text) + suffix
        let name = NoteFileName.make(title: title, date: date, timeZone: timeZone, taken: taken)
        return try write(text, to: folder.appendingPathComponent(name))
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

import Foundation
import Testing
@testable import Notchemon

/// A throwaway `Notchemon/` folder holding a quick-note log beside `Notes/`,
/// so tests can check the log is never touched. Trashed files land in `trash`.
final class NotesSandbox {
    let root: URL
    let notes: URL
    let quickNoteLog: URL
    let trash: URL
    static let logText = "- [2026-10-07 09:00] the user's real quick notes\n"

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesSandbox-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Notchemon", isDirectory: true)
        notes = root.appendingPathComponent("Notes", isDirectory: true)
        quickNoteLog = root.appendingPathComponent("notes.md")
        trash = root.deletingLastPathComponent().appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data(Self.logText.utf8).write(to: quickNoteLog)
    }

    deinit {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    var store: NoteStore {
        var store = NoteStore(folder: notes, timeZone: TimeZone(identifier: "Asia/Singapore")!)
        let trash = trash
        store.trashItem = { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
        return store
    }

    var noteFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: notes.path)) ?? []).sorted()
    }

    func text(_ name: String) -> String? {
        try? String(contentsOf: notes.appendingPathComponent(name), encoding: .utf8)
    }

    func writeExternally(_ text: String, to name: String) throws {
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: notes.appendingPathComponent(name))
        // Some file systems keep one-second timestamps; make the change visible.
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: notes.appendingPathComponent(name).path)
    }

    var quickNoteLogUntouched: Bool {
        (try? String(contentsOf: quickNoteLog, encoding: .utf8)) == Self.logText
    }
}

let october8 = ISO8601DateFormatter().date(from: "2026-10-08T01:30:00Z")!

struct NoteTests {
    @Test(arguments: [
        ("Groceries\nmilk", "Groceries"),
        ("# Plan for Q4\n- ship", "Plan for Q4"),
        ("   \nsecond line", "Untitled"),
        ("", "Untitled"),
        ("##   ", "Untitled"),
    ])
    func titleIsTheFirstLineWithoutHeadingMarks(body: String, title: String) {
        #expect(Note.title(of: body) == title)
    }

    @Test(arguments: [
        ("Groceries", "groceries"),
        ("Plan for Q4: ship it!", "plan-for-q4-ship-it"),
        ("Café résumé", "cafe-resume"),
        ("  --  ", "untitled"),
        ("snake_case_name", "snake-case-name"),
    ])
    func slugsAreLowercaseKebab(title: String, slug: String) {
        #expect(NoteFileName.slug(title) == slug)
    }

    @Test func longTitlesStopAtAWordBoundary() {
        let slug = NoteFileName.slug(String(repeating: "word ", count: 30))
        #expect(slug.count <= NoteFileName.maxSlugLength)
        #expect(!slug.hasSuffix("-"))
        #expect(slug.hasPrefix("word-word"))
    }

    @Test func fileNamesCarryTheLocalDateAndAreMadeUnique() {
        let singapore = TimeZone(identifier: "Asia/Singapore")!
        let first = NoteFileName.make(title: "Groceries", date: october8, timeZone: singapore, taken: [])
        #expect(first == "20261008-groceries.md")
        let second = NoteFileName.make(title: "Groceries", date: october8, timeZone: singapore, taken: [first, "20261008-groceries-2.md"])
        #expect(second == "20261008-groceries-3.md")
        let caseClash = NoteFileName.make(title: "groceries", date: october8, timeZone: singapore, taken: ["20261008-Groceries.md"])
        #expect(caseClash == "20261008-groceries-2.md")
    }
}

struct NoteSyncTests {
    @Test func cleanNoteWithUnchangedFileDoesNothing() {
        #expect(NoteSync.decide(base: "a", disk: .text("a"), local: "a") == .none)
    }

    @Test func localEditsOverAnUnchangedFileAreWritten() {
        #expect(NoteSync.decide(base: "a", disk: .text("a"), local: "ab") == .write)
    }

    @Test func anExternalEditToACleanNoteIsReloaded() {
        #expect(NoteSync.decide(base: "a", disk: .text("from vim"), local: "a") == .reload("from vim"))
    }

    @Test func bothSidesArrivingAtTheSameTextIsAReload() {
        #expect(NoteSync.decide(base: "a", disk: .text("same"), local: "same") == .reload("same"))
    }

    @Test func anExternalEditOverUnsavedEditsIsAConflict() {
        #expect(NoteSync.decide(base: "a", disk: .text("from vim"), local: "mine") == .conflict(disk: "from vim"))
    }

    @Test func aDeletedFileIsDroppedWhenCleanAndRestoredWhenEdited() {
        #expect(NoteSync.decide(base: "a", disk: .missing, local: "a") == .remove)
        #expect(NoteSync.decide(base: "a", disk: .missing, local: "mine") == .restore)
    }

    @Test func anUnreadableFileIsLeftAloneAndUnsavedTextGoesToACopy() {
        #expect(NoteSync.decide(base: "a", disk: .unreadable, local: "a") == .none)
        #expect(NoteSync.decide(base: "a", disk: .unreadable, local: "mine") == .conflict(disk: nil))
    }
}

struct NoteStoreTests {
    @Test func createNamesTheFileFromTheTitleAndWritesItAtomically() throws {
        let sandbox = try NotesSandbox()
        let file = try sandbox.store.create("Groceries\nmilk", at: october8)
        #expect(file.url.lastPathComponent == "20261008-groceries.md")
        #expect(sandbox.text("20261008-groceries.md") == "Groceries\nmilk")
        let again = try sandbox.store.create("Groceries\neggs", at: october8)
        #expect(again.url.lastPathComponent == "20261008-groceries-2.md")
    }

    @Test func loadAllListsOnlyMarkdownInTheNotesFolderNewestFirst() throws {
        let sandbox = try NotesSandbox()
        try sandbox.writeExternally("Older", to: "a.md")
        try FileManager.default.setAttributes([.modificationDate: october8], ofItemAtPath: sandbox.notes.appendingPathComponent("a.md").path)
        try sandbox.writeExternally("Newer", to: "b.md")
        try sandbox.writeExternally("ignored", to: "c.txt")
        try sandbox.writeExternally("ignored", to: ".hidden.md")
        #expect(sandbox.store.loadAll().map(\.text) == ["Newer", "Older"])
    }

    @Test func aMissingFolderLoadsAsNoNotes() throws {
        let sandbox = try NotesSandbox()
        #expect(sandbox.store.loadAll().isEmpty)
    }

    @Test func trashMovesTheFileAndNeverDeletesIt() throws {
        let sandbox = try NotesSandbox()
        let file = try sandbox.store.create("Doomed", at: october8)
        try sandbox.store.trash(file.url)
        #expect(sandbox.noteFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sandbox.trash.appendingPathComponent("20261008-doomed.md").path))
    }

    @Test func diskTellsAMissingFileFromAnUnreadableOne() throws {
        let sandbox = try NotesSandbox()
        let file = try sandbox.store.create("Plan", at: october8)
        #expect(sandbox.store.disk(file.url) == .text("Plan"))
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: file.url)
        #expect(sandbox.store.disk(file.url) == .unreadable)
        #expect(sandbox.store.disk(sandbox.notes.appendingPathComponent("nope.md")) == .missing)
    }

    /// `create` relies on this error to step past a name taken since it listed the folder.
    @Test func anExclusiveWriteOverAnExistingFileThrowsFileExists() throws {
        let sandbox = try NotesSandbox()
        let file = try sandbox.store.create("Taken", at: october8)
        do {
            try Data().write(to: file.url, options: .withoutOverwriting)
            Issue.record("an exclusive write replaced an existing file")
        } catch CocoaError.fileWriteFileExists {}
        #expect(sandbox.text(file.url.lastPathComponent) == "Taken")
    }

    @Test func theFolderOverrideCannotPointAtTheQuickNoteLogFolder() throws {
        let sandbox = try NotesSandbox()
        let fallback = sandbox.notes
        let elsewhere = sandbox.trash.path
        #expect(NoteStore.folder(override: "", fallback: fallback, quickNoteFolder: sandbox.root) == fallback)
        #expect(NoteStore.folder(override: elsewhere, fallback: fallback, quickNoteFolder: sandbox.root).path == elsewhere)
        #expect(NoteStore.folder(override: sandbox.root.path, fallback: fallback, quickNoteFolder: sandbox.root) == fallback)
        #expect(NoteStore.folder(override: sandbox.root.path + "/", fallback: fallback, quickNoteFolder: sandbox.root) == fallback)
    }

    @Test func theStandardFolderIsTheNotesSubfolderBesideTheQuickNoteLog() {
        let standard = NoteStore(folder: AppPaths.notesFolder.appendingPathComponent("Notes", isDirectory: true))
        #expect(standard.folder.deletingLastPathComponent().standardizedFileURL == AppPaths.notes.deletingLastPathComponent().standardizedFileURL)
        #expect(standard.folder.lastPathComponent == "Notes")
    }
}

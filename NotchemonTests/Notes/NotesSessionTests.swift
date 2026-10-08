import Foundation
import Testing
@testable import Notchemon

@MainActor
struct NotesSessionTests {
    let sandbox: NotesSandbox
    let session: NotesSession

    init() throws {
        sandbox = try NotesSandbox()
        session = NotesSession(store: sandbox.store, now: { october8 })
    }

    @Test func anEmptyFolderOpensOneBlankNoteWithoutAFile() {
        session.load()
        #expect(session.notes.count == 1)
        #expect(session.current?.url == nil)
        session.flush()
        #expect(sandbox.noteFiles.isEmpty)
    }

    @Test func theFirstSaveNamesTheFileAndLaterTitleEditsKeepIt() {
        session.load()
        session.edit("Groceries\nmilk")
        session.flush()
        #expect(sandbox.noteFiles == ["20261008-groceries.md"])
        session.edit("Shopping list\nmilk\neggs")
        session.flush()
        #expect(sandbox.noteFiles == ["20261008-groceries.md"])
        #expect(sandbox.text("20261008-groceries.md") == "Shopping list\nmilk\neggs")
        #expect(session.current?.title == "Shopping list")
    }

    @Test func aNewNoteWaitsForItsTitleLineBeforeTheShortDebounce() {
        #expect(NoteSavePolicy.delay(hasFile: false, text: "Groc") == NoteSavePolicy.untitledDebounce)
        #expect(NoteSavePolicy.delay(hasFile: false, text: "Groceries\n") == NoteSavePolicy.debounce)
        #expect(NoteSavePolicy.delay(hasFile: true, text: "G") == NoteSavePolicy.debounce)
    }

    @Test func reopensTheRememberedNote() throws {
        _ = try sandbox.store.create("First", at: october8)
        let second = try sandbox.store.create("Second", at: october8)
        session.load(selecting: second.url.lastPathComponent)
        #expect(session.current?.title == "Second")
    }

    @Test func newNoteDoesNotStackBlankDraftsAndLeavingADraftDiscardsIt() throws {
        _ = try sandbox.store.create("Kept", at: october8)
        session.load()
        session.newNote()
        session.newNote()
        #expect(session.notes.count == 2)
        session.step(by: 1)
        #expect(session.notes.map(\.title) == ["Kept"])
    }

    @Test func stepMovesThroughTheListWithoutWrapping() throws {
        for title in ["One", "Two", "Three"] { _ = try sandbox.store.create(title, at: october8) }
        session.load()
        let order = session.notes.map(\.title)
        session.step(by: -1)
        #expect(session.current?.title == order[0])
        session.step(by: 1)
        session.step(by: 1)
        session.step(by: 1)
        #expect(session.current?.title == order[2])
    }

    @Test func deleteTrashesTheFileAndOpensTheNeighbour() throws {
        for title in ["One", "Two"] { _ = try sandbox.store.create(title, at: october8) }
        session.load()
        let doomed = try #require(session.current)
        session.delete(session.current!.id)
        #expect(!session.notes.contains { $0.id == doomed.id })
        #expect(session.current != nil)
        #expect(FileManager.default.fileExists(atPath: sandbox.trash.appendingPathComponent(doomed.url!.lastPathComponent).path))
    }

    @Test func deletingTheLastNoteLeavesABlankOne() throws {
        _ = try sandbox.store.create("Only", at: october8)
        session.load()
        session.delete(session.current!.id)
        #expect(session.notes.count == 1)
        #expect(session.current?.body == "")
        #expect(sandbox.noteFiles.isEmpty)
    }

    @Test func anExternalEditReloadsACleanNote() throws {
        let file = try sandbox.store.create("Plan\nv1", at: october8)
        session.load()
        let revision = session.editorRevision
        try sandbox.writeExternally("Plan\nv2 from vim", to: file.url.lastPathComponent)
        session.rescan()
        #expect(session.current?.body == "Plan\nv2 from vim")
        #expect(session.editorRevision > revision)
    }

    @Test func anExternalEditOverUnsavedTextKeepsBothSides() throws {
        let file = try sandbox.store.create("Plan\nv1", at: october8)
        session.load()
        session.edit("Plan\nmy unsaved line")
        try sandbox.writeExternally("Plan\nv2 from vim", to: file.url.lastPathComponent)
        session.flush()
        #expect(sandbox.text(file.url.lastPathComponent) == "Plan\nv2 from vim")
        #expect(sandbox.text("20261008-plan-conflict.md") == "Plan\nmy unsaved line")
        #expect(session.current?.body == "Plan\nmy unsaved line")
        #expect(session.current?.url?.lastPathComponent == "20261008-plan-conflict.md")
        #expect(session.notes.contains { $0.body == "Plan\nv2 from vim" })
    }

    @Test func unsavedTextOverAnUnreadableFileGoesToACopyAndTheFileIsUntouched() throws {
        let file = try sandbox.store.create("Plan\nv1", at: october8)
        session.load()
        session.edit("Plan\nmy unsaved line")
        let foreign = Data([0xFF, 0xFE, 0x50, 0x00])
        try foreign.write(to: file.url)
        session.flush()
        #expect(try Data(contentsOf: file.url) == foreign)
        #expect(sandbox.text("20261008-plan-conflict.md") == "Plan\nmy unsaved line")
        #expect(session.current?.url?.lastPathComponent == "20261008-plan-conflict.md")
        session.flush()
        #expect(sandbox.noteFiles == ["20261008-plan-conflict.md", "20261008-plan.md"])
    }

    @Test func deletingByIdLeavesTheOpenNoteOpen() throws {
        let other = try sandbox.store.create("Other", at: october8)
        let open = try sandbox.store.create("Open", at: october8)
        session.load(selecting: open.url.lastPathComponent)
        let otherID = try #require(session.notes.first { $0.url == other.url }?.id)
        session.delete(otherID)
        #expect(session.current?.title == "Open")
        #expect(session.notes.map(\.title) == ["Open"])
    }

    @Test func rescanPicksUpNewFilesAndDropsDeletedOnes() throws {
        let gone = try sandbox.store.create("Gone", at: october8)
        _ = try sandbox.store.create("Stays", at: october8)
        session.load()
        try FileManager.default.removeItem(at: gone.url)
        try sandbox.writeExternally("Arrived\nfrom Finder", to: "arrived.md")
        session.rescan()
        #expect(Set(session.notes.map(\.title)) == ["Stays", "Arrived"])
    }

    @Test func aSeededNoteIsSavedImmediately() {
        session.load()
        session.newNote(body: "Idea from the notch")
        #expect(sandbox.noteFiles == ["20261008-idea-from-the-notch.md"])
    }

    @Test func noOperationTouchesTheQuickNoteLog() throws {
        let file = try sandbox.store.create("Plan\nv1", at: october8)
        session.load()
        session.edit("Plan\nmine")
        try sandbox.writeExternally("Plan\ntheirs", to: file.url.lastPathComponent)
        session.flush()
        session.newNote(body: "notes")
        session.rescan()
        session.delete(session.current!.id)
        #expect(sandbox.quickNoteLogUntouched)
        #expect(!session.notes.contains { $0.url?.standardizedFileURL == sandbox.quickNoteLog.standardizedFileURL })
    }
}

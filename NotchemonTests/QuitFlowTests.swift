import AppKit
import Foundation
import os
import Testing
@testable import Notchemon

/// Answers the quit alert from a script and records what it was asked.
@MainActor
final class ScriptedQuit: QuitPrompt {
    var choices: [QuitChoice]
    var copies: [Bool]
    var beforeAnswering: () -> Void = {}
    private(set) var asked: [[NoteSaveFailure]] = []
    private(set) var copied: [NoteSaveFailure] = []
    var terminations = 0

    init(_ choices: [QuitChoice], copies: [Bool] = []) {
        self.choices = choices
        self.copies = copies
    }

    func choose(for failures: [NoteSaveFailure]) -> QuitChoice {
        asked.append(failures)
        beforeAnswering()
        return choices.isEmpty ? .quitAnyway : choices.removeFirst()
    }

    func saveCopy(of failure: NoteSaveFailure) -> Bool {
        copied.append(failure)
        return copies.isEmpty ? false : copies.removeFirst()
    }
}

struct QuitDecisionTests {
    let groceries = NoteSaveFailure(title: "Groceries", text: "Groceries\nmilk", reason: "The disk is full.")
    let standup = NoteSaveFailure(title: "Standup", text: "Standup\nnotes", reason: "Permission denied.")

    @Test func quitsWhenEverythingSaved() {
        #expect(QuitDecision.after(saving: []) == .quit)
        #expect(QuitDecision.after(saving: [groceries]) == .ask([groceries]))
    }

    @Test func tryAgainQuitsOnlyWhenTheRetrySaves() {
        #expect(QuitDecision.after(.tryAgain, for: [groceries], retry: { [] }, copy: { _ in false }) == .quit)
        #expect(QuitDecision.after(.tryAgain, for: [groceries], retry: { [standup] }, copy: { _ in false }) == .ask([standup]))
    }

    @Test func saveACopyAsksAgainAboutNotesLeftUncopied() {
        var offered: [String] = []
        let some = QuitDecision.after(.saveCopy, for: [groceries, standup], retry: { [] }, copy: {
            offered.append($0.title)
            return $0 == groceries
        })
        #expect(offered == ["Groceries", "Standup"])
        #expect(some == .ask([standup]))
        #expect(QuitDecision.after(.saveCopy, for: [groceries, standup], retry: { [] }, copy: { _ in true }) == .quit)
    }

    @Test func quitAnywayNeitherRetriesNorCopies() {
        var touched = false
        let decision = QuitDecision.after(.quitAnyway, for: [groceries], retry: {
            touched = true
            return [groceries]
        }, copy: { _ in
            touched = true
            return false
        })
        #expect(decision == .quit)
        #expect(!touched)
    }

    @Test func theAlertNamesEachNoteAndItsError() {
        let one = QuitDecision.alertText(for: [groceries])
        #expect(one.message == "“Groceries” couldn't be saved.")
        #expect(one.detail.hasPrefix("The disk is full."))
        let two = QuitDecision.alertText(for: [groceries, standup])
        #expect(two.message == "2 notes couldn't be saved.")
        #expect(two.detail.contains("“Groceries”: The disk is full."))
        #expect(two.detail.contains("“Standup”: Permission denied."))
    }

    @Test func logoutRestartAndShutdownEndTheSessionButAPlainQuitDoesNot() {
        func quitEvent(_ reason: OSType?) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor.appleEvent(
                withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
                targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
            )
            if let reason {
                event.setAttribute(NSAppleEventDescriptor(enumCode: reason), forKeyword: AEKeyword(kAEQuitReason))
            }
            return event
        }
        for reason in [kAELogOut, kAEReallyLogOut, kAERestart, kAEShowRestartDialog, kAEShutDown, kAEShowShutdownDialog] {
            #expect(QuitReason.endsSession(quitEvent(reason)))
        }
        #expect(!QuitReason.endsSession(quitEvent(nil)))
        #expect(!QuitReason.endsSession(nil))
    }
}

/// A disk whose writes hang until `release()`, then recover.
final class HungDisk: Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let holding = OSAllocatedUnfairLock(initialState: true)

    func store(_ base: NoteStore) -> NoteStore {
        var store = base
        store.writeFile = { [self] data, url in
            if holding.withLock({ $0 }) { gate.wait() }
            try data.write(to: url, options: .atomic)
        }
        return store
    }

    func release() {
        holding.withLock { $0 = false }
        gate.signal()
    }
}

@MainActor
struct QuitSavingTests {
    let sandbox: NotesSandbox

    init() throws {
        sandbox = try NotesSandbox()
    }

    /// A plain file where the notes folder should be makes every save fail.
    func blockNotesFolder() throws {
        try Data().write(to: sandbox.notes)
    }

    func unblockNotesFolder() throws {
        try FileManager.default.removeItem(at: sandbox.notes)
    }

    func editedNotes(_ text: String) -> FloatingNotes {
        let defaults = UserDefaults(suiteName: "NotchemonQuit-\(UUID().uuidString)")!
        let notes = FloatingNotes(store: sandbox.store, defaults: defaults)
        notes.session.load()
        notes.session.edit(text)
        return notes
    }

    func delegate(_ notes: FloatingNotes, _ quit: ScriptedQuit, endsSession: Bool = false) -> AppDelegate {
        AppDelegate(notes: notes, quitPrompt: quit, endsSession: { endsSession }, terminate: { quit.terminations += 1 })
    }

    func mainQueueDrained() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func flushReturnsTheNotesItCouldNotSave() throws {
        try blockNotesFolder()
        let session = editedNotes("Groceries\nmilk").session
        let failures = session.flush()
        #expect(failures.map(\.title) == ["Groceries"])
        #expect(failures.map(\.text) == ["Groceries\nmilk"])
        #expect(failures.allSatisfy { !$0.reason.isEmpty })
        #expect(session.lastError?.contains("Groceries") == true)
    }

    func flushUntilSaved(_ session: NotesSession) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !session.flush(within: 1).isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func aSaveThatOutlastsTheLimitFailsAndItsLateWriteKeepsNewerText() async throws {
        let file = try sandbox.store.create("Groceries\nmilk", at: october8)
        let disk = HungDisk()
        let session = NotesSession(store: disk.store(sandbox.store), now: { october8 })
        session.load()
        session.edit("Groceries\nmilk\neggs")

        let start = Date()
        #expect(session.flush(within: 0.3).map(\.reason) == [NoteSaveTimeout(seconds: 0.3).localizedDescription])
        #expect(Date().timeIntervalSince(start) < 2)
        session.edit("Groceries\nmilk\neggs\nbread")
        #expect(session.flush(within: 0.3).map(\.reason) == [NoteSaveTimeout.stillRunning])

        disk.release()
        try await flushUntilSaved(session)
        #expect(sandbox.noteFiles == [file.url.lastPathComponent])
        #expect(sandbox.text(file.url.lastPathComponent) == "Groceries\nmilk\neggs\nbread")
        #expect(session.current?.body == "Groceries\nmilk\neggs\nbread")
    }

    @Test func aLateFirstSaveOfANewNoteLeavesNoDuplicate() async throws {
        let disk = HungDisk()
        let session = NotesSession(store: disk.store(sandbox.store), now: { october8 })
        session.load()
        session.edit("Groceries\nmilk")
        #expect(session.flush(within: 0.3).map(\.title) == ["Groceries"])
        session.edit("Groceries\nmilk\neggs")

        disk.release()
        try await flushUntilSaved(session)
        #expect(sandbox.noteFiles == ["20261008-groceries.md"])
        #expect(sandbox.text("20261008-groceries.md") == "Groceries\nmilk\neggs")
    }

    @Test func quitAnywayWritesNothingEvenWhenTheDiskRecovers() throws {
        try blockNotesFolder()
        let quit = ScriptedQuit([.quitAnyway])
        quit.beforeAnswering = { try? unblockNotesFolder() }
        let notes = editedNotes("Groceries\nmilk")
        let app = delegate(notes, quit, endsSession: true)

        #expect(app.applicationShouldTerminate(NSApp) == .terminateNow)
        notes.applicationWillTerminate()
        #expect(!FileManager.default.fileExists(atPath: sandbox.notes.path))
    }

    @Test func savedNotesQuitWithoutAsking() throws {
        let quit = ScriptedQuit([])
        let app = delegate(editedNotes("Groceries\nmilk"), quit)
        #expect(app.applicationShouldTerminate(NSApp) == .terminateNow)
        #expect(quit.asked.isEmpty)
        #expect(sandbox.noteFiles.map(sandbox.text) == ["Groceries\nmilk"])
    }

    @Test func aFailedSaveCancelsTheQuitAndAsksUntilTheUserDecides() async throws {
        try blockNotesFolder()
        let quit = ScriptedQuit([.tryAgain, .quitAnyway])
        let app = delegate(editedNotes("Groceries\nmilk"), quit)

        #expect(app.applicationShouldTerminate(NSApp) == .terminateCancel)
        #expect(app.applicationShouldTerminate(NSApp) == .terminateCancel)
        #expect(quit.terminations == 0)
        await mainQueueDrained()

        #expect(quit.asked.map { $0.map(\.title) } == [["Groceries"], ["Groceries"]])
        #expect(quit.asked.flatMap { $0 }.allSatisfy { !$0.reason.isEmpty })
        #expect(quit.terminations == 1)
        #expect(app.applicationShouldTerminate(NSApp) == .terminateNow)
    }

    @Test func tryAgainQuitsOnceTheSaveGoesThrough() async throws {
        try blockNotesFolder()
        let quit = ScriptedQuit([.tryAgain])
        quit.beforeAnswering = { try? unblockNotesFolder() }
        let app = delegate(editedNotes("Groceries\nmilk"), quit)

        #expect(app.applicationShouldTerminate(NSApp) == .terminateCancel)
        await mainQueueDrained()

        #expect(quit.asked.count == 1)
        #expect(quit.terminations == 1)
        #expect(sandbox.noteFiles.map(sandbox.text) == ["Groceries\nmilk"])
    }

    @Test func saveACopyQuitsOnceTheCopyIsSaved() async throws {
        try blockNotesFolder()
        let quit = ScriptedQuit([.saveCopy, .saveCopy], copies: [false, true])
        let app = delegate(editedNotes("Groceries\nmilk"), quit)

        #expect(app.applicationShouldTerminate(NSApp) == .terminateCancel)
        await mainQueueDrained()

        #expect(quit.copied.map(\.text) == ["Groceries\nmilk", "Groceries\nmilk"])
        #expect(quit.asked.count == 2)
        #expect(quit.terminations == 1)
    }

    @Test func atLogoutTheAlertRunsBeforeTheReply() throws {
        try blockNotesFolder()
        let quit = ScriptedQuit([.quitAnyway])
        let app = delegate(editedNotes("Groceries\nmilk"), quit, endsSession: true)

        #expect(app.applicationShouldTerminate(NSApp) == .terminateNow)
        #expect(quit.asked.map { $0.map(\.title) } == [["Groceries"]])
        #expect(quit.terminations == 0)
    }
}

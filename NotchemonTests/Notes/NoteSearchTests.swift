import Foundation
import Testing
@testable import Notchemon

struct NoteSearchTests {
    let notes = [
        Note(body: "Big rocks\nmove them", modified: october8),
        Note(body: "Groceries\n- [ ] Milk\n- [x] eggs", modified: october8),
        Note(body: "Standup\nasked about the release", modified: october8),
    ]

    @Test func anEmptyQueryListsEveryNoteInOrder() {
        #expect(NoteSearch.rank("  ", in: notes).map(\.title) == ["Big rocks", "Groceries", "Standup"])
    }

    @Test func titlesMatchFuzzilyWithWordStartsAndRunsFirst() {
        #expect(NoteSearch.rank("gro", in: notes).map(\.title) == ["Groceries", "Big rocks"])
        #expect(NoteSearch.rank("stu", in: notes).map(\.title) == ["Standup"])
    }

    @Test func bodiesMatchEveryWordAndShowTheLine() {
        let matches = NoteSearch.rank("milk", in: notes)
        #expect(matches.map(\.title) == ["Groceries"])
        #expect(matches.first?.snippet == "- [ ] Milk")
        #expect(NoteSearch.rank("release asked", in: notes).first?.snippet == "asked about the release")
        #expect(NoteSearch.rank("release milk", in: notes).isEmpty)
    }

    @Test func titleMatchesOutrankBodyMatches() {
        let notes = [Note(body: "Plan\nstandup notes", modified: october8), Note(body: "Standup\n", modified: october8)]
        #expect(NoteSearch.rank("standup", in: notes).map(\.title) == ["Standup", "Plan"])
    }
}

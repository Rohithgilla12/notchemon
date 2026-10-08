import AppKit
import Testing
@testable import Notchemon

struct SlashCommandTests {
    func ids(_ query: String) -> [String] {
        SlashCommand.matching(query).map(\.id)
    }

    func applying(_ id: String, to text: String) throws -> (text: String, caret: Int) {
        let command = try #require(SlashCommand.all.first { $0.id == id })
        let string = text as NSString
        let slash = string.range(of: "/", options: .backwards)
        let trigger = NSRange(location: slash.location, length: string.length - slash.location)
        let edit = command.apply(to: string, trigger: trigger)
        #expect(edit.selection.length == 0)
        return (string.replacingCharacters(in: edit.range, with: edit.replacement), edit.selection.location)
    }

    @Test func anEmptyQueryListsEveryCommandInGroups() {
        #expect(ids("") == SlashCommand.all.map(\.id))
        #expect(SlashCommand.matching("").map(\.group.rawValue).first == "Headings")
    }

    @Test func typingFiltersByFuzzyTitle() {
        #expect(ids("h2") == ["h2"])
        #expect(ids("hea") == ["h1", "h2", "h3"])
        #expect(ids("b") == ["bold", "bullets", "numbers"])
        #expect(ids("strk") == ["strikethrough"])
        #expect(ids("zzz").isEmpty)
    }

    @Test func onlyASlashAtALineStartOrAfterSpaceOpensTheMenu() {
        #expect(SlashCommand.opens(at: 0, in: "/"))
        #expect(SlashCommand.opens(at: 2, in: "a /"))
        #expect(SlashCommand.opens(at: 2, in: "a\n/"))
        #expect(!SlashCommand.opens(at: 1, in: "a/b"))
    }

    @Test func blockCommandsReplaceTheLinePrefix() throws {
        #expect(try applying("h1", to: "Plan\n/h1") == ("Plan\n# ", 7))
        #expect(try applying("h2", to: "- [ ] buy /h2") == ("## buy ", 7))
        #expect(try applying("checklist", to: "  milk /check") == ("  - [ ] milk ", 13))
        #expect(try applying("quote", to: "# Title /q") == ("> Title ", 8))
        #expect(try applying("numbers", to: "/num") == ("1. ", 3))
    }

    @Test func blockCommandsLeaveTheRestOfTheLine() throws {
        let command = try #require(SlashCommand.all.first { $0.id == "bullets" })
        let text = "milk /bul and eggs" as NSString
        let edit = command.apply(to: text, trigger: NSRange(location: 5, length: 4))
        #expect(text.replacingCharacters(in: edit.range, with: edit.replacement) == "- milk  and eggs")
        #expect(edit.selection.location == 7)
    }

    @Test func inlineCommandsWrapTheCaret() throws {
        #expect(try applying("bold", to: "say /b") == ("say ****", 6))
        #expect(try applying("italic", to: "/it") == ("__", 1))
        #expect(try applying("strikethrough", to: "x /s") == ("x ~~~~", 4))
        #expect(try applying("code", to: "/code") == ("``", 1))
    }

    @Test func theDividerTakesItsOwnLine() throws {
        #expect(try applying("divider", to: "a\n/div") == ("a\n---\n", 6))
        #expect(try applying("divider", to: "text /div") == ("text \n---\n", 10))
    }

    @Test func theMenuFollowsTheQueryAndClosesWhenItNoLongerApplies() throws {
        let opened = try #require(SlashMenuState.after(nil, slash: 0, text: "/", caret: 1))
        #expect(opened.results.count == SlashCommand.all.count)
        #expect(opened.selectedCommand?.id == "h1")
        let typed = try #require(SlashMenuState.after(opened, slash: 0, text: "/hea", caret: 4))
        #expect(typed.results.map(\.id) == ["h1", "h2", "h3"])
        #expect(typed.moving(by: -1).selectedCommand?.id == "h3")
        #expect(typed.moving(by: 1).moving(by: 1).moving(by: 1).selectedCommand?.id == "h1")
        let moved = typed.moving(by: 1)
        #expect(SlashMenuState.after(moved, slash: 0, text: "/hea", caret: 4)?.selectedCommand?.id == "h2")

        #expect(SlashMenuState.after(typed, slash: 0, text: "/heading ", caret: 9) != nil)
        #expect(SlashMenuState.after(typed, slash: 0, text: "/zz", caret: 3)?.results.isEmpty == true)
        #expect(SlashMenuState.after(typed, slash: 0, text: "/zz ", caret: 4) == nil)
        #expect(SlashMenuState.after(typed, slash: 0, text: "/h\nx", caret: 4) == nil)
        #expect(SlashMenuState.after(typed, slash: 0, text: "/hea", caret: 0) == nil)
        #expect(SlashMenuState.after(typed, slash: 0, text: "hea", caret: 2) == nil)
    }
}

@MainActor
struct SlashMenuEditorTests {
    @Test func returnAppliesTheChosenCommandAsOneUndoStep() throws {
        let editor = EditorHarness("Plan\n")
        let undo = try #require(editor.textView.undoManager)
        // Each key is its own event in the app; here the groups are explicit.
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.type("/", at: 5)
        #expect(editor.textView.slashMenu.isOpen)
        editor.type("h2", at: 6)
        #expect(editor.textView.slashMenu.model.state?.query == "h2")
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        editor.textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        undo.endUndoGrouping()
        #expect(!editor.textView.slashMenu.isOpen)
        #expect(editor.storage.string == "Plan\n## ")
        #expect(editor.textView.selectedRange() == NSRange(location: 8, length: 0))
        undo.undo()
        #expect(editor.storage.string == "Plan\n/h2")
    }

    @Test func arrowsMoveTheSelectionAndEscapeCloses() {
        let editor = EditorHarness("")
        editor.type("/", at: 0)
        editor.textView.doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(editor.textView.slashMenu.model.state?.selectedCommand?.id == "h2")
        editor.textView.cancelOperation(nil)
        #expect(!editor.textView.slashMenu.isOpen)
        #expect(editor.storage.string == "/")
    }

    @Test func aSlashInsideAWordStaysText() {
        let editor = EditorHarness("and")
        editor.type("/", at: 3)
        #expect(!editor.textView.slashMenu.isOpen)
    }

    @Test func movingTheCaretAwayCloses() {
        let editor = EditorHarness("Plan\n")
        editor.type("/", at: 5)
        editor.moveCaret(to: 2)
        #expect(!editor.textView.slashMenu.isOpen)
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

struct NotesWindowFrameTests {
    let laptop = NotesDisplay(id: "laptop", visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
    let monitor = NotesDisplay(id: "monitor", visibleFrame: CGRect(x: 1512, y: -200, width: 2560, height: 1415))

    @Test func aSavedFrameOnScreenIsKept() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(NotesWindowFrame.resolve(saved: ["laptop": frame], on: laptop) == frame)
    }

    @Test func aFrameHangingOffTheEdgeSlidesBackOn() {
        let frame = CGRect(x: 1400, y: 800, width: 400, height: 300)
        #expect(NotesWindowFrame.resolve(saved: ["laptop": frame], on: laptop) == CGRect(x: 1112, y: 644, width: 400, height: 300))
    }

    @Test func aFrameFromABiggerScreenShrinksToFit() {
        let frame = CGRect(x: -50, y: -50, width: 3000, height: 2000)
        #expect(NotesWindowFrame.resolve(saved: ["laptop": frame], on: laptop) == laptop.visibleFrame)
    }

    @Test func aTinyFrameGrowsToTheMinimum() {
        let frame = CGRect(x: 10, y: 10, width: 50, height: 40)
        let resolved = NotesWindowFrame.resolve(saved: ["laptop": frame], on: laptop)
        #expect(resolved.size == NotesWindowFrame.minimumSize)
    }

    @Test func framesAreRememberedPerDisplay() {
        let onLaptop = CGRect(x: 100, y: 100, width: 400, height: 300)
        let onMonitor = CGRect(x: 2000, y: 300, width: 600, height: 700)
        let saved = ["laptop": onLaptop, "monitor": onMonitor]
        #expect(NotesWindowFrame.resolve(saved: saved, on: laptop) == onLaptop)
        #expect(NotesWindowFrame.resolve(saved: saved, on: monitor) == onMonitor)
    }

    @Test func aDisplayWithNoSavedFrameGetsTheTopRightDefault() {
        let frame = NotesWindowFrame.resolve(saved: [:], on: monitor)
        #expect(frame.size == NotesWindowFrame.defaultSize)
        #expect(frame.maxX == monitor.visibleFrame.maxX - NotesWindowFrame.margin)
        #expect(frame.maxY == monitor.visibleFrame.maxY - NotesWindowFrame.margin)
    }

    @Test func aFrameBelongsToTheDisplayHoldingMostOfIt() {
        let straddling = CGRect(x: 1400, y: 100, width: 400, height: 300)
        #expect(NotesWindowFrame.display(for: straddling, among: [laptop, monitor]) == monitor)
        #expect(NotesWindowFrame.display(for: CGRect(x: -900, y: 0, width: 100, height: 100), among: [laptop, monitor]) == nil)
    }

    @Test func framesRoundTripThroughDefaults() {
        let frames = ["laptop": CGRect(x: 1, y: 2, width: 300, height: 400)]
        #expect(NotesWindowFrame.decode(NotesWindowFrame.encode(frames)) == frames)
        #expect(NotesWindowFrame.decode(["bad": "nonsense"]).isEmpty)
    }
}

struct NotesShortcutTests {
    func command(_ characters: String, keyCode: UInt16 = 0, shift: Bool = false, option: Bool = false) -> NotesCommand? {
        NotesShortcut.command(characters: characters, keyCode: keyCode, command: true, shift: shift, option: option, control: false)
    }

    @Test func noteCommands() {
        #expect(command("n") == .newNote)
        #expect(command("p") == .quickSwitcher)
        #expect(command("k") == .quickSwitcher)
        #expect(command("[") == .previous)
        #expect(command("]") == .next)
        #expect(command("\u{7F}", keyCode: NotesShortcut.deleteKeyCode) == .delete)
    }

    @Test func editCommands() {
        #expect(command("z") == .undo)
        #expect(command("Z", shift: true) == .redo)
        #expect(command("v") == .paste)
    }

    @Test func otherCombinationsPassThrough() {
        #expect(command("n", option: true) == nil)
        #expect(command("\u{7F}", keyCode: NotesShortcut.deleteKeyCode, shift: true) == nil)
        #expect(command("q") == nil)
        #expect(NotesShortcut.command(characters: "n", keyCode: 45, command: false, shift: false, option: false, control: false) == nil)
    }
}

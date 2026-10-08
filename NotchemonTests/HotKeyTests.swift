import Carbon.HIToolbox
import Testing
@testable import Notchemon

@MainActor
struct HotKeyTests {
    /// Hotkeys never unregister, so the ones a test makes must outlive it.
    static var keptAlive: [HotKey] = []

    /// Delivers a hotkey press to the app's own Carbon handlers, the way the
    /// system does, without involving the keyboard.
    func press(_ id: UInt32) -> OSStatus {
        var event: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event)
        guard let event else { return OSStatus(eventNotHandledErr) }
        defer { ReleaseEvent(event) }
        var hotKeyID = EventHotKeyID(signature: HotKey.signature, id: id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &hotKeyID)
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }

    /// ⌃⌥N toggles the notch and ⌃⌥⌘N floating notes; each press reaches only its own action.
    @Test func theNotchAndNotesHotkeysEachFireOnlyForTheirOwnPress() throws {
        #expect(HotKey.notchID != HotKey.notesID)
        var fired: [String] = []
        let modifiers = controlKey | optionKey | cmdKey | shiftKey
        let notch = try #require(HotKey(keyCode: kVK_F19, modifiers: modifiers, id: HotKey.notchID) { fired.append("notch") })
        let notes = try #require(HotKey(keyCode: kVK_F18, modifiers: modifiers, id: HotKey.notesID) { fired.append("notes") })
        Self.keptAlive += [notch, notes]

        #expect(press(HotKey.notchID) == noErr)
        #expect(fired == ["notch"])
        #expect(press(HotKey.notesID) == noErr)
        #expect(fired == ["notch", "notes"])
        #expect(press(999) == OSStatus(eventNotHandledErr))
        #expect(fired == ["notch", "notes"])
    }
}

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

    @Test func eachHotkeyFiresOnlyForItsOwnPress() throws {
        var fired: [String] = []
        let modifiers = controlKey | optionKey | cmdKey | shiftKey
        let first = try #require(HotKey(keyCode: kVK_F19, modifiers: modifiers, id: 901) { fired.append("first") })
        let second = try #require(HotKey(keyCode: kVK_F18, modifiers: modifiers, id: 902) { fired.append("second") })
        Self.keptAlive += [first, second]

        #expect(press(901) == noErr)
        #expect(fired == ["first"])
        #expect(press(902) == noErr)
        #expect(fired == ["first", "second"])
        #expect(press(999) == OSStatus(eventNotHandledErr))
        #expect(fired == ["first", "second"])
    }
}

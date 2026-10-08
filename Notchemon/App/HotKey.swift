import Carbon.HIToolbox

/// A system-wide hotkey through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission, unlike a global key-event monitor. Lives for the
/// whole app session, so it never unregisters.
@MainActor
final class HotKey {
    static let signature = OSType(0x4E_54_43_48)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let action: @MainActor () -> Void

    init?(keyCode: Int, modifiers: Int, id: UInt32 = 1, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Every hotkey's handler sees every press, and the first to return
        // noErr consumes it, so each acts only on its own id and passes the rest on.
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let read = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            let handled = MainActor.assumeIsolated {
                guard read == noErr, pressed.signature == HotKey.signature, pressed.id == hotKey.id else { return false }
                hotKey.action()
                return true
            }
            return handled ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &spec, context, &handlerRef)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: Self.signature, id: id)
        let registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    static func controlOptionN(action: @escaping @MainActor () -> Void) -> HotKey? {
        HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey, action: action)
    }

    static func controlOptionCommandN(action: @escaping @MainActor () -> Void) -> HotKey? {
        HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey | cmdKey, id: 2, action: action)
    }
}

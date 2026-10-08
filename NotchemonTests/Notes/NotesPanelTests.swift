import AppKit
import Testing
@testable import Notchemon

@MainActor
struct NotesPanelTests {
    @Test func thePanelIsATranslucentHUDThatNeverAnimatesOrDims() throws {
        let sandbox = try NotesSandbox()
        let defaults = try #require(UserDefaults(suiteName: "NotchemonNotesPanel-\(UUID().uuidString)"))
        let notes = FloatingNotes(store: sandbox.store, defaults: defaults)
        let panel = notes.preparePanel()
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.hasShadow)
        #expect(panel.animationBehavior == .none)
        let material = try #require(panel.contentView as? NSVisualEffectView)
        #expect(material.material == .hudWindow)
        #expect(material.blendingMode == .behindWindow)
        #expect(material.state == .active)
        #expect(material.appearance?.name == .darkAqua)
        notes.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(panel.alphaValue == 1)
    }
}

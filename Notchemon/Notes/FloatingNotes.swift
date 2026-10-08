import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class FloatingNotes: NSObject, NSWindowDelegate {
    static let shared = FloatingNotes(store: .standard)

    static let keepOnTopKey = "NotchemonNotesKeepOnTop"
    static let monospacedKey = "NotchemonNotesMonospaced"
    static let framesKey = "NotchemonNotesFrames"
    static let selectedKey = "NotchemonNotesSelected"
    static let pollInterval: TimeInterval = 2

    let session: NotesSession
    @ObservationIgnored let editor = NoteEditorHandle()
    private(set) var switcherOpen = false
    private(set) var keepOnTop: Bool
    private(set) var monospaced: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var panel: NotesPanel?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var loaded = false
    /// Set once quitting is waiting on a failed save. From then on the window
    /// neither reads nor saves on its own, since the disk may be what failed.
    @ObservationIgnored private var quitting = false

    init(store: NoteStore, defaults: UserDefaults = .standard) {
        session = NotesSession(store: store)
        self.defaults = defaults
        keepOnTop = defaults.object(forKey: Self.keepOnTopKey) as? Bool ?? true
        monospaced = defaults.bool(forKey: Self.monospacedKey)
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationWillTerminate), name: NSApplication.willTerminateNotification, object: nil
        )
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// Hidden or behind another window: bring it forward. Focused: hide it.
    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    /// Opens the window. A non-blank `seed` becomes a new note.
    func show(seed: String? = nil) {
        loadOrRescan()
        if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switcherOpen = false
            session.newNote(body: seed)
        }
        let panel = preparePanel()
        if !panel.isVisible {
            panel.setFrame(openingFrame(), display: false)
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = frontmost }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        startPolling()
        // SwiftUI creates the editor on the first layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let self, !switcherOpen else { return }
            editor.focusAtEnd()
        }
    }

    /// Brings the window forward under the quit alert, so the user sees the
    /// notes at stake.
    func revealForQuit() {
        quitting = true
        stopPolling()
        let panel = preparePanel()
        if !panel.isVisible {
            panel.setFrame(openingFrame(), display: false)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        switcherOpen = false
        saveState()
        stopPolling()
        panel.orderOut(nil)
        previousApp?.activate()
        previousApp = nil
    }

    func setKeepOnTop(_ on: Bool) {
        keepOnTop = on
        defaults.set(on, forKey: Self.keepOnTopKey)
        panel?.level = on ? .floating : .normal
    }

    func setMonospaced(_ on: Bool) {
        monospaced = on
        defaults.set(on, forKey: Self.monospacedKey)
    }

    func openSwitcher() {
        switcherOpen = true
    }

    func closeSwitcher(opening id: UUID? = nil) {
        switcherOpen = false
        if let id { session.select(id) }
        DispatchQueue.main.async { [weak self] in self?.editor.focusAtEnd() }
    }

    func newNote() {
        switcherOpen = false
        session.newNote()
        editor.focusAtEnd()
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: session.store.folder, withIntermediateDirectories: true)
        if let url = session.current?.url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(session.store.folder)
        }
    }

    func confirmDelete() {
        guard let panel, let note = session.current, note.url != nil || !note.body.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(note.title)”?"
        alert.informativeText = "The note moves to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        // By id: polling and saves continue under the sheet and can change the selection.
        let id = note.id
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated {
                self?.session.delete(id)
                self?.editor.focusAtEnd()
            }
        }
    }

    /// Builds the panel once; tests render it without showing it.
    func preparePanel() -> NotesPanel {
        if let panel { return panel }
        let panel = NotesPanel(contentRect: CGRect(origin: .zero, size: NotesWindowFrame.defaultSize))
        let background = NotesMaterial.makeView(cornerRadius: NotesMaterial.windowCornerRadius)
        let hosting = NSHostingView(rootView: NotesView(notes: self))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.level = keepOnTop ? .floating : .normal
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.escape() }
        panel.onCommand = { [weak self] command in self?.perform(command) ?? false }
        self.panel = panel
        return panel
    }

    private func escape() {
        if switcherOpen {
            closeSwitcher()
        } else {
            hide()
        }
    }

    private func perform(_ command: NotesCommand) -> Bool {
        switch command {
        case .newNote: newNote()
        case .quickSwitcher: switcherOpen ? closeSwitcher() : openSwitcher()
        case .previous: step(by: -1)
        case .next: step(by: 1)
        case .delete:
            guard !switcherOpen else { return false }
            confirmDelete()
        case .undo: return NSApp.sendAction(Selector(("undo:")), to: nil, from: panel)
        case .redo: return NSApp.sendAction(Selector(("redo:")), to: nil, from: panel)
        case .cut: return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: panel)
        case .copy: return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: panel)
        case .paste: return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: panel)
        case .selectAll: return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: panel)
        }
        return true
    }

    private func step(by offset: Int) {
        switcherOpen = false
        session.step(by: offset)
        editor.focusAtEnd()
    }

    private func loadOrRescan() {
        if loaded {
            session.rescan()
        } else {
            session.load(selecting: defaults.string(forKey: Self.selectedKey))
            loaded = true
        }
    }

    private func saveState() {
        session.flush()
        rememberPlace()
    }

    private func rememberPlace() {
        if let name = session.currentFileName { defaults.set(name, forKey: Self.selectedKey) }
        saveFrame()
    }

    private func savedFrames() -> [String: CGRect] {
        NotesWindowFrame.decode(defaults.dictionary(forKey: Self.framesKey) as? [String: String] ?? [:])
    }

    private func saveFrame() {
        guard let panel, panel.isVisible,
              let display = NotesWindowFrame.display(for: panel.frame, among: NSScreen.screens.map(\.notesDisplay)) else { return }
        var frames = savedFrames()
        frames[display.id] = panel.frame
        defaults.set(NotesWindowFrame.encode(frames), forKey: Self.framesKey)
    }

    /// The screen under the pointer, where the user is looking.
    private func openingFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        return NotesWindowFrame.resolve(saved: savedFrames(), on: screen.notesDisplay)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.session.rescan() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// The app delegate flushes before it lets the app quit; flushing again
    /// here would write the edits the user chose Quit Anyway to discard.
    @objc func applicationWillTerminate() {
        rememberPlace()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard !quitting else { return }
        session.rescan()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !quitting else { return }
        session.flush()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    // The shadow is computed from the window's alpha once; a new size needs a new one.
    func windowDidResize(_ notification: Notification) {
        panel?.invalidateShadow()
    }
}

extension NSScreen {
    /// Keyed by the display's UUID, which survives reboots and rearranging.
    var notesDisplay: NotesDisplay {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let uuid = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0.uint32Value)?.takeRetainedValue() }
        let id = uuid.flatMap { CFUUIDCreateString(nil, $0) as String? } ?? localizedName
        return NotesDisplay(id: id, visibleFrame: visibleFrame)
    }
}

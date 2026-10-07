import SwiftUI

struct MenuBarContent: View {
    let app: AppDelegate
    let model: CompanionModel

    var body: some View {
        if let species = model.activeSpecies, let progress = model.progress {
            Text("\(species.name) · Level \(progress.level)")
        }
        Button(model.snapshot.focus == nil ? "Start Focus" : "Stop Focus", action: model.toggleFocus)
            .disabled(model.activeSpecies == nil)
        Picker("Focus Length", selection: preference(\.focusMinutes)) {
            ForEach(Preferences.focusLengths, id: \.self) { minutes in
                Text("\(minutes) minutes").tag(minutes)
            }
        }
        Toggle("Sleep When Idle", isOn: preference(\.sleepEnabled))
        Toggle("Virtual Notch on Displays Without One", isOn: preference(\.virtualNotchEnabled))
        Divider()
        Button("Open Notch") { app.windowController?.expandPinned(focusNote: true) }
            .keyboardShortcut("n", modifiers: [.control, .option])
        Button("Choose Creature…", action: app.confirmNewStarter)
        Button("Open Notes Folder", action: app.openNotesFolder)
        Divider()
        Button("Quit Notchemon") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.snapshot.preferences[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        )
    }
}

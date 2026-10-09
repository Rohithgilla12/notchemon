import SwiftUI

struct MenuBarContent: View {
    let app: AppDelegate
    let model: CompanionModel

    var body: some View {
        if let species = model.activeSpecies, let progress = model.progress {
            Text("\(species.name) · Level \(progress.level)")
            Menu("Stats") {
                ForEach(StatsSummary.lines(model.snapshot.stats, now: Date()), id: \.self) { line in
                    Text(line)
                }
            }
        }
        WeatherMenuItem(weather: model.weather)
        Button(model.snapshot.focus == nil ? "Start Focus" : "Stop Focus", action: model.toggleFocus)
            .disabled(model.activeSpecies == nil)
        Picker("Focus Length", selection: preference(\.focusMinutes)) {
            ForEach(Preferences.focusLengths, id: \.self) { minutes in
                Text("\(minutes) minutes").tag(minutes)
            }
        }
        Picker("Focus Sound", selection: preference(\.focusSound)) {
            ForEach(FocusSound.allCases, id: \.self) { sound in
                Text(sound.label).tag(sound)
            }
        }
        Toggle("Sleep When Idle", isOn: preference(\.sleepEnabled))
        Toggle("Virtual Notch on Displays Without One", isOn: preference(\.virtualNotchEnabled))
        Toggle("Click to Open", isOn: preference(\.clickToOpen))
        Toggle("Show Weather", isOn: Binding(get: { model.snapshot.preferences.showsWeather }, set: { model.setShowsWeather($0) }))
        Menu("Motion") {
            Picker("Idle Style", selection: preference(\.idleStyle)) {
                ForEach(IdleStyle.allCases, id: \.self) { style in
                    Text(style.rawValue.capitalized).tag(style)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Wander", selection: preference(\.wander)) {
                Text("Off").tag(WanderRange.off)
                Text("Near the Notch").tag(WanderRange.nearNotch)
                Text("Across the Top Edge").tag(WanderRange.topEdge)
                Text("On the Dock").tag(WanderRange.dock)
                Text("Top Edge and Dock").tag(WanderRange.topEdgeAndDock)
            }
            .pickerStyle(.inline)
            Text(DockWalkingStatus.line(wanted: wantsDock, trusted: app.dockWatcher.isTrusted, read: app.dockWatcher.lastRead))
            if wantsDock, !app.dockWatcher.isTrusted {
                Button("Allow Dock Walking…", action: app.requestDockAccess)
                Button("Accessibility shows it on but it still won't walk?", action: app.explainStaleDockAccess)
            }
            Divider()
            Toggle("Hop When Cursor Comes Near", isOn: preference(\.hopsOnApproach))
            Toggle("Fidgets", isOn: preference(\.fidgets))
        }
        Divider()
        Button("Open Notch") { app.windowController?.expandPinned(focusNote: true) }
            .keyboardShortcut("n", modifiers: [.control, .option])
        Button("Floating Notes") { FloatingNotes.shared.toggle() }
            .keyboardShortcut("n", modifiers: [.control, .option, .command])
        Button("Partners…", action: app.showPartners)
            .disabled(model.activeSpecies == nil)
        Button("Open Notes Folder", action: app.openNotesFolder)
        if case .stashCleared = model.snapshot.banner {
            Button("Undo Clear Stash") { model.undoClearStash(animated: false) }
        } else {
            Button("Clear Stash") { model.clearStash(animated: false) }
                .disabled(model.snapshot.stash.isEmpty)
        }
        if UnlockOverride.isDeveloperBuild(bundleIdentifier: Bundle.main.bundleIdentifier) {
            Menu("Developer") {
                // A closure, not the method itself: CI's Swift 6.2 crashes emitting the thunk for a main-actor method reference here.
                Toggle("Unlock All", isOn: Binding(get: { model.snapshot.unlocks.override }, set: { app.setUnlockAll($0) }))
                Button("Spawn Encounter Now", action: model.spawnEncounterNow)
                    .disabled(model.activeSpecies == nil || model.snapshot.encounter != nil)
                Button("Add 1 km", action: model.addCreatureKilometre)
                    .disabled(model.activeSpecies == nil)
                Button("Add 1 Focus Hour", action: model.addFocusHour)
                    .disabled(model.activeSpecies == nil)
                Divider()
                Button("Reset Collection…", action: app.confirmResetCollection)
            }
        }
        Divider()
        AppMenuSection()
        Divider()
        Button("Quit Notchemon") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var wantsDock: Bool { model.snapshot.preferences.wander.includesDock }

    private func preference<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.snapshot.preferences[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } }
        )
    }
}

import AppKit
import UniformTypeIdentifiers

enum QuitChoice: Equatable {
    case tryAgain
    case saveCopy
    case quitAnyway
}

/// What quitting does next. It quits only once every note is saved, copied
/// elsewhere, or knowingly discarded.
enum QuitDecision: Equatable {
    case quit
    case ask([NoteSaveFailure])

    static func after(saving failures: [NoteSaveFailure]) -> QuitDecision {
        failures.isEmpty ? .quit : .ask(failures)
    }

    /// `retry` saves again and returns what still failed; `copy` saves one
    /// note elsewhere and says whether it did.
    static func after(
        _ choice: QuitChoice,
        for failures: [NoteSaveFailure],
        retry: () -> [NoteSaveFailure],
        copy: (NoteSaveFailure) -> Bool
    ) -> QuitDecision {
        switch choice {
        case .tryAgain:
            return after(saving: retry())
        case .saveCopy:
            return after(saving: failures.filter { !copy($0) })
        case .quitAnyway:
            return .quit
        }
    }

    static func alertText(for failures: [NoteSaveFailure]) -> (message: String, detail: String) {
        let advice = "Try again, save a copy somewhere else, or quit and lose the unsaved changes."
        if failures.count == 1, let failure = failures.first {
            return ("“\(failure.title)” couldn't be saved.", "\(failure.reason)\n\n\(advice)")
        }
        let lines = failures.map { "“\($0.title)”: \($0.reason)" }.joined(separator: "\n")
        return ("\(failures.count) notes couldn't be saved.", "\(lines)\n\n\(advice)")
    }
}

/// Logout, restart, and shutdown quit apps with an Apple event that says why.
enum QuitReason {
    static let sessionEnding: Set<OSType> = [
        kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog, kAEShutDown,
    ]

    static func endsSession(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let reason = event?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else { return false }
        return sessionEnding.contains(reason)
    }
}

@MainActor
protocol QuitPrompt {
    func choose(for failures: [NoteSaveFailure]) -> QuitChoice
    func saveCopy(of failure: NoteSaveFailure) -> Bool
}

@MainActor
struct AlertQuitPrompt: QuitPrompt {
    let notes: FloatingNotes

    func choose(for failures: [NoteSaveFailure]) -> QuitChoice {
        notes.revealForQuit()
        NSApp.activate()
        let text = QuitDecision.alertText(for: failures)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = text.message
        alert.informativeText = text.detail
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Save a Copy…")
        alert.addButton(withTitle: "Quit Anyway").hasDestructiveAction = true
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .saveCopy
        case .alertThirdButtonReturn: return .quitAnyway
        default: return .tryAgain
        }
    }

    func saveCopy(of failure: NoteSaveFailure) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save a Copy of “\(failure.title)”"
        panel.nameFieldStringValue = NoteFileName.make(title: failure.title, date: Date(), taken: [])
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try Data(failure.text.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}

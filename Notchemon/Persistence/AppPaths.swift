import Foundation

enum AppPaths {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchemon", isDirectory: true)
    }

    static var state: URL { support.appendingPathComponent("state.json") }
    static var cache: URL { support.appendingPathComponent("Cache", isDirectory: true) }

    static var notesFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchemon", isDirectory: true)
    }

    static var notes: URL { notesFolder.appendingPathComponent("notes.md") }
}

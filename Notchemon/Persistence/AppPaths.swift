import Foundation

enum AppPaths {
    /// Debug builds carry the `.debug` bundle ID suffix and keep their state
    /// apart from the installed app's.
    static func supportFolderName(bundleIdentifier: String?) -> String {
        bundleIdentifier?.hasSuffix(".debug") == true ? "Notchemon Debug" : "Notchemon"
    }

    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportFolderName(bundleIdentifier: Bundle.main.bundleIdentifier), isDirectory: true)
    }

    static var state: URL { support.appendingPathComponent("state.json") }
    static var cache: URL { support.appendingPathComponent("Cache", isDirectory: true) }

    static var notesFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchemon", isDirectory: true)
    }

    static var notes: URL { notesFolder.appendingPathComponent("notes.md") }
}

import Foundation

struct StateStore: Sendable {
    let url: URL

    static var standard: StateStore { StateStore(url: AppPaths.state) }

    /// Where a state from before the collection is copied, once, before
    /// anything saves over it in the new format.
    var v1Backup: URL { url.deletingLastPathComponent().appendingPathComponent("state.v1.backup.json") }

    /// A missing file is a first launch. An unreadable one is moved aside so
    /// the user can recover it, and the app starts fresh rather than crashing.
    func load() -> CompanionState {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        do {
            let state = try Self.decoder.decode(CompanionState.self, from: data)
            if Self.predatesCollection(data), !FileManager.default.fileExists(atPath: v1Backup.path) {
                try? FileManager.default.copyItem(at: url, to: v1Backup)
            }
            return state
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return .empty
        }
    }

    /// About when the first state was saved: when its folder was made. An
    /// atomic save replaces the file, so the file's own date is the last save.
    var firstSaved: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path))?[.creationDate] as? Date
    }

    func save(_ state: CompanionState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: url, options: .atomic)
    }

    /// A companion saved with `progress` and no `collection`.
    static func predatesCollection(_ data: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object["progress"] != nil && object["collection"] == nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

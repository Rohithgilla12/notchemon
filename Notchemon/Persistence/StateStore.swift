import Foundation

struct StateStore: Sendable {
    let url: URL

    static var standard: StateStore { StateStore(url: AppPaths.state) }

    /// A missing file is a first launch. An unreadable one is moved aside so
    /// the user can recover it, and the app starts fresh rather than crashing.
    func load() -> CompanionState {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        do {
            return try Self.decoder.decode(CompanionState.self, from: data)
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return .empty
        }
    }

    func save(_ state: CompanionState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: url, options: .atomic)
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

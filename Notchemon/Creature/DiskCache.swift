import CryptoKit
import Foundation

/// Cache-first store of fetched bytes, keyed by URL. Creature data and sprites
/// never change once published, so a hit is always served and the network is
/// only touched on a miss; that is also what makes the app work offline.
actor DiskCache {
    let root: URL
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(root: URL) {
        self.root = root
    }

    func cached(_ url: URL) -> Data? {
        try? Data(contentsOf: fileURL(for: url))
    }

    func store(_ data: Data, for url: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: url), options: .atomic)
    }

    func data(for url: URL, using fetcher: any DataFetcher) async throws -> Data {
        if let hit = cached(url) { return hit }
        if let pending = inFlight[url] { return try await pending.value }
        let task = Task { try await fetcher.data(from: url) }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let fresh = try await task.value
        try? store(fresh, for: url)
        return fresh
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(name)
    }
}

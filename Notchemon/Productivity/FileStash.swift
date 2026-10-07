import Foundation

struct StashItem: Sendable, Equatable, Identifiable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Turns file URLs into persistable bookmarks and back. Injected so stash
/// rules are testable without touching the file system.
protocol BookmarkCodec: Sendable {
    func bookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) -> URL?
}

struct SecurityScopedBookmarks: BookmarkCodec {
    func bookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            // Outside the sandbox the scope can be refused; a plain bookmark still
            // survives renames and moves.
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        let url = (try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}

struct StashAddResult: Sendable, Equatable {
    var bookmarks: [Data]
    var added: Int
    var refused: Int
}

enum FileStash {
    /// Adds files oldest-first until full. Files already held are skipped
    /// rather than refused; anything past capacity is refused.
    static func add(_ urls: [URL], to bookmarks: [Data], capacity: Int, codec: any BookmarkCodec) -> StashAddResult {
        var result = StashAddResult(bookmarks: bookmarks, added: 0, refused: 0)
        var held = Set(bookmarks.compactMap { codec.resolve($0)?.standardizedFileURL })
        for url in urls.map(\.standardizedFileURL) where !held.contains(url) {
            guard result.bookmarks.count < capacity else {
                result.refused += 1
                continue
            }
            guard let bookmark = try? codec.bookmark(for: url) else {
                result.refused += 1
                continue
            }
            result.bookmarks.append(bookmark)
            held.insert(url)
            result.added += 1
        }
        return result
    }

    static func remove(_ url: URL, from bookmarks: [Data], codec: any BookmarkCodec) -> [Data] {
        let target = url.standardizedFileURL
        return bookmarks.filter { codec.resolve($0)?.standardizedFileURL != target }
    }

    /// Drops bookmarks whose files are gone, so the stash heals itself.
    static func items(_ bookmarks: [Data], codec: any BookmarkCodec) -> (items: [StashItem], live: [Data]) {
        var items: [StashItem] = []
        var live: [Data] = []
        for bookmark in bookmarks {
            guard let url = codec.resolve(bookmark) else { continue }
            items.append(StashItem(url: url))
            live.append(bookmark)
        }
        return (items, live)
    }
}

import Foundation

struct StashItem: Sendable, Equatable, Identifiable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct ResolvedBookmark: Sendable, Equatable {
    var url: URL
    /// The file was renamed or moved since the bookmark was made, so the
    /// bookmark should be re-created to keep resolving.
    var isStale: Bool
}

/// Turns file URLs into persistable bookmarks and back. Injected so stash
/// rules are testable without touching the file system.
protocol BookmarkCodec: Sendable {
    func bookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) -> ResolvedBookmark?
}

/// Plain bookmarks: the app is not sandboxed, so security scope would grant
/// nothing, but a bookmark still follows a file through renames and moves.
struct FileBookmarks: BookmarkCodec {
    func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ bookmark: Data) -> ResolvedBookmark? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return ResolvedBookmark(url: url, isStale: stale)
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
        var held = Set(bookmarks.compactMap { codec.resolve($0)?.url.standardizedFileURL })
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
        return bookmarks.filter { codec.resolve($0)?.url.standardizedFileURL != target }
    }

    static func restore(_ cleared: [Data], into current: [Data], capacity: Int, codec: any BookmarkCodec) -> StashAddResult {
        let cleared = cleared.filter { codec.resolve($0) != nil }
        let restoring = Set(cleared.compactMap { codec.resolve($0)?.url.standardizedFileURL })
        let newer = current.filter { bookmark in
            guard let url = codec.resolve(bookmark)?.url.standardizedFileURL else { return false }
            return !restoring.contains(url)
        }
        let restored = Array(cleared.prefix(max(0, capacity - newer.count)))
        return StashAddResult(bookmarks: restored + newer, added: restored.count, refused: cleared.count - restored.count)
    }

    /// Drops bookmarks whose files are gone and re-creates stale ones, so the
    /// stash heals itself.
    static func items(_ bookmarks: [Data], codec: any BookmarkCodec) -> (items: [StashItem], live: [Data]) {
        var items: [StashItem] = []
        var live: [Data] = []
        for bookmark in bookmarks {
            guard let resolved = codec.resolve(bookmark) else { continue }
            items.append(StashItem(url: resolved.url))
            let refreshed = resolved.isStale ? try? codec.bookmark(for: resolved.url) : nil
            live.append(refreshed ?? bookmark)
        }
        return (items, live)
    }
}

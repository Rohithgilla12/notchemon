import CoreGraphics
import Foundation
import ImageIO

struct SpriteCollabSprite: Sendable {
    let frames: [CGImage]
    let durations: [TimeInterval]
    /// The PMD anim that satisfied the request after fallbacks.
    let animName: String
    /// Display names where known, raw author ids otherwise. Never empty when
    /// the species has any credits, since CC BY-NC requires attribution.
    let authors: [String]
}

enum SpriteCollabError: Error, Equatable {
    case noAnimation(dex: Int, animation: PMDAnimation)
    case undecodableImage(URL)
    case undecodableText(URL)
}

/// Fetches and slices SpriteCollab sprites. All network access goes through
/// `fetch`, so callers can route it through a disk cache or a test double.
actor SpriteCollabClient {
    typealias Fetch = @Sendable (URL) async throws -> Data

    private struct SheetKey: Hashable {
        let dex: Int
        let sheetName: String
    }

    private let fetch: Fetch
    private var animData: [Int: Task<PMDAnimData, any Error>] = [:]
    private var sheets: [SheetKey: Task<PMDSheet, any Error>] = [:]
    private var credits: [Int: Task<PMDCredits, any Error>] = [:]
    private var creditNames: Task<PMDCreditNames?, Never>?

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func sprite(dex: Int, animation: PMDAnimation, facing: PMDFacing) async throws -> SpriteCollabSprite {
        let data = try await animData(dex: dex)
        guard let resolved = data.resolve(animation) else {
            throw SpriteCollabError.noAnimation(dex: dex, animation: animation)
        }
        let sheet = try await sheet(dex: dex, spec: resolved.spec)
        let authors = try await authors(dex: dex, sheetName: resolved.spec.sheetName)
        return SpriteCollabSprite(
            frames: sheet.frames(facing: facing),
            durations: sheet.durations,
            animName: resolved.name,
            authors: authors
        )
    }

    private func animData(dex: Int) async throws -> PMDAnimData {
        let task = animData[dex] ?? Task { [fetch] in
            try PMDAnimData(xml: try await fetch(SpriteCollabEndpoint.animData(dex: dex)))
        }
        animData[dex] = task
        do {
            return try await task.value
        } catch {
            if animData[dex] == task { animData[dex] = nil }
            throw error
        }
    }

    private func sheet(dex: Int, spec: PMDAnimSpec) async throws -> PMDSheet {
        let key = SheetKey(dex: dex, sheetName: spec.sheetName)
        let task = sheets[key] ?? Task { [fetch] in
            let url = SpriteCollabEndpoint.sheet(dex: dex, name: spec.sheetName)
            return try PMDSheet(image: try Self.decodeImage(try await fetch(url), from: url), spec: spec)
        }
        sheets[key] = task
        do {
            return try await task.value
        } catch {
            if sheets[key] == task { sheets[key] = nil }
            throw error
        }
    }

    private func authors(dex: Int, sheetName: String) async throws -> [String] {
        let task = credits[dex] ?? Task { [fetch] in
            let url = SpriteCollabEndpoint.credits(dex: dex)
            return PMDCredits(text: try Self.decodeText(try await fetch(url), from: url))
        }
        credits[dex] = task
        let parsed: PMDCredits
        do {
            parsed = try await task.value
        } catch {
            if credits[dex] == task { credits[dex] = nil }
            throw error
        }

        let named = parsed.authors(for: sheetName)
        let ids = named.isEmpty ? parsed.allAuthors : named
        let names = await creditNamesOnce()
        return ids.map { names?.displayName(for: $0) ?? $0 }
    }

    /// Names are cosmetic, so a failed fetch falls back to raw ids instead of
    /// failing the sprite, and the next sprite request tries again.
    private func creditNamesOnce() async -> PMDCreditNames? {
        let task = creditNames ?? Task { [fetch] in
            let url = SpriteCollabEndpoint.creditNames
            guard let data = try? await fetch(url), let text = try? Self.decodeText(data, from: url) else {
                return nil
            }
            return PMDCreditNames(text: text)
        }
        creditNames = task
        let names = await task.value
        if names == nil, creditNames == task { creditNames = nil }
        return names
    }

    private static func decodeImage(_ data: Data, from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw SpriteCollabError.undecodableImage(url) }
        return image
    }

    private static func decodeText(_ data: Data, from url: URL) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SpriteCollabError.undecodableText(url)
        }
        return text
    }
}

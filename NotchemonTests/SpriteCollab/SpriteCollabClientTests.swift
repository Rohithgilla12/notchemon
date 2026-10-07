import Foundation
import Testing
@testable import Notchemon

private struct MissingFixture: Error {}

private actor FakeServer {
    private var files: [URL: Data] = [:]
    private var fetched: [URL] = []

    func put(_ url: URL, _ data: Data) { files[url] = data }

    func addSpecies(dex: Int, credits: String = "t\tSTUDIO\tCUR\tUnspecified\tIdle,Sleep,Laying,Walk") {
        files[SpriteCollabEndpoint.animData(dex: dex)] = SpriteFixtures.animData("""
        \(SpriteFixtures.anim("Idle", width: 10, height: 12, durations: [6, 12, 18]))
        \(SpriteFixtures.anim("Laying", width: 8, height: 8, durations: [30, 30]))
        \(SpriteFixtures.alias("Sleep", of: "Laying"))
        """)
        files[SpriteCollabEndpoint.sheet(dex: dex, name: "Idle")] = SpriteFixtures.png(
            SpriteFixtures.sheet(frameWidth: 10, frameHeight: 12, columns: 3, rows: 8)
        )
        files[SpriteCollabEndpoint.sheet(dex: dex, name: "Laying")] = SpriteFixtures.png(
            SpriteFixtures.sheet(frameWidth: 8, frameHeight: 8, columns: 2, rows: 1)
        )
        files[SpriteCollabEndpoint.shadow(dex: dex, name: "Idle")] = SpriteFixtures.png(SpriteFixtures.shadowSheet(
            frameWidth: 10, frameHeight: 12, columns: 3, rows: 8, shadow: CGRect(x: 2, y: 8, width: 6, height: 3)
        ) { cell in CGPoint(x: 2 + cell.column, y: 8 + cell.row % 3) })
        files[SpriteCollabEndpoint.shadow(dex: dex, name: "Laying")] = SpriteFixtures.png(SpriteFixtures.shadowSheet(
            frameWidth: 8, frameHeight: 8, columns: 2, rows: 1, shadow: CGRect(x: 1, y: 5, width: 6, height: 2)
        ) { cell in CGPoint(x: 3 + cell.column, y: 6) })
        files[SpriteCollabEndpoint.credits(dex: dex)] = Data(credits.utf8)
    }

    func remove(_ url: URL) { files[url] = nil }

    func fetch(_ url: URL) throws -> Data {
        fetched.append(url)
        guard let data = files[url] else { throw MissingFixture() }
        return data
    }

    func count(_ url: URL) -> Int { fetched.filter { $0 == url }.count }

    nonisolated func client() -> SpriteCollabClient {
        SpriteCollabClient { url in
            await Task.yield()
            return try await self.fetch(url)
        }
    }
}

struct SpriteCollabClientTests {
    @Test func returnsFramesForTheFacingWithDurationsAndAuthors() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 7)

        let sprite = try await server.client().sprite(dex: 7, animation: .idle, facing: .upLeft)

        #expect(sprite.animName == "Idle")
        #expect(sprite.frames.map(SpriteFixtures.cell) == (0..<3).map { Cell(column: $0, row: 5) })
        #expect(sprite.durations == [0.1, 0.2, 0.3])
        #expect(sprite.groundPoints == [CGPoint(x: 2, y: 10), CGPoint(x: 3, y: 10), CGPoint(x: 4, y: 10)])
        #expect(sprite.authors == ["STUDIO"])
    }

    @Test func missingShadowKeepsTheSpriteWithoutGroundPointsAndIsRetried() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 11)
        await server.remove(SpriteCollabEndpoint.shadow(dex: 11, name: "Idle"))
        let client = server.client()

        let sprite = try await client.sprite(dex: 11, animation: .idle, facing: .down)
        _ = try await client.sprite(dex: 11, animation: .idle, facing: .left)

        #expect(sprite.frames.count == 3)
        #expect(sprite.groundPoints == nil)
        #expect(await server.count(SpriteCollabEndpoint.shadow(dex: 11, name: "Idle")) == 2)
    }

    @Test func fetchesAnimDataOncePerDex() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 1)
        await server.addSpecies(dex: 2)
        let client = server.client()

        _ = try await client.sprite(dex: 1, animation: .idle, facing: .down)
        _ = try await client.sprite(dex: 1, animation: .sleep, facing: .left)
        _ = try await client.sprite(dex: 1, animation: .hop, facing: .right)
        _ = try await client.sprite(dex: 2, animation: .idle, facing: .down)

        #expect(await server.count(SpriteCollabEndpoint.animData(dex: 1)) == 1)
        #expect(await server.count(SpriteCollabEndpoint.animData(dex: 2)) == 1)
        #expect(await server.count(SpriteCollabEndpoint.sheet(dex: 1, name: "Idle")) == 1)
        #expect(await server.count(SpriteCollabEndpoint.credits(dex: 1)) == 1)
    }

    @Test func concurrentRequestsShareOneFetch() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 3)
        let client = server.client()

        async let first = client.sprite(dex: 3, animation: .idle, facing: .down)
        async let second = client.sprite(dex: 3, animation: .idle, facing: .up)
        _ = try await (first, second)

        #expect(await server.count(SpriteCollabEndpoint.animData(dex: 3)) == 1)
        #expect(await server.count(SpriteCollabEndpoint.sheet(dex: 3, name: "Idle")) == 1)
    }

    @Test func aliasFetchesTheTargetSheet() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 4)

        let sprite = try await server.client().sprite(dex: 4, animation: .sleep, facing: .left)

        #expect(sprite.animName == "Sleep")
        #expect(sprite.frames.map(SpriteFixtures.cell) == [Cell(column: 0, row: 0), Cell(column: 1, row: 0)])
        #expect(sprite.groundPoints == [CGPoint(x: 3, y: 6), CGPoint(x: 4, y: 6)])
        #expect(await server.count(SpriteCollabEndpoint.sheet(dex: 4, name: "Laying")) == 1)
        #expect(await server.count(SpriteCollabEndpoint.sheet(dex: 4, name: "Sleep")) == 0)
        #expect(await server.count(SpriteCollabEndpoint.shadow(dex: 4, name: "Laying")) == 1)
        #expect(await server.count(SpriteCollabEndpoint.shadow(dex: 4, name: "Sleep")) == 0)
    }

    @Test func fallsBackToAnotherAnimWhenTheFirstChoiceIsMissing() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 5)

        let sprite = try await server.client().sprite(dex: 5, animation: .pose, facing: .down)

        #expect(sprite.animName == "Idle")
    }

    @Test func throwsWhenNoFallbackExists() async throws {
        let server = FakeServer()
        await server.put(SpriteCollabEndpoint.animData(dex: 6), SpriteFixtures.animData(
            SpriteFixtures.anim("Attack", width: 8, height: 8, durations: [1])
        ))

        await #expect(throws: SpriteCollabError.noAnimation(dex: 6, animation: .idle)) {
            try await server.client().sprite(dex: 6, animation: .idle, facing: .down)
        }
    }

    @Test func mapsAuthorIDsToDisplayNamesWhenAvailable() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 8, credits: "t\tSTUDIO\tCUR\tU\tIdle\nt\t<@!111>\tCUR\tU\tIdle")
        await server.put(SpriteCollabEndpoint.creditNames, Data("Name\tDiscord\tContact\nArtist\t<@!111>\t\n".utf8))

        let sprite = try await server.client().sprite(dex: 8, animation: .idle, facing: .down)

        #expect(sprite.authors == ["STUDIO", "Artist"])
    }

    @Test func creditsEveryAuthorWhenTheAnimIsUnlisted() async throws {
        let server = FakeServer()
        await server.addSpecies(dex: 9, credits: "t\tSTUDIO\tCUR\tU\tWalk\nt\tPORTRAITIST\tCUR\tU\tAttack")

        let sprite = try await server.client().sprite(dex: 9, animation: .idle, facing: .down)

        #expect(sprite.authors == ["STUDIO", "PORTRAITIST"])
    }

    @Test func retriesAfterAFailedFetch() async throws {
        let server = FakeServer()
        let client = server.client()

        await #expect(throws: MissingFixture.self) {
            try await client.sprite(dex: 10, animation: .idle, facing: .down)
        }

        await server.addSpecies(dex: 10)
        let sprite = try await client.sprite(dex: 10, animation: .idle, facing: .down)

        #expect(sprite.frames.count == 3)
        #expect(await server.count(SpriteCollabEndpoint.animData(dex: 10)) == 2)
    }
}

import Testing
@testable import Notchemon

struct PMDCreditsTests {
    let text = """
    2020-10-07 17:58:43.416193\tSTUDIO\tCUR\tUnspecified\tWalk,Attack,Sleep,Idle
    2022-04-14 00:56:01.712419\t<@!111>\tCUR\tPMDCollab_1\tIdle, Hop ,Pose

    garbage-without-tabs
    2023-01-01 00:00:00.000000\t\tCUR\tUnspecified\tIdle
    2023-02-02 00:00:00.000000\tPORTRAITIST
    2024-03-03 00:00:00.000000\tSTUDIO\tCUR\tUnspecified\tEat
    """

    @Test func parsesContributionsAndSkipsMalformedLines() {
        let credits = PMDCredits(text: text)

        #expect(credits.contributions.map(\.authorID) == ["STUDIO", "<@!111>", "PORTRAITIST", "STUDIO"])
        #expect(credits.contributions[1] == PMDCredits.Contribution(
            timestamp: "2022-04-14 00:56:01.712419",
            authorID: "<@!111>",
            status: "CUR",
            license: "PMDCollab_1",
            animNames: ["Idle", "Hop", "Pose"]
        ))
        #expect(credits.contributions[2].animNames.isEmpty)
    }

    @Test func authorsForAnAnimAreUniqueInFileOrder() {
        let credits = PMDCredits(text: text)

        #expect(credits.authors(for: "Idle") == ["STUDIO", "<@!111>"])
        #expect(credits.authors(for: "Hop") == ["<@!111>"])
        #expect(credits.authors(for: "Eat") == ["STUDIO"])
        #expect(credits.authors(for: "Charge").isEmpty)
    }

    @Test func allAuthorsAreUniqueInFileOrder() {
        #expect(PMDCredits(text: text).allAuthors == ["STUDIO", "<@!111>", "PORTRAITIST"])
    }

    @Test func creditNamesMapDiscordIDsToDisplayNames() {
        let names = PMDCreditNames(text: """
        Name\tDiscord\tContact
        Studio\tSTUDIO\thttps://example.com/
        Artist\t<@!111>\t<@111>
        \t<@!222>\t
        broken-line
        """)

        #expect(names.displayName(for: "STUDIO") == "Studio")
        #expect(names.displayName(for: "<@!111>") == "Artist")
        #expect(names.displayName(for: "<@!222>") == nil)
        #expect(names.displayName(for: "<@!333>") == nil)
    }
}

import Foundation
import Testing
@testable import Notchemon

struct PMDAnimDataTests {
    typealias F = SpriteFixtures

    @Test func parsesConcreteAnims() throws {
        let xml = F.animData("""
        <Anim>
            <Name>Attack</Name>
            <Index>1</Index>
            <FrameWidth>80</FrameWidth>
            <FrameHeight>72</FrameHeight>
            <RushFrame>1</RushFrame>
            <HitFrame>3</HitFrame>
            <ReturnFrame>6</ReturnFrame>
            <Durations>
                <Duration>2</Duration>
                <Duration>4</Duration>
                <Duration>1</Duration>
            </Durations>
        </Anim>
        \(F.anim("Idle", width: 40, height: 56, durations: [40, 2, 3, 3, 3, 2]))
        """)

        let data = try PMDAnimData(xml: xml)

        #expect(data.anims == [
            "Attack": PMDAnimSpec(sheetName: "Attack", frameWidth: 80, frameHeight: 72, durations: [2, 4, 1]),
            "Idle": PMDAnimSpec(sheetName: "Idle", frameWidth: 40, frameHeight: 56, durations: [40, 2, 3, 3, 3, 2]),
        ])
    }

    @Test func resolvesCopyOfChainsToTheTargetSheet() throws {
        let data = try PMDAnimData(xml: F.animData("""
        \(F.alias("Dance", of: "Twirl"))
        \(F.alias("Twirl", of: "Rotate"))
        \(F.anim("Rotate", width: 24, height: 32, durations: [4, 4]))
        """))

        let rotate = PMDAnimSpec(sheetName: "Rotate", frameWidth: 24, frameHeight: 32, durations: [4, 4])
        #expect(data.anims == ["Dance": rotate, "Twirl": rotate, "Rotate": rotate])
    }

    @Test func dropsCopyOfCyclesAndKeepsTheRest() throws {
        let data = try PMDAnimData(xml: F.animData("""
        \(F.alias("A", of: "B"))
        \(F.alias("B", of: "C"))
        \(F.alias("C", of: "A"))
        \(F.alias("Self", of: "Self"))
        \(F.anim("Walk", width: 32, height: 40, durations: [8]))
        """))

        #expect(Set(data.anims.keys) == ["Walk"])
    }

    @Test func dropsDanglingCopyOf() throws {
        let data = try PMDAnimData(xml: F.animData("""
        \(F.alias("Sleep", of: "Missing"))
        \(F.anim("Walk", width: 32, height: 40, durations: [8]))
        """))

        #expect(Set(data.anims.keys) == ["Walk"])
    }

    @Test func skipsAnimsWithMissingFields() throws {
        let data = try PMDAnimData(xml: F.animData("""
        <Anim><Name>NoHeight</Name><FrameWidth>8</FrameWidth><Durations><Duration>2</Duration></Durations></Anim>
        <Anim><Name>NoDurations</Name><FrameWidth>8</FrameWidth><FrameHeight>8</FrameHeight></Anim>
        <Anim><Name>BadDuration</Name><FrameWidth>8</FrameWidth><FrameHeight>8</FrameHeight><Durations><Duration>x</Duration></Durations></Anim>
        <Anim><FrameWidth>8</FrameWidth><FrameHeight>8</FrameHeight><Durations><Duration>2</Duration></Durations></Anim>
        \(F.alias("CopiesBroken", of: "NoHeight"))
        \(F.anim("Walk", width: 32, height: 40, durations: [8]))
        """))

        #expect(Set(data.anims.keys) == ["Walk"])
    }

    @Test func malformedXMLThrows() {
        #expect(throws: PMDAnimDataError.self) {
            try PMDAnimData(xml: Data("<AnimData><Anims><Anim>".utf8))
        }
    }

    @Test func resolveWalksTheFallbackList() throws {
        let data = try PMDAnimData(xml: F.animData("""
        \(F.anim("Charge", width: 8, height: 8, durations: [1]))
        \(F.anim("Idle", width: 8, height: 8, durations: [1]))
        """))

        #expect(data.resolve(.pose)?.name == "Charge")
        #expect(data.resolve(.sleep)?.name == "Idle")
        #expect(data.resolve(.idle)?.name == "Idle")
    }

    @Test func resolveReportsTheAliasNameAndTargetSheet() throws {
        let data = try PMDAnimData(xml: F.animData("""
        \(F.alias("Sleep", of: "Laying"))
        \(F.anim("Laying", width: 8, height: 8, durations: [1]))
        """))

        let resolved = try #require(data.resolve(.sleep))
        #expect(resolved.name == "Sleep")
        #expect(resolved.spec.sheetName == "Laying")
    }

    @Test func sittingLiesDownAndNeverUsesTheSitAnimOrIdle() throws {
        let withLaying = try PMDAnimData(xml: F.animData("""
        \(F.anim("Sit", width: 8, height: 8, durations: [8, 8, 8]))
        \(F.anim("Laying", width: 8, height: 8, durations: [12]))
        \(F.anim("Idle", width: 8, height: 8, durations: [1]))
        """))
        let withoutLaying = try PMDAnimData(xml: F.animData("""
        \(F.anim("Sit", width: 8, height: 8, durations: [8, 8, 8]))
        \(F.anim("Idle", width: 8, height: 8, durations: [1]))
        """))

        #expect(withLaying.resolve(.sit)?.name == "Laying")
        #expect(withoutLaying.resolve(.sit) == nil)
    }

    @Test func resolveIsNilWhenNoFallbackExists() throws {
        let data = try PMDAnimData(xml: F.animData(F.anim("Attack", width: 8, height: 8, durations: [1])))

        #expect(data.resolve(.idle) == nil)
    }
}

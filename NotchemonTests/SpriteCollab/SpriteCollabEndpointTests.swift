import Testing
@testable import Notchemon

struct SpriteCollabEndpointTests {
    let base = "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/"

    @Test func buildsZeroPaddedSpriteURLs() {
        #expect(SpriteCollabEndpoint.animData(dex: 7).absoluteString == base + "sprite/0007/AnimData.xml")
        #expect(SpriteCollabEndpoint.sheet(dex: 151, name: "Idle").absoluteString == base + "sprite/0151/Idle-Anim.png")
        #expect(SpriteCollabEndpoint.credits(dex: 1000).absoluteString == base + "sprite/1000/credits.txt")
        #expect(SpriteCollabEndpoint.portrait(dex: 42).absoluteString == base + "portrait/0042/Normal.png")
        #expect(SpriteCollabEndpoint.creditNames.absoluteString == base + "credit_names.txt")
    }
}

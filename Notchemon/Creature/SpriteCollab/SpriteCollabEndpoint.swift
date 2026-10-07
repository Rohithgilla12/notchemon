import Foundation

enum SpriteCollabEndpoint {
    static let root = URL(string: "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/")!

    static func animData(dex: Int) -> URL {
        spriteDirectory(dex: dex).appending(path: "AnimData.xml")
    }

    static func sheet(dex: Int, name: String) -> URL {
        spriteDirectory(dex: dex).appending(path: "\(name)-Anim.png")
    }

    static func shadow(dex: Int, name: String) -> URL {
        spriteDirectory(dex: dex).appending(path: "\(name)-Shadow.png")
    }

    static func credits(dex: Int) -> URL {
        spriteDirectory(dex: dex).appending(path: "credits.txt")
    }

    static func portrait(dex: Int) -> URL {
        root.appending(path: "portrait/\(dex4(dex))/Normal.png")
    }

    static let creditNames = root.appending(path: "credit_names.txt")
    static let project = URL(string: "https://github.com/PMDCollab/SpriteCollab")!

    static func dex4(_ dex: Int) -> String {
        String(format: "%04d", dex)
    }

    private static func spriteDirectory(dex: Int) -> URL {
        root.appending(path: "sprite/\(dex4(dex))")
    }
}

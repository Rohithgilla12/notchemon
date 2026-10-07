import Foundation

struct PMDAnimSpec: Sendable, Equatable {
    /// The anim whose `{sheetName}-Anim.png` holds the frames. Differs from the
    /// anim's own name when it is a `CopyOf` alias, since aliases ship no PNG.
    let sheetName: String
    let frameWidth: Int
    let frameHeight: Int
    /// Per-frame durations in game ticks of 1/60 s.
    let durations: [Int]
}

enum PMDAnimDataError: Error, Equatable {
    case malformedXML(String)
}

/// A parsed `AnimData.xml` with every `CopyOf` alias resolved. Aliases that
/// point nowhere or form a cycle are dropped rather than failing the species.
struct PMDAnimData: Sendable, Equatable {
    let anims: [String: PMDAnimSpec]

    init(xml: Data) throws {
        let entries = try AnimDataXMLReader.read(xml)
        anims = Self.resolveCopies(entries)
    }

    func resolve(_ animation: PMDAnimation) -> (name: String, spec: PMDAnimSpec)? {
        for name in animation.fallbackNames {
            if let spec = anims[name] { return (name, spec) }
        }
        return nil
    }

    private static func resolveCopies(_ entries: [AnimEntry]) -> [String: PMDAnimSpec] {
        var bodies: [String: AnimEntry.Body] = [:]
        for entry in entries where bodies[entry.name] == nil {
            bodies[entry.name] = entry.body
        }

        var resolved: [String: PMDAnimSpec] = [:]
        for name in bodies.keys {
            resolved[name] = spec(following: name, in: bodies)
        }
        return resolved
    }

    private static func spec(following name: String, in bodies: [String: AnimEntry.Body]) -> PMDAnimSpec? {
        var visited: Set<String> = []
        var current = name
        while visited.insert(current).inserted {
            switch bodies[current] {
            case let .frames(width, height, durations)?:
                return PMDAnimSpec(sheetName: current, frameWidth: width, frameHeight: height, durations: durations)
            case let .copyOf(target)?:
                current = target
            case nil:
                return nil
            }
        }
        return nil
    }
}

private struct AnimEntry {
    enum Body {
        case frames(width: Int, height: Int, durations: [Int])
        case copyOf(String)
    }

    let name: String
    let body: Body
}

/// Collects `<Anim>` elements; incomplete ones are skipped so one bad entry
/// does not cost the whole species.
private final class AnimDataXMLReader: NSObject, XMLParserDelegate {
    private struct Draft {
        var name: String?
        var frameWidth: Int?
        var frameHeight: Int?
        var durations: [Int] = []
        var copyOf: String?

        var entry: AnimEntry? {
            guard let name, !name.isEmpty else { return nil }
            if let copyOf, !copyOf.isEmpty { return AnimEntry(name: name, body: .copyOf(copyOf)) }
            guard let frameWidth, let frameHeight, frameWidth > 0, frameHeight > 0,
                  !durations.isEmpty, durations.allSatisfy({ $0 > 0 })
            else { return nil }
            return AnimEntry(name: name, body: .frames(width: frameWidth, height: frameHeight, durations: durations))
        }
    }

    private var entries: [AnimEntry] = []
    private var draft: Draft?
    private var text = ""

    static func read(_ data: Data) throws -> [AnimEntry] {
        let reader = AnimDataXMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw PMDAnimDataError.malformedXML(parser.parserError?.localizedDescription ?? "unknown")
        }
        return reader.entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if elementName == "Anim" { draft = Draft() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard draft != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Name": draft?.name = value
        case "FrameWidth": draft?.frameWidth = Int(value)
        case "FrameHeight": draft?.frameHeight = Int(value)
        case "Duration": draft?.durations.append(Int(value) ?? 0)
        case "CopyOf": draft?.copyOf = value
        case "Anim":
            if let entry = draft?.entry { entries.append(entry) }
            draft = nil
        default: break
        }
        text = ""
    }
}

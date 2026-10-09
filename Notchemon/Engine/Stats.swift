import Foundation
import os

/// Each folded event, at debug level. Read with
/// `log show --debug --predicate 'subsystem == "com.rohithgilla.Notchemon" && category == "stats"'`.
let statsLog = Logger(subsystem: "com.rohithgilla.Notchemon", category: "stats")

/// Something the companion did, emitted once when a phase changes. Stats
/// are a fold over these and nothing samples them per frame. Moves name the
/// root of the party member that made them.
enum CompanionEvent: Sendable, Equatable {
    /// A walk ended or was cut short, `points` along `perch` either way.
    case walked(points: Double, perch: Perch, partner: Int)
    case hopped(partner: Int)
    case napped
    case transferred(to: Perch, partner: Int)
    case focusCompleted(minutes: Int)
    case evolved
    case encounterSeen
    case encounterCaught

    /// The party member that moved, for a move.
    var partner: Int? {
        switch self {
        case .walked(_, _, let partner), .hopped(let partner), .transferred(_, let partner): partner
        case .napped, .focusCompleted, .evolved, .encounterSeen, .encounterCaught: nil
        }
    }
}

/// Converts walked points into the two fun distances, measured where and
/// by whom the walk happened.
struct WalkScale: Sendable, Equatable {
    var creatureMetresPerPoint: Double
    var screenMillimetresPerPoint: Double

    static let none = WalkScale(creatureMetresPerPoint: 0, screenMillimetresPerPoint: 0)
}

struct Stats: Codable, Sendable, Equatable {
    var topEdgePoints: Double = 0
    var dockPoints: Double = 0
    /// Walked distance measured in the walker's own body heights.
    var creatureMetres: Double = 0
    /// How far the sprite really moved across the glass.
    var screenMillimetres: Double = 0
    var hops = 0
    var naps = 0
    var dockVisits = 0
    var focusSessions = 0
    var focusMinutes = 0
    var evolutions = 0
    var firstMet: Date?
    var encountersSeen = 0
    var encountersCaught = 0
}

extension Stats {
    /// Every field falls back to zero, so a stat added later never fails an older file.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topEdgePoints = try container.decodeIfPresent(Double.self, forKey: .topEdgePoints) ?? 0
        dockPoints = try container.decodeIfPresent(Double.self, forKey: .dockPoints) ?? 0
        creatureMetres = try container.decodeIfPresent(Double.self, forKey: .creatureMetres) ?? 0
        screenMillimetres = try container.decodeIfPresent(Double.self, forKey: .screenMillimetres) ?? 0
        hops = try container.decodeIfPresent(Int.self, forKey: .hops) ?? 0
        naps = try container.decodeIfPresent(Int.self, forKey: .naps) ?? 0
        dockVisits = try container.decodeIfPresent(Int.self, forKey: .dockVisits) ?? 0
        focusSessions = try container.decodeIfPresent(Int.self, forKey: .focusSessions) ?? 0
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        evolutions = try container.decodeIfPresent(Int.self, forKey: .evolutions) ?? 0
        firstMet = try container.decodeIfPresent(Date.self, forKey: .firstMet)
        encountersSeen = try container.decodeIfPresent(Int.self, forKey: .encountersSeen) ?? 0
        encountersCaught = try container.decodeIfPresent(Int.self, forKey: .encountersCaught) ?? 0
    }
}

enum StatsReducer {
    static func apply(_ event: CompanionEvent, to stats: Stats, scale: WalkScale = .none) -> Stats {
        var next = stats
        switch event {
        case .walked(let points, let perch, _):
            let walked = max(0, points)
            switch perch {
            case .topEdge: next.topEdgePoints += walked
            case .dock: next.dockPoints += walked
            }
            next.creatureMetres += walked * scale.creatureMetresPerPoint
            next.screenMillimetres += walked * scale.screenMillimetresPerPoint
        case .hopped:
            next.hops += 1
        case .napped:
            next.naps += 1
        case .transferred(let perch, _):
            if perch == .dock { next.dockVisits += 1 }
        case .focusCompleted(let minutes):
            next.focusSessions += 1
            next.focusMinutes += max(0, minutes)
        case .evolved:
            next.evolutions += 1
        case .encounterSeen:
            next.encountersSeen += 1
        case .encounterCaught:
            next.encountersCaught += 1
        }
        return next
    }
}

/// The two fun conversions of a distance walked in points.
enum Distance {
    /// How tall the resting creature is drawn below the notch and on the
    /// Dock: the peek box less the headroom above its head.
    static let drawnHeight: Double = Double(NotchGeometry.peekHeight - SpriteRendering.headroom)
    /// For a species whose real height is unknown.
    static let assumedHeightMetres = 0.5

    /// Metres per point at the creature's own scale: one drawn body height
    /// on screen is one real body height. A 0.4 m creature drawn 40 pt tall
    /// walks 1 cm per point.
    static func creatureMetresPerPoint(heightMetres: Double?, drawnHeight: Double = drawnHeight) -> Double {
        guard drawnHeight > 0 else { return 0 }
        return (heightMetres ?? assumedHeightMetres) / drawnHeight
    }

    /// Millimetres per point on a display `physicalWidth` millimetres wide
    /// that shows `widthInPoints` points across. A screen's frame is in
    /// points, so its width already folds in the backing scale. Zero when
    /// the display reports no physical size.
    static func screenMillimetresPerPoint(physicalWidth: Double, widthInPoints: Double) -> Double {
        guard physicalWidth > 0, widthInPoints > 0 else { return 0 }
        return physicalWidth / widthInPoints
    }
}

/// The lines the Stats submenu shows.
enum StatsSummary {
    static func lines(_ stats: Stats, now: Date) -> [String] {
        var lines: [String] = []
        lines.append("Walked \(metres(stats.creatureMetres)) (creature-scale)")
        lines.append("\(metres(stats.screenMillimetres / 1000)) on screen")
        lines.append("\(count(stats.hops, "hop")) · \(count(stats.naps, "nap"))")
        lines.append(count(stats.dockVisits, "Dock trip"))
        lines.append("\(focus(stats.focusMinutes)) focus in \(count(stats.focusSessions, "session"))")
        if stats.evolutions > 0 {
            lines.append(count(stats.evolutions, "evolution"))
        }
        if let firstMet = stats.firstMet {
            lines.append(together(since: firstMet, now: now))
        }
        return lines
    }

    static func metres(_ metres: Double) -> String {
        if metres >= 1000 {
            let kilometres: String = String(format: "%.1f", metres / 1000)
            return (kilometres.hasSuffix(".0") ? String(kilometres.dropLast(2)) : kilometres) + " km"
        }
        if metres >= 1 || metres <= 0 { return "\(Int(metres)) m" }
        return "\(Int(metres * 100)) cm"
    }

    static func focus(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours < 10 && minutes % 60 != 0 ? String(format: "%.1f h", hours) : "\(minutes / 60) h"
    }

    static func together(since firstMet: Date, now: Date) -> String {
        let days = Int(now.timeIntervalSince(firstMet) / 86_400)
        return days < 1 ? "Together since today" : "Together \(count(days, "day"))"
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}

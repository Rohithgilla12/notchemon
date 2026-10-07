import Foundation

/// The animations Notchemon plays. Each maps onto PMD anim names in order of
/// preference, because many species ship only a subset of the full anim set.
enum PMDAnimation: String, Sendable, CaseIterable {
    case idle, sleep, hop, pose, wake

    init(_ state: SpriteState) {
        switch state {
        case .idle: self = .idle
        case .sleeping: self = .sleep
        case .celebrating: self = .pose
        case .hop: self = .hop
        case .wake: self = .wake
        }
    }

    var fallbackNames: [String] {
        switch self {
        case .idle: ["Idle", "Walk"]
        case .sleep: ["Sleep", "EventSleep", "Laying", "Idle", "Walk"]
        case .hop: ["Hop", "Idle", "Walk"]
        case .pose: ["Pose", "Charge", "Nod", "Idle", "Walk"]
        case .wake: ["Wake", "LookUp", "Idle", "Walk"]
        }
    }
}

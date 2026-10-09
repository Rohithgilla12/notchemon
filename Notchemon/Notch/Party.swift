import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Where a follower looks and how often it has hopped at the cursor. The
/// leader's come from the engine; a follower's are worked out from its own spot.
struct FollowerLook: Sendable, Equatable {
    /// Toward a cursor within the watch radius, or nil.
    var facing: Facing?
    /// Counts hops at an approaching cursor, so each plays once.
    var hops = 0
}

/// One roamer per party member, keyed by root, each deciding against where
/// the others stand. The leader's is the one the panel and the homing
/// triggers act on.
@MainActor
@Observable
final class Party {
    private(set) var leader: Int?
    /// In party order: the followers that can be drawn.
    private(set) var followers: [Int] = []
    private(set) var roamers: [Int: Roamer] = [:]
    private(set) var looks: [Int: FollowerLook] = [:]
    /// Called with the roamer whose creature should look at the cursor again.
    @ObservationIgnored var onLookAgain: ((Roamer) -> Void)?
    @ObservationIgnored var onEvent: ((CompanionEvent) -> Void)?
    @ObservationIgnored private var proximity: [Int: CursorProximity] = [:]
    @ObservationIgnored private var lastHop: [Int: Date] = [:]

    var members: [Int] {
        (leader.map { [$0] } ?? []) + followers
    }

    var leaderRoamer: Roamer? {
        leader.flatMap { roamers[$0] }
    }

    /// Every member's roamer, the leader's first.
    var all: [Roamer] {
        members.compactMap { roamers[$0] }
    }

    /// A member that stays keeps its roamer, and with it where it stands,
    /// whatever its role becomes.
    func sync(leader: Int?, followers: [Int]) {
        guard leader != self.leader || followers != self.followers else { return }
        let members: [Int] = (leader.map { [$0] } ?? []) + followers
        for (root, roamer) in roamers where !members.contains(root) {
            roamer.stop()
            roamers[root] = nil
            looks[root] = nil
            proximity[root] = nil
            lastHop[root] = nil
        }
        for root in members {
            let roamer = roamers[root] ?? makeRoamer(root)
            roamer.follower = root != leader
            roamers[root] = roamer
        }
        self.leader = leader
        self.followers = followers
    }

    func occupied(for root: Int) -> [Perch: [ClosedRange<Double>]] {
        let others: [RoamPhase] = members.filter { $0 != root }.compactMap { roamers[$0]?.phase }
        return RoamRules.occupied(by: others, at: Date(), follower: root != leader)
    }

    /// Each follower faces the cursor from its own spot and hops when the
    /// cursor first comes near it. `centre` places a spot on screen. A
    /// follower out of sight at home sees nothing.
    func cursorMoved(to point: CGPoint, hopsEnabled: Bool, centre: (RoamSpot) -> CGPoint?) {
        let now = Date()
        for root in followers {
            guard let roamer = roamers[root] else { continue }
            let spot = roamer.phase.spot(at: now)
            let seen: CGPoint? = spot == .home ? nil : centre(spot)
            var look = looks[root] ?? FollowerLook()
            var near = false
            if let seen {
                let offset = CursorOffset(dx: point.x - seen.x, dy: point.y - seen.y)
                near = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot() <= BehaviourRules.watchRadius
                look.facing = near ? BehaviourRules.facing(toward: offset) : nil
            } else {
                look.facing = nil
            }
            let current = CursorProximity(near: near, panelExpanded: false)
            let sinceHop: TimeInterval = now.timeIntervalSince(lastHop[root] ?? .distantPast)
            if HopCue.hops(from: proximity[root], to: current, secondsSinceLastHop: sinceHop, enabled: hopsEnabled) {
                lastHop[root] = now
                look.hops += 1
                onEvent?(.hopped(partner: root))
            }
            proximity[root] = current
            if looks[root] != look { looks[root] = look }
        }
    }

    private func makeRoamer(_ root: Int) -> Roamer {
        let roamer = Roamer(partner: root)
        roamer.occupied = { [weak self] in self?.occupied(for: root) ?? [:] }
        roamer.onLookAgain = { [weak self, weak roamer] in
            guard let self, let roamer else { return }
            onLookAgain?(roamer)
        }
        roamer.onEvent = { [weak self] event in self?.onEvent?(event) }
        return roamer
    }
}

/// A follower's sprite on one perch's window, drawn only while it is there.
/// Its own view, so a follower moving redraws only itself.
struct FollowerSprite: View {
    let follower: Follower
    let party: Party
    let snapshot: CompanionSnapshot
    let perch: Perch
    var ground: GroundStep?

    var body: some View {
        if let roamer = party.roamers[follower.root],
           let pose = SpritePose(
               follower: follower.sprites, look: party.looks[follower.root] ?? FollowerLook(), snapshot,
               roam: roamer.phase, on: perch, ground: ground
           ) {
            SpriteView(pose: pose)
        }
    }
}

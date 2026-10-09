import Foundation

/// One creature in the collection, with progress of its own.
struct Partner: Codable, Sendable, Equatable, Identifiable {
    /// The first stage of its family, which keys it while it evolves.
    var root: Int
    /// Its current stage, level, and XP.
    var progress: Progress
    /// How far it has walked at its own scale.
    var creatureMetres: Double = 0

    var id: Int { root }
}

extension Partner {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progress = try container.decode(Progress.self, forKey: .progress)
        root = try container.decodeIfPresent(Int.self, forKey: .root) ?? progress.speciesId
        creatureMetres = try container.decodeIfPresent(Double.self, forKey: .creatureMetres) ?? 0
    }
}

/// Every partner the user has, in the order they joined, which one is out,
/// and which walk along with it. Named apart from Swift's `Collection`
/// protocol, which a type of that name would shadow throughout the module.
struct PartnerCollection: Codable, Sendable, Equatable {
    static let maxFollowers = 2

    private(set) var partners: [Partner] = []
    /// The root of the partner that is out, or nil while there is none. It
    /// leads the party: it always walks, and it is the one the panel shows.
    private(set) var active: Int?
    /// The roots of the partners walking with the leader, in the order they joined it.
    private(set) var followers: [Int] = []

    /// The single partner a state file from before collections had.
    init(only progress: Progress) {
        partners = [Partner(root: progress.speciesId, progress: progress)]
        active = progress.speciesId
    }

    init() {}

    var activePartner: Partner? {
        partners.first { $0.root == active }
    }

    func partner(_ root: Int) -> Partner? {
        partners.first { $0.root == root }
    }

    func owns(_ root: Int) -> Bool {
        partner(root) != nil
    }

    /// Adds `partner` unless its family is already here. Returns whether it joined.
    @discardableResult
    mutating func add(_ partner: Partner) -> Bool {
        guard !owns(partner.root) else { return false }
        partners.append(partner)
        return true
    }

    /// The leader, then its followers.
    var party: [Int] {
        (active.map { [$0] } ?? []) + followers
    }

    /// Sends out the partner keyed `root`, if there is one. A follower sent
    /// out swaps places with the leader, so the same partners keep walking.
    mutating func activate(_ root: Int) {
        guard owns(root), root != active else { return }
        if let slot = followers.firstIndex(of: root) {
            if let active {
                followers[slot] = active
            } else {
                followers.remove(at: slot)
            }
        }
        active = root
    }

    /// Starts or stops partner `root` walking with the leader. The leader
    /// always walks, so it cannot be changed here.
    mutating func setWalking(_ root: Int, _ walking: Bool) -> WalkingChange {
        guard owns(root), root != active else { return .unchanged }
        guard walking else {
            guard let slot = followers.firstIndex(of: root) else { return .unchanged }
            followers.remove(at: slot)
            return .changed
        }
        guard !followers.contains(root) else { return .unchanged }
        guard followers.count < Self.maxFollowers else { return .partyFull }
        followers.append(root)
        return .changed
    }

    mutating func updateActive(_ change: (inout Partner) -> Void) {
        guard let index = partners.firstIndex(where: { $0.root == active }) else { return }
        change(&partners[index])
    }

    /// Moves a partner to the root its provider reports, for partners that
    /// joined before roots were known. Where that family already has a
    /// partner, the one further along stays.
    mutating func rekey(_ root: Int, to newRoot: Int) {
        guard root != newRoot, let index = partners.firstIndex(where: { $0.root == root }) else { return }
        var moved = partners[index]
        moved.root = newRoot
        partners.remove(at: index)
        if let existing = partners.firstIndex(where: { $0.root == newRoot }) {
            if moved.progress.level > partners[existing].progress.level { partners[existing] = moved }
        } else {
            partners.insert(moved, at: index)
        }
        if active == root { active = newRoot }
        followers = Self.cleaned(followers.map { $0 == root ? newRoot : $0 }, partners: partners, active: active)
    }

    /// Followers that are owned, are not the leader, and appear once, at most `maxFollowers` of them.
    private static func cleaned(_ roots: [Int], partners: [Partner], active: Int?) -> [Int] {
        var kept: [Int] = []
        for root in roots where root != active && !kept.contains(root) && partners.contains(where: { $0.root == root }) {
            kept.append(root)
        }
        return Array(kept.prefix(maxFollowers))
    }
}

enum WalkingChange: Sendable, Equatable {
    case changed
    case unchanged
    /// Refused: the leader already has `PartnerCollection.maxFollowers` followers.
    case partyFull
}

extension PartnerCollection {
    /// A partner that cannot be read is dropped rather than failing the
    /// whole file, an active root that names no partner falls back to the
    /// first, and a file from before parties has no followers.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([Lenient<Partner>].self, forKey: .partners) ?? []
        var partners: [Partner] = []
        for entry in entries {
            guard let partner = entry.value, !partners.contains(where: { $0.root == partner.root }) else { continue }
            partners.append(partner)
        }
        self.partners = partners
        let active = try container.decodeIfPresent(Int.self, forKey: .active)
        self.active = partners.contains { $0.root == active } ? active : partners.first?.root
        let followers: [Int]? = try? container.decodeIfPresent([Int].self, forKey: .followers)
        self.followers = Self.cleaned(followers ?? [], partners: partners, active: self.active)
    }
}

/// Decodes a value or nothing, so one bad element leaves its siblings alone.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

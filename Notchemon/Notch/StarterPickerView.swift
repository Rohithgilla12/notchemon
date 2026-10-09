import SwiftUI

struct StarterPickerView: View {
    let model: CompanionModel
    let carryOver: Progress?

    var body: some View {
        VStack(spacing: 8) {
            Text(carryOver == nil ? "Choose your companion" : "Choose a new companion. Your level carries over.")
                .font(.system(size: 12, weight: .semibold))
            if model.starterOptions.isEmpty {
                if model.isLoadingStarters {
                    ProgressView().controlSize(.small).frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 6) {
                        Text("Couldn't load the starters.").font(.system(size: 11))
                        Button("Try again") { Task { await model.loadStarters() } }
                    }
                    .frame(maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(model.starterOptions) { option in
                        PartnerCard(option: option, caption: nil, highlighted: false) { model.choose(option) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The collection in one row: partners first, the one that is out
/// highlighted, then species that could join at the starting level. Each
/// partner can walk along with the one that is out. With the unlock
/// override on, a search reaches every species.
struct PartnersView: View {
    static let partyFullHint = "Two partners can walk with the leader. Stop one first."

    let model: CompanionModel
    @State private var query: String
    @State private var hint: String?

    init(model: CompanionModel, query: String = "", hint: String? = nil) {
        self.model = model
        _query = State(initialValue: query)
        _hint = State(initialValue: hint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Partners").font(.system(size: 12, weight: .semibold))
                if model.snapshot.unlocks.override {
                    TextField("Any species by name or number", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Spacer()
                }
                Button("Done") { model.showsPartners = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            let shown = query.isEmpty ? model.partnerOptions : model.searchResults
            if shown.isEmpty {
                Group {
                    if query.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("No species matches.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shown) { option in
                            VStack(spacing: 4) {
                                PartnerCard(option: option, caption: caption(option), highlighted: isOut(option)) { model.choose(option) }
                                    .help(help(option))
                                // A closure, not the method: CI's Swift 6.2 crashes emitting a main-actor method reference's thunk.
                                WalkingToggle(model: model, option: option) { showPartyFull() }
                            }
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            } else if let next = model.snapshot.unlocks.next {
                Text(Self.nextLine(next, stats: model.snapshot.stats))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .task(id: query) {
            // Waits out a burst of typing before asking the provider.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
    }

    static func nextLine(_ next: UnlockThreshold, stats: Stats) -> String {
        let walked = StatsSummary.metres(stats.creatureMetres)
        let goal = StatsSummary.metres(next.creatureKilometres * 1000)
        return "More partners at \(next.focusMinutes) focus min or \(goal) walked. So far \(stats.focusMinutes) min, \(walked)."
    }

    private func showPartyFull() {
        hint = Self.partyFullHint
        Task {
            try? await Task.sleep(for: .seconds(3))
            if hint == Self.partyFullHint { hint = nil }
        }
    }

    private func isOut(_ option: PartnerOption) -> Bool {
        option.partner != nil && option.species.id == model.activeSpecies?.id
    }

    private func caption(_ option: PartnerOption) -> String {
        guard let partner = option.partner else { return "New · Lv \(XPRules.startingLevel)" }
        // A search can find another stage of a family already here.
        return partner.progress.speciesId == option.species.id ? "Lv \(partner.progress.level)" : "Family at Lv \(partner.progress.level)"
    }

    private func help(_ option: PartnerOption) -> String {
        guard let partner = option.partner else { return "Add to your collection at level \(XPRules.startingLevel)" }
        return "Walked \(StatsSummary.metres(partner.creatureMetres)) at its own scale"
    }
}

/// Under a partner's own card, not another stage of its family a search
/// found. The one that is out always walks.
private struct WalkingToggle: View {
    let model: CompanionModel
    let option: PartnerOption
    /// Called when the party is already full.
    let refused: () -> Void

    var body: some View {
        if let partner = option.partner, partner.progress.speciesId == option.species.id {
            if partner.root == model.snapshot.leader {
                Label("Leading", systemImage: "figure.walk")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.green.opacity(0.9))
                    .frame(height: 14)
                    .help("The partner that is out always walks.")
            } else {
                Toggle("Walking", isOn: walking(partner.root))
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    .font(.system(size: 9, weight: .medium))
                    .frame(height: 14)
                    .help("Walk along the top edge and the Dock with the partner that is out.")
            }
        }
    }

    private func walking(_ root: Int) -> Binding<Bool> {
        Binding(
            get: { model.snapshot.followerRoots.contains(root) },
            set: { (walking: Bool) in
                Task {
                    if await model.setWalking(root, walking) == .partyFull { refused() }
                }
            }
        )
    }
}

struct PartnerCard: View {
    let option: PartnerOption
    let caption: String?
    let highlighted: Bool
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 2) {
                Group {
                    if let portrait = option.portrait {
                        Image(decorative: portrait, scale: 1).resizable().interpolation(.high).scaledToFit()
                    } else {
                        Image(systemName: "questionmark").font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 60, height: caption == nil ? 60 : 52)
                Text(option.species.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 84, height: 88)
            .background(.white.opacity(hovering ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.8), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

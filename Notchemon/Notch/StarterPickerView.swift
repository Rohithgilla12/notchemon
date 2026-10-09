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
/// highlighted, then species that could join at the starting level.
struct PartnersView: View {
    let model: CompanionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Partners").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Done") { model.showsPartners = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if model.partnerOptions.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.partnerOptions) { option in
                            PartnerCard(option: option, caption: caption(option), highlighted: isOut(option)) { model.choose(option) }
                                .help(help(option))
                        }
                    }
                }
            }
        }
    }

    private func isOut(_ option: PartnerOption) -> Bool {
        option.partner != nil && option.species.id == model.activeSpecies?.id
    }

    private func caption(_ option: PartnerOption) -> String {
        guard let partner = option.partner else { return "New · Lv \(XPRules.startingLevel)" }
        return "Lv \(partner.progress.level)"
    }

    private func help(_ option: PartnerOption) -> String {
        guard let partner = option.partner else { return "Add to your collection at level \(XPRules.startingLevel)" }
        return "Walked \(StatsSummary.metres(partner.creatureMetres)) at its own scale"
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

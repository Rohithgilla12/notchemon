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
                        StarterButton(option: option) { model.choose(option) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StarterButton: View {
    let option: StarterOption
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 2) {
                SpriteView(pose: SpritePose(frames: option.frames, fidgets: false))
                    .frame(width: 60, height: 60)
                Text(option.species.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 84, height: 88)
            .background(.white.opacity(hovering ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

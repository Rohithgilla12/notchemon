import SwiftUI

struct ExpandedView: View {
    @Bindable var model: CompanionModel
    let presentation: NotchPresentation
    let metrics: PanelMetrics

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notchSize.height)
            content
                .padding(.horizontal, PanelMetrics.expandedInset)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            if let banner = model.snapshot.banner {
                BannerView(banner: banner)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.snapshot.banner)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.snapshot.phase {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let message):
            VStack(spacing: 8) {
                Text(message).font(.callout).multilineTextAlignment(.center)
                Button("Retry now") { model.retry() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .choosingStarter(let carryOver):
            StarterPickerView(model: model, carryOver: carryOver)
        case .active(let species, let progress):
            HStack(alignment: .top, spacing: 14) {
                CompanionColumn(species: species, progress: progress)
                    .frame(width: PanelMetrics.expandedSpriteSide + 16)
                ToolsColumn(model: model, presentation: presentation)
            }
        }
    }
}

private struct CompanionColumn: View {
    let species: Species
    let progress: Progress

    var body: some View {
        VStack(spacing: 3) {
            Color.clear.frame(height: PanelMetrics.expandedSpriteSide + 6)
            Text(species.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            HStack(spacing: 4) {
                Text("Lv \(progress.level)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                ProgressView(value: Double(progress.xp), total: Double(XPRules.xpToNextLevel(from: progress.level)))
                    .progressViewStyle(.linear)
                    .tint(.green)
            }
        }
    }
}

private struct ToolsColumn: View {
    @Bindable var model: CompanionModel
    let presentation: NotchPresentation
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FocusButton(model: model)
            TextField("Quick note, Enter to save", text: $model.noteDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                .focused($noteFocused)
                .onSubmit { model.submitNote() }
            StashRow(model: model)
        }
        .task(id: presentation.noteFocusRequested) {
            guard presentation.noteFocusRequested else { return }
            // The field must be in a key window before it can take focus.
            try? await Task.sleep(for: .milliseconds(60))
            noteFocused = true
            presentation.noteFocusRequested = false
        }
    }
}

private struct FocusButton: View {
    let model: CompanionModel

    var body: some View {
        Button(action: model.toggleFocus) {
            HStack(spacing: 6) {
                Image(systemName: model.snapshot.focus == nil ? "timer" : "stop.fill")
                if let session = model.snapshot.focus {
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        Text("Stop focus · \(Self.clock(session.endsAt.timeIntervalSince(context.date)))").monospacedDigit()
                    }
                } else {
                    Text("Start focus · \(model.snapshot.preferences.focusMinutes) min")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((model.snapshot.focus == nil ? Color.white.opacity(0.12) : Color.green.opacity(0.3)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct StashRow: View {
    let model: CompanionModel

    var body: some View {
        HStack(spacing: 6) {
            if model.snapshot.stash.isEmpty {
                Label("Drop files on the notch to stash them", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(model.snapshot.stash) { item in
                    StashItemView(url: item.url) { model.removeFromStash($0) }
                        .frame(width: 30, height: 30)
                        .help(item.name)
                }
                Spacer(minLength: 0)
                Text("\(model.snapshot.stash.count)/\(CompanionState.stashCapacity)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: 30)
    }
}

private struct BannerView: View {
    let banner: Banner

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.9), in: Capsule())
    }

    private var text: String {
        switch banner {
        case .levelUp(let level): "Level up! Now level \(level)"
        case .evolved(let name): "Evolved into \(name)!"
        case .stashFull: "Stash is full (\(CompanionState.stashCapacity) items)"
        }
    }

    private var color: Color {
        switch banner {
        case .levelUp: .green
        case .evolved: .purple
        case .stashFull: .orange
        }
    }
}

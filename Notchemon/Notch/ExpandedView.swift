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
                .padding(.vertical, PanelMetrics.expandedVerticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay {
            if case .evolved(_, let portrait?) = model.snapshot.banner {
                EvolutionReveal(portrait: portrait, topInset: metrics.notchSize.height)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let banner = model.snapshot.banner {
                BannerView(banner: banner) { model.undoClearStash(animated: true) }
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if model.newPartnersWaiting, !model.showsPartners {
                NewPartnersBanner(model: model)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.snapshot.banner)
        .onDisappear { model.showsPartners = false }
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
            if model.showsPartners {
                PartnersView(model: model)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    CompanionColumn(species: species, progress: progress)
                        .frame(width: PanelMetrics.expandedSpriteSize.width)
                    ToolsColumn(model: model, presentation: presentation)
                }
            }
        }
    }
}

private struct CompanionColumn: View {
    let species: Species
    let progress: Progress

    var body: some View {
        VStack(spacing: 3) {
            Color.clear.frame(height: PanelMetrics.expandedSpriteSize.height + 2)
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
                .overlay(alignment: .trailing) {
                    Button {
                        FloatingNotes.shared.show(seed: model.noteDraft)
                        model.noteDraft = ""
                    } label: {
                        Image(systemName: "macwindow.on.rectangle").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .help("Open in Floating Notes")
                }
            StashRow(model: model)
            SystemStatsView()
            if let credits = SpriteCredits(model.snapshot.drawnCreatures) {
                SpriteCreditLine(credits: credits)
            }
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
                        .frame(width: StashItemNSView.side, height: StashItemNSView.side)
                        .padding(.top, -StashItemNSView.badgeOverhang)
                        .padding(.trailing, -StashItemNSView.badgeOverhang)
                        .transition(.opacity)
                }
                HStack(spacing: 4) {
                    Button("Clear Stash") { model.clearStash(animated: true) }
                        .buttonStyle(.plain)
                        .help("Empty the stash. The files stay where they are.")
                    Text("\(model.snapshot.stash.count)/\(CompanionState.stashCapacity)")
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 30)
    }
}

/// Licences like CC BY-NC require attribution wherever a sprite is shown, so
/// the line credits every creature drawn, not only the leader.
private struct SpriteCreditLine: View {
    let credits: SpriteCredits

    var body: some View {
        Button {
            for source in credits.sources {
                NSWorkspace.shared.open(source.url)
            }
        } label: {
            HStack(spacing: 0) {
                ForEach(Array(credits.sources.enumerated()), id: \.offset) { (index: Int, source: SpriteCredits.Source) in
                    if index > 0 {
                        Text("; ").fixedSize()
                    }
                    if let byline = source.byline {
                        Text(byline).lineLimit(1).truncationMode(.tail)
                        Text(" · \(source.terms)").fixedSize()
                    } else {
                        Text(source.line).fixedSize()
                    }
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.4))
        }
        .buttonStyle(.plain)
        .help(credits.fullList)
    }
}

private struct EvolutionReveal: View {
    let portrait: CGImage
    let topInset: CGFloat

    var body: some View {
        Image(decorative: portrait, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 96, height: 96)
            .shadow(color: .purple.opacity(0.9), radius: 18)
            .padding(10)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
            .padding(.top, topInset)
            .padding(.bottom, 24)
            .allowsHitTesting(false)
    }
}

/// Shown once in the open panel after a tier opens; a click opens the picker.
private struct NewPartnersBanner: View {
    let model: CompanionModel

    var body: some View {
        Button(action: model.showPartners) {
            Text("New partners available")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.teal.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
        .task {
            try? await Task.sleep(for: CreatureEngine.bannerLength + .seconds(2))
            guard !Task.isCancelled else { return }
            model.newPartnersWaiting = false
        }
    }
}

private struct BannerView: View {
    let banner: Banner
    let onUndo: () -> Void

    var body: some View {
        if case .stashCleared = banner {
            Button(action: onUndo) { capsule }
                .buttonStyle(.plain)
        } else {
            capsule
        }
    }

    private var capsule: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.9), in: Capsule())
    }

    private var text: String {
        switch banner {
        case .levelUp(let level): "Level up! Now level \(level)"
        case .evolved(let name, _): "Evolved into \(name)!"
        case .stashFull: "Stash is full (\(CompanionState.stashCapacity) items)"
        case .stashCleared: "Stash cleared · Undo"
        case .caught(let name): "Caught! \(name) joined your collection"
        case .seenAgain(let name): "\(name) is already a partner"
        }
    }

    private var color: Color {
        switch banner {
        case .levelUp: .green
        case .evolved: .purple
        case .stashFull: .orange
        case .stashCleared: .gray
        case .caught: .teal
        case .seenAgain: .gray
        }
    }
}

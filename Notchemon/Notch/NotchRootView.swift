import SwiftUI

struct NotchRootView: View {
    let presentation: NotchPresentation
    let model: CompanionModel
    let roamer: Roamer

    var body: some View {
        if let metrics = presentation.metrics {
            let expanded = presentation.isExpanded
            let shapeSize = expanded ? metrics.panelSize : metrics.notchSize
            let radius: CGFloat = expanded ? 22 : 9
            let sprite = metrics.spriteFrame(expanded: expanded)

            ZStack(alignment: .topLeading) {
                NotchShape(bottomRadius: radius)
                    .fill(.black)
                    .overlay {
                        if presentation.isDropTargeted {
                            NotchShape(bottomRadius: radius, closed: false)
                                .stroke(.white.opacity(0.7), lineWidth: 1.5)
                        }
                    }
                    .frame(width: shapeSize.width, height: shapeSize.height)
                    .frame(maxWidth: .infinity, alignment: .top)

                if expanded {
                    ExpandedView(model: model, presentation: presentation, metrics: metrics)
                        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .topLeading)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }

                if model.activeSpecies != nil {
                    SpriteView(pose: SpritePose(model.snapshot, roam: roamer.phase, expanded: expanded, at: Date()))
                        .frame(width: sprite.width, height: sprite.height)
                        .offset(x: sprite.minX, y: sprite.minY)
                }

                NotchShape(bottomRadius: 9)
                    .fill(.black)
                    .frame(width: metrics.notchSize.width, height: metrics.notchSize.height)
                    .frame(maxWidth: .infinity, alignment: .top)

                if let focus = model.snapshot.focus {
                    FocusRing(session: focus, radius: radius)
                        .frame(width: shapeSize.width + 4, height: shapeSize.height + 2)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(width: metrics.panelSize.width, height: metrics.panelSize.height, alignment: .topLeading)
            .modifier(ShakeEffect(shakes: CGFloat(presentation.shakeToken)))
            .animation(.linear(duration: 0.45), value: presentation.shakeToken)
            .dropDestination(for: URL.self) { urls, _ in
                accept(urls)
            } isTargeted: { targeted in
                presentation.isDropTargeted = targeted
            }
            .frame(width: metrics.windowSize.width, height: metrics.windowSize.height, alignment: .top)
        }
    }

    private func accept(_ urls: [URL]) -> Bool {
        let held = Set(model.snapshot.stash.map(\.url.standardizedFileURL))
        let fresh = urls.filter { $0.isFileURL && !held.contains($0.standardizedFileURL) }
        guard !fresh.isEmpty else { return false }
        if model.snapshot.stash.count >= CompanionState.stashCapacity {
            presentation.shakeToken += 1
            return false
        }
        Task {
            if await !model.addToStash(fresh) { presentation.shakeToken += 1 }
        }
        return true
    }
}

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 6), y: 0))
    }
}

struct FocusRing: View {
    let session: FocusSession
    let radius: CGFloat

    var body: some View {
        // One redraw a second, and only while a session runs.
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            NotchShape(bottomRadius: radius + 2, closed: false)
                .trim(from: 0, to: session.remainingFraction(at: context.date))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

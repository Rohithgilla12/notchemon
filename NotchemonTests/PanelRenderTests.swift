import AppKit
import SwiftUI
import Testing
@testable import Notchemon

/// Renders panel views offscreen with the original creatures, when
/// `NOTCHEMON_PANEL_RENDER_DIR` names a folder for the output. Pass it to
/// xcodebuild as `TEST_RUNNER_NOTCHEMON_PANEL_RENDER_DIR=<dir>`.
let panelRenderFolder = ProcessInfo.processInfo.environment["NOTCHEMON_PANEL_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }

@MainActor
@Suite(.enabled(if: panelRenderFolder != nil))
struct PanelRenderTests {
    let directory = Fixtures.temporaryDirectory()

    /// A collection of two partners, the second out, with the other starters to add.
    func model(unlockAll: Bool = false, evolve: Bool = true) async throws -> CompanionModel {
        let engine = CreatureEngine(
            provider: OriginalCreatureProvider(),
            store: StateStore(url: directory.appendingPathComponent("state.json")),
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 },
            unlockAll: { unlockAll }
        )
        await engine.start()
        await engine.adopt(101)
        if evolve { await engine.award(5_000) }
        await engine.adopt(104)
        let model = CompanionModel(engine: engine)
        Task { await model.run() }
        for _ in 0..<200 where model.activeSpecies == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.loadPartners()
        return model
    }

    @Test func rendersThePartnerPicker() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await model()
        try render(PartnersView(model: model), to: folder.appendingPathComponent("partners.png"))
    }

    @Test func rendersTheDeveloperSearch() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await model(unlockAll: true)
        await model.search("o")
        try render(PartnersView(model: model, query: "o"), to: folder.appendingPathComponent("partners-search.png"))
        try render(PartnersView(model: model), to: folder.appendingPathComponent("partners-unlocked.png"))
    }

    @Test func rendersAVisitorOnTheStripAndTheCatchBanner() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await model(evolve: false)
        model.spawnEncounterNow()
        for _ in 0..<200 where model.snapshot.encounter == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let encounter = try #require(model.snapshot.encounter)
        let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656)
        let presentation = NotchPresentation()
        let layout = try #require(NotchGeometry.layout(for: screen, virtualNotchEnabled: true, wander: .topEdge))
        presentation.layout = layout
        let metrics = try #require(presentation.metrics)
        let wild = WildWalker()
        var rng = SplitMix64(seed: 2)
        wild.begin(WildVisit.plan(on: .topEdge, in: 120...400, start: Date() - 1, using: &rng), serial: encounter.serial)
        let strip = NotchRootView(presentation: presentation, model: model, party: Party(), wild: wild)
        try render(strip, size: metrics.windowSize, padding: 0, to: folder.appendingPathComponent("visitor-strip.png"))
        model.catchEncounter()
        for _ in 0..<200 where model.snapshot.banner == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let panel = ExpandedView(model: model, presentation: NotchPresentation(), metrics: metrics)
            .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
        try render(panel, size: metrics.panelSize, padding: 0, to: folder.appendingPathComponent("caught-banner.png"))
    }

    @Test func rendersTheNewPartnersBanner() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await model(evolve: false)
        model.newPartnersWaiting = true
        let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656)
        let layout = try #require(NotchGeometry.layout(for: screen, virtualNotchEnabled: true, wander: .off))
        let metrics = PanelMetrics(layout: layout)
        let panel = ExpandedView(model: model, presentation: NotchPresentation(), metrics: metrics)
            .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
        try render(panel, size: metrics.panelSize, padding: 0, to: folder.appendingPathComponent("new-partners-banner.png"))
    }

    func render(_ view: some View, size: CGSize = CGSize(width: 408, height: 156), padding: CGFloat = 16, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let outer = CGSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
        let framed = view
            .padding(padding)
            .frame(width: outer.width, height: outer.height, alignment: .topLeading)
            .background(.black)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = CGRect(origin: .zero, size: outer)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

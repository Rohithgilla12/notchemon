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

    /// Four partners: 110 leads, 101 and 104 walk with it, 107 stays in.
    func partyModel() async throws -> CompanionModel {
        let engine = CreatureEngine(
            provider: OriginalCreatureProvider(),
            store: StateStore(url: directory.appendingPathComponent("state.json")),
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 }
        )
        await engine.start()
        for id in [101, 104, 107, 110] { await engine.adopt(id) }
        _ = await engine.setWalking(101, true)
        _ = await engine.setWalking(104, true)
        let model = CompanionModel(engine: engine)
        Task { await model.run() }
        for _ in 0..<200 where model.snapshot.followers.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.loadPartners()
        return model
    }

    @Test func rendersThePartnersWithWalkingToggles() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await partyModel()
        try render(PartnersView(model: model), to: folder.appendingPathComponent("partners-walking.png"))
        try render(
            PartnersView(model: model, hint: PartnersView.partyFullHint),
            to: folder.appendingPathComponent("partners-party-full.png")
        )
    }

    @Test func rendersAPartyOfThreeOnTheTopEdge() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await partyModel()
        let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656)
        let presentation = NotchPresentation()
        let layout = try #require(NotchGeometry.layout(for: screen, virtualNotchEnabled: true, wander: .topEdge))
        presentation.layout = layout
        let metrics = try #require(presentation.metrics)
        let party = Party()
        party.sync(leader: model.snapshot.leader, followers: model.snapshot.followers.map(\.root))
        let reach = Double(layout.roamReach)
        for roamer in party.all {
            let homing: Homing = roamer.partner == party.leader ? .snap : .free
            roamer.update(range: -reach...reach, dock: nil, homing: homing)
        }
        #expect(party.all.count == 3)
        let strip = NotchRootView(presentation: presentation, model: model, party: party, wild: WildWalker())
        try render(strip, size: metrics.windowSize, padding: 0, to: folder.appendingPathComponent("party-top-edge.png"))
    }

    /// 110 leads; with `walkers`, 101 and 104 walk with it.
    func creditedModel(walkers: Bool) async throws -> CompanionModel {
        let engine = CreatureEngine(
            provider: CreditedProvider(),
            store: StateStore(url: directory.appendingPathComponent("state.json")),
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 }
        )
        await engine.start()
        for id in [101, 104, 110] { await engine.adopt(id) }
        if walkers {
            _ = await engine.setWalking(101, true)
            _ = await engine.setWalking(104, true)
        }
        let model = CompanionModel(engine: engine)
        Task { await model.run() }
        let followers = walkers ? 2 : 0
        for _ in 0..<200 where model.snapshot.followers.count < followers || model.snapshot.sprite == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        return model
    }

    func renderPanel(_ model: CompanionModel, to name: String, folder: URL) throws {
        let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656)
        let layout = try #require(NotchGeometry.layout(for: screen, virtualNotchEnabled: true, wander: .topEdge))
        let metrics = PanelMetrics(layout: layout)
        let panel = ExpandedView(model: model, presentation: NotchPresentation(), metrics: metrics)
            .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
        try render(panel, size: metrics.panelSize, padding: 0, to: folder.appendingPathComponent(name))
        let credits = try #require(SpriteCredits(model.snapshot.drawnCreatures))
        let text = credits.line + "\n\n" + credits.fullList + "\n"
        try text.write(to: folder.appendingPathComponent(name).deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }

    @Test func rendersTheCreditsOfAPartyOfThree() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await creditedModel(walkers: true)
        #expect(SpriteCredits(model.snapshot.drawnCreatures)?.creatures.count == 3)
        try renderPanel(model, to: "credits-party.png", folder: folder)
    }

    @Test func rendersTheCreditsDuringAVisit() async throws {
        let folder = try #require(panelRenderFolder)
        let model = try await creditedModel(walkers: false)
        model.spawnEncounterNow()
        for _ in 0..<200 where model.snapshot.encounter == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(SpriteCredits(model.snapshot.drawnCreatures)?.creatures.count == 2)
        try renderPanel(model, to: "credits-visit.png", folder: folder)
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

/// The original creatures with made-up credits, so a render shows the credit line.
private struct CreditedProvider: CreatureProvider {
    let base = OriginalCreatureProvider()
    var starterIDs: [Int] { base.starterIDs }
    var unlockTiers: [[Int]] { base.unlockTiers }

    static func authors(of id: Int) -> [String] {
        switch id {
        case 110: ["Ana Ferreira", "Bo Nakamura"]
        case 101: ["Bo Nakamura", "Cyrus Delacroix-Whitfield"]
        case 104: ["Dee Okonkwo"]
        default: ["Evangeline Hargreaves", "Ana Ferreira"]
        }
    }

    func encounterCandidate(using rng: inout some RandomNumberGenerator) async throws -> Species? {
        try await base.encounterCandidate(using: &rng)
    }

    func species(id: Int) async throws -> Species {
        try await base.species(id: id)
    }

    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        let drawn = try await base.sprite(for: species, state: state, facing: facing)
        let credit = Attribution(
            authors: Self.authors(of: species.id), source: "SpriteCollab", license: "CC BY-NC 4.0", url: URL(string: "https://example.test")!
        )
        return SpriteFrames(
            frames: drawn.frames, durations: drawn.durations, pixelated: drawn.pixelated, directional: drawn.directional,
            loops: drawn.loops, attribution: credit, groundPoints: drawn.groundPoints
        )
    }

    func portrait(for species: Species) async throws -> CGImage {
        try await base.portrait(for: species)
    }
}

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
    func model() async throws -> CompanionModel {
        let engine = CreatureEngine(
            provider: OriginalCreatureProvider(),
            store: StateStore(url: directory.appendingPathComponent("state.json")),
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 }
        )
        await engine.start()
        await engine.adopt(101)
        await engine.award(5_000)
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

    func render(_ view: some View, size: CGSize = CGSize(width: 408, height: 156), to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let framed = view
            .padding(16)
            .frame(width: size.width + 32, height: size.height + 32, alignment: .topLeading)
            .background(.black)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = CGRect(origin: .zero, size: CGSize(width: size.width + 32, height: size.height + 32))
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

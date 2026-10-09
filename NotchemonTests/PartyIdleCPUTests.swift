import AppKit
import Darwin
import SwiftUI
import Testing
@testable import Notchemon

/// How long each run lasts, when `NOTCHEMON_IDLE_CPU_SECONDS` asks for the
/// measurement. Pass it to xcodebuild as `TEST_RUNNER_NOTCHEMON_IDLE_CPU_SECONDS=<seconds>`.
let idleCPUSeconds = ProcessInfo.processInfo.environment["NOTCHEMON_IDLE_CPU_SECONDS"].flatMap(Double.init)

/// Wanders a party of 0, 1, and 3 for real time, drawn by `NotchRootView`
/// in a window that is never shown, and prints the CPU the process spent
/// and how often each roamer woke. A measurement to read, not a check: it
/// fails only when the party does not form.
@MainActor
@Suite(.enabled(if: idleCPUSeconds != nil), .serialized)
struct PartyIdleCPUTests {
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user: Double = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system: Double = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }

    func model(followers: [Int], leads: Bool) async throws -> CompanionModel {
        let directory = Fixtures.temporaryDirectory()
        let engine = CreatureEngine(
            provider: OriginalCreatureProvider(),
            store: StateStore(url: directory.appendingPathComponent("state.json")),
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 },
            sleepAfter: .infinity
        )
        await engine.start()
        if leads {
            for id in [101, 104, 107] { await engine.adopt(id) }
            for root in followers { _ = await engine.setWalking(root, true) }
        }
        let model = CompanionModel(engine: engine)
        Task { await model.run() }
        for _ in 0..<300 where model.snapshot.followers.count < followers.count || (leads && model.activeSpecies == nil) {
            try await Task.sleep(for: .milliseconds(10))
        }
        return model
    }

    @Test(arguments: [(0, "idle host, no creature"), (1, "leader alone"), (3, "leader and two followers")])
    func measure(members: Int, label: String) async throws {
        let seconds = try #require(idleCPUSeconds)
        let followers: [Int] = Array([101, 104].prefix(max(0, members - 1)))
        let model = try await model(followers: followers, leads: members > 0)
        let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656)
        let presentation = NotchPresentation()
        let layout = try #require(NotchGeometry.layout(for: screen, virtualNotchEnabled: true, wander: .topEdge))
        presentation.layout = layout
        let metrics = try #require(presentation.metrics)
        let party = Party()
        party.sync(leader: model.snapshot.leader, followers: model.snapshot.followers.map(\.root))
        #expect(party.all.count == members)
        var wakes: [Int: Int] = [:]
        party.onLookAgain = { roamer in wakes[roamer.partner, default: 0] += 1 }
        let hosting = NSHostingView(rootView: NotchRootView(presentation: presentation, model: model, party: party, wild: WildWalker()))
        hosting.frame = CGRect(origin: .zero, size: metrics.windowSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = hosting
        let reach = Double(layout.roamReach)
        for roamer in party.all {
            roamer.update(range: -reach...reach, dock: -400...400, homing: .free)
        }
        let before = Self.cpuSeconds()
        let start = Date()
        try await Task.sleep(for: .seconds(seconds))
        let spent = Self.cpuSeconds() - before
        let elapsed = Date().timeIntervalSince(start)
        let percent: Double = 100 * spent / elapsed
        let perMinute: [String] = party.all.map { (roamer: Roamer) -> String in
            String(format: "%d: %.1f wakes/min", roamer.partner, Double(wakes[roamer.partner] ?? 0) * 60 / elapsed)
        }
        print(String(format: "IDLE-CPU %@: %.3f s CPU over %.1f s = %.3f%% of one core; ", label, spent, elapsed, percent) + perMinute.joined(separator: ", "))
        withExtendedLifetime(window) {}
    }
}

import AppKit
import SwiftUI

@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        let window = window ?? make()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private static func make() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.title = "About Notchemon"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct AboutView: View {
    /// Matches the disclaimer in README.md; a test keeps the two in step.
    static let disclaimer = "Pokémon is a trademark of Nintendo, The Pokémon Company, and Game Freak; this is an unaffiliated, free, non-commercial fan work."

    private let info = Bundle.main.infoDictionary ?? [:]
    private let licence = Bundle.main.url(forResource: "LICENSE", withExtension: nil)
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    var body: some View {
        VStack(spacing: 14) {
            icon
            VStack(spacing: 4) {
                Text("Notchemon").font(.title2.bold())
                Text("Version \(string("CFBundleShortVersionString")) (\(string("CFBundleVersion")))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(Self.disclaimer)
                .font(.callout)
                .multilineTextAlignment(.center)
            VStack(spacing: 4) {
                Text("Species data and fallback sprites from [PokéAPI](https://pokeapi.co).")
                Text("Sprites from [SpriteCollab](https://github.com/PMDCollab/SpriteCollab), licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).")
                Text("Both are fetched at runtime; the app bundles no creature art.")
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            if let licence {
                DisclosureGroup("MIT Licence") {
                    ScrollView {
                        Text(licence)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                }
                .font(.caption)
            }
            Link("github.com/Rohithgilla12/notchemon", destination: URL(string: "https://github.com/Rohithgilla12/notchemon")!)
                .font(.callout)
        }
        .padding(24)
        .frame(width: 380)
    }

    @ViewBuilder private var icon: some View {
        if info["CFBundleIconName"] != nil || info["CFBundleIconFile"] != nil {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
        }
    }

    private func string(_ key: String) -> String {
        info[key] as? String ?? "?"
    }
}

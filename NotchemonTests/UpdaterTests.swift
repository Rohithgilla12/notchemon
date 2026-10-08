import Foundation
import Security
import Sparkle
import Testing
@testable import Notchemon

@MainActor
struct UpdaterTests {
    @Test func feedIsTheLatestReleaseAsset() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        #expect(feed == "https://github.com/Rohithgilla12/notchemon/releases/latest/download/appcast.xml")
    }

    @Test func onlyANonEmptyPublicKeyCounts() {
        #expect(!AppUpdater.hasPublicKey([:]))
        #expect(!AppUpdater.hasPublicKey(["SUPublicEDKey": ""]))
        #expect(!AppUpdater.hasPublicKey(["SUPublicEDKey": " \n"]))
        #expect(AppUpdater.hasPublicKey(["SUPublicEDKey": "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="]))
    }

    /// Sparkle 2 falls back to Apple code signing alone when a signed app over
    /// HTTPS has no EdDSA key. The app's own settings must stop that fallback.
    @Test func sparkleRefusesASignedAppWithoutAnEdDSAKey() throws {
        var info = sparkleSettings(of: .main)
        info.removeValue(forKey: "SUPublicEDKey")
        let host = try makeSignedBundle(info: info)
        defer { try? FileManager.default.removeItem(at: host.bundleURL.deletingLastPathComponent()) }

        let driver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
        let updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: nil)
        let error = #expect(throws: NSError.self) { try updater.start() }
        #expect(error?.localizedDescription.contains("EdDSA") == true)
    }

    private func sparkleSettings(of bundle: Bundle) -> [String: Any] {
        (bundle.infoDictionary ?? [:]).filter { $0.key.hasPrefix("SU") }
    }

    /// An ad hoc signed bundle with a test-only identifier, so Sparkle never
    /// reads or writes the real app's defaults.
    private func makeSignedBundle(info: [String: Any]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("UpdaterHost.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("UpdaterHost"))
        let plist = info.merging([
            "CFBundleIdentifier": "com.rohithgilla.Notchemon.updater-tests",
            "CFBundleExecutable": "UpdaterHost",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ]) { _, fixed in fixed }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", app.path]
        try codesign.run()
        codesign.waitUntilExit()
        try #require(codesign.terminationStatus == 0)

        // The check Sparkle itself uses to decide that a bundle is signed.
        var code: SecStaticCode?
        var requirement: SecRequirement?
        try #require(SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess)
        try #require(SecCodeCopyDesignatedRequirement(try #require(code), [], &requirement) == errSecSuccess)

        return try #require(Bundle(url: app))
    }
}

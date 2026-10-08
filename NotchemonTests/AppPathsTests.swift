import Foundation
import Testing
@testable import Notchemon

struct AppPathsTests {
    @Test func theReleaseBundleKeepsTheInstalledAppsFolder() {
        #expect(AppPaths.supportFolderName(bundleIdentifier: "com.rohithgilla.Notchemon") == "Notchemon")
    }

    @Test func theDebugBundleGetsItsOwnFolder() {
        #expect(AppPaths.supportFolderName(bundleIdentifier: "com.rohithgilla.Notchemon.debug") == "Notchemon Debug")
    }

    /// The test host is the Debug build, so its state must not be the user's.
    @Test func theTestHostWritesStateUnderNotchemonDebug() throws {
        let host = try #require(Bundle.main.bundleIdentifier)
        #expect(host == "com.rohithgilla.Notchemon.debug")
        #expect(AppPaths.state.pathComponents.suffix(3) == ["Application Support", "Notchemon Debug", "state.json"])
        #expect(AppPaths.cache.pathComponents.suffix(2) == ["Notchemon Debug", "Cache"])
    }
}

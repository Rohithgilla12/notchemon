import Foundation
import Testing
@testable import Notchemon

@MainActor
struct AboutTests {
    @Test func disclaimerMatchesTheReadme() throws {
        let readme = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("README.md")
        let text = try String(contentsOf: readme, encoding: .utf8)
        #expect(text.contains(AboutView.disclaimer))
    }

    @Test func licenceShipsInTheApp() throws {
        let url = try #require(Bundle.main.url(forResource: "LICENSE", withExtension: nil))
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("MIT License"))
    }
}

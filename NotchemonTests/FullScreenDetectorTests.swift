import CoreGraphics
import Testing
@testable import Notchemon

/// Built-in geometry measured on a 16-inch MacBook Pro (safe area 32 pt, menu
/// bar 33 pt), with a 1920x1080 display to its right. Quartz rects: origin top-left.
struct FullScreenDetectorTests {
    let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let notchTop: CGFloat = 32
    let external = CGRect(x: 1728, y: 0, width: 1920, height: 1080)

    func window(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, layer: Int = 0) -> WindowSnapshot {
        WindowSnapshot(layer: layer, bounds: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func normalDesktopIsNotFullScreen() {
        let windows = [window(200, 120, 900, 700), window(0, 33, 1728, 1084)]
        #expect(!FullScreenDetector.isFullScreen(screen: builtIn, safeAreaTop: notchTop, windows: windows))
    }

    @Test func autoHiddenMenuBarAloneIsNotFullScreen() {
        #expect(!FullScreenDetector.isFullScreen(screen: external, safeAreaTop: 0, windows: []))
        let ordinary = [window(1900, 0, 900, 700), window(2000, 300, 1200, 780)]
        #expect(!FullScreenDetector.isFullScreen(screen: external, safeAreaTop: 0, windows: ordinary))
    }

    @Test func zoomedWindowBelowMenuBarAreaIsNotFullScreen() {
        #expect(!FullScreenDetector.isFullScreen(screen: external, safeAreaTop: 0, windows: [window(1728, 24, 1920, 1056)]))
        #expect(!FullScreenDetector.isFullScreen(screen: builtIn, safeAreaTop: notchTop, windows: [window(0, 33, 1728, 1084)]))
    }

    @Test func zoomedWindowShortOfTheBottomIsNotFullScreen() {
        let aboveDock = window(1728, 0, 1920, 1000)
        #expect(!FullScreenDetector.isFullScreen(screen: external, safeAreaTop: 0, windows: [aboveDock]))
    }

    @Test func fullScreenWindowFromTheNotchLineDownIsFullScreen() {
        #expect(FullScreenDetector.isFullScreen(screen: builtIn, safeAreaTop: notchTop, windows: [window(0, 32, 1728, 1085)]))
        #expect(FullScreenDetector.isFullScreen(screen: builtIn, safeAreaTop: notchTop, windows: [window(0, 0, 1728, 1117)]))
    }

    @Test func fullScreenWindowOnScreenWithoutNotchIsFullScreen() {
        #expect(FullScreenDetector.isFullScreen(screen: external, safeAreaTop: 0, windows: [window(1728, 0, 1920, 1080)]))
    }

    @Test func fullScreenAppOnAnotherDisplayDoesNotCount() {
        let onExternal = window(1728, 0, 1920, 1080)
        #expect(!FullScreenDetector.isFullScreen(screen: builtIn, safeAreaTop: notchTop, windows: [onExternal]))
    }

    @Test func overlayWindowsAreIgnored() {
        let overlay = window(0, 0, 1728, 1117, layer: 25)
        #expect(!FullScreenDetector.isFullScreen(screen: builtIn, safeAreaTop: notchTop, windows: [overlay]))
    }
}

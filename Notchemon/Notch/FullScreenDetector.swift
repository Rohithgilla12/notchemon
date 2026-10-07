import AppKit

struct WindowSnapshot: Sendable, Equatable {
    var layer: Int
    /// Quartz coordinates: origin at the top-left of the primary display.
    var bounds: CGRect
}

enum FullScreenDetector {
    /// True when an ordinary window covers the whole screen from the notch line
    /// down, which a full-screen window does and a zoomed one only does when
    /// both menu bar and dock auto-hide. The menu bar's height is no signal
    /// here: with auto-hide it reads zero on an ordinary desktop.
    static func isFullScreen(screen: CGRect, safeAreaTop: CGFloat, windows: [WindowSnapshot]) -> Bool {
        var belowNotch = screen
        belowNotch.origin.y += safeAreaTop
        belowNotch.size.height -= safeAreaTop
        return windows.contains { $0.layer == 0 && $0.bounds.contains(belowNotch) }
    }

    static func isFullScreen(_ screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let frame = screen.frame
        let quartzFrame = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        return isFullScreen(screen: quartzFrame, safeAreaTop: screen.safeAreaInsets.top, windows: otherAppsOnScreenWindows())
    }

    /// Reads only bounds and layer, never window names, which are what Screen
    /// Recording permission withholds.
    private static func otherAppsOnScreenWindows() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = getpid()
        return info.compactMap { entry in
            guard
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return WindowSnapshot(layer: layer, bounds: bounds)
        }
    }
}

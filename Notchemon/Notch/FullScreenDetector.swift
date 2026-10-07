import AppKit

struct WindowSnapshot: Sendable, Equatable {
    var ownerPID: pid_t
    var layer: Int
    /// Quartz coordinates: origin at the top-left of the primary display.
    var bounds: CGRect
}

enum FullScreenDetector {
    /// Heuristic over public API. A zoomed window starts exactly at the bottom
    /// of the menu bar; a full-screen window starts above it (at the notch line
    /// on notched displays, at the top elsewhere). A hidden menu bar also counts.
    /// Window bounds and layers need no Screen Recording permission.
    static func isFullScreen(screenBounds: CGRect, menuBarHeight: CGFloat, windows: [WindowSnapshot], ownPID: pid_t) -> Bool {
        if menuBarHeight <= 0 { return true }
        return windows.contains { window in
            window.ownerPID != ownPID
                && window.layer == 0
                && window.bounds.minY < screenBounds.minY + menuBarHeight
                && window.bounds.minX <= screenBounds.minX
                && window.bounds.maxX >= screenBounds.maxX
                && window.bounds.maxY >= screenBounds.maxY
        }
    }

    static func isFullScreen(_ screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let frame = screen.frame
        let quartzBounds = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        return isFullScreen(
            screenBounds: quartzBounds,
            menuBarHeight: screen.metrics.menuBarHeight,
            windows: onScreenWindows(),
            ownPID: getpid()
        )
    }

    private static func onScreenWindows() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { entry in
            guard
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds)
        }
    }
}

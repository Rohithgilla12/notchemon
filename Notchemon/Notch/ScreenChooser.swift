import AppKit

struct ScreenCandidate: Sendable, Equatable {
    var isBuiltIn: Bool
    var isMain: Bool
    var metrics: ScreenMetrics
}

enum ScreenChooser {
    /// Only the built-in display can have a notch, so it wins. In clamshell or
    /// external-only setups the main screen gets a virtual notch.
    static func choose(from candidates: [ScreenCandidate]) -> Int? {
        candidates.firstIndex(where: \.isBuiltIn)
            ?? candidates.firstIndex(where: \.isMain)
            ?? candidates.indices.first
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var metrics: ScreenMetrics {
        ScreenMetrics(
            frame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width ?? 0,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width ?? 0
        )
    }

    var candidate: ScreenCandidate {
        ScreenCandidate(
            isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
            isMain: self == NSScreen.main,
            metrics: metrics
        )
    }

    static var notchHost: NSScreen? {
        let screens = NSScreen.screens
        return ScreenChooser.choose(from: screens.map(\.candidate)).map { screens[$0] }
    }
}

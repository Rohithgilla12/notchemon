/// The one line in the Motion submenu that says what Dock walking is doing
/// right now, so a grant that did not take or a Dock that cannot be walked
/// shows there instead of as a creature that never leaves the top edge.
enum DockWalkingStatus {
    static func line(wanted: Bool, trusted: Bool, read: DockRead?) -> String {
        "Dock walking: " + state(wanted: wanted, trusted: trusted, read: read)
    }

    private static func state(wanted: Bool, trusted: Bool, read: DockRead?) -> String {
        guard wanted else { return "off" }
        guard trusted else { return "needs Accessibility" }
        switch read {
        case nil: return "reading the Dock"
        case .unreadable: return "Dock did not answer"
        case .noShelf(.sideDock): return "Dock is on the side"
        case .noShelf(.noRoom): return "Dock too small to walk"
        case .noShelf(.fullScreen): return "off in full screen"
        case .shelf(let shelf): return shelf.autoHide?.revealed == false ? "on (Dock hidden, walking the bottom edge)" : "on"
        }
    }
}

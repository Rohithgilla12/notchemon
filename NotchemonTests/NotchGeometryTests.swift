import CoreGraphics
import Testing
@testable import Notchemon

struct NotchGeometryTests {
    let macBookPro = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 764,
        auxiliaryTopRightWidth: 764
    )
    let external = ScreenMetrics(
        frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0
    )

    @Test func hardwareNotchIsCentredGapBetweenAuxiliaryAreas() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false))
        #expect(layout.kind == .hardware)
        #expect(layout.notch == CGRect(x: 764, y: 1085, width: 200, height: 32))
    }

    @Test func collapsedExtendsPeekBelowNotch() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false))
        #expect(layout.collapsed == CGRect(x: 764, y: 1041, width: 200, height: 76))
    }

    @Test func fullScreenUsesSmallerPeek() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false, fullScreen: true))
        #expect(layout.collapsed.height == 32 + NotchGeometry.fullScreenPeekHeight)
    }

    @Test func expandedIsCentredAndPinnedToTop() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false))
        #expect(layout.expanded.midX == macBookPro.frame.midX)
        #expect(layout.expanded.maxY == macBookPro.frame.maxY)
        #expect(layout.expanded.width == 440)
        #expect(layout.expanded.height == CGFloat(212))
    }

    @Test func noNotchWithVirtualDisabledHasNoLayout() {
        #expect(NotchGeometry.layout(for: external, virtualNotchEnabled: false) == nil)
    }

    @Test func noNotchWithVirtualEnabledDrawsVirtualNotchOnThatScreen() throws {
        let layout = try #require(NotchGeometry.layout(for: external, virtualNotchEnabled: true))
        #expect(layout.kind == .virtual)
        #expect(layout.notch == CGRect(x: 1728 + 960 - 90, y: 1048, width: 180, height: 32))
    }
}

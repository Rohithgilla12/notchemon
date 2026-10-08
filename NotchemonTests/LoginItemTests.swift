import ServiceManagement
import Testing
@testable import Notchemon

struct LoginItemTests {
    @Test func menuStateFollowsTheServiceStatus() {
        #expect(LoginItemState(.notRegistered) == .off)
        #expect(LoginItemState(.notFound) == .off)
        #expect(LoginItemState(.enabled) == .on)
        #expect(LoginItemState(.requiresApproval) == .needsApproval)
    }
}

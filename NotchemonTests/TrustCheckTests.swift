import ApplicationServices
import Testing
@testable import Notchemon

struct TrustCheckTests {
    @Test func aYesFromAXIsProcessTrustedIsFinalAndSkipsTheProbe() {
        var probed = false
        let check = DockReader.checkTrust(axTrusted: { true }, probe: { probed = true; return .apiDisabled })
        #expect(check == TrustCheck(trusted: true, source: .axIsProcessTrusted))
        #expect(!probed)
    }

    @Test func aNoFromAXIsProcessTrustedIsOverruledByADockReadThatSucceeds() {
        let check = DockReader.checkTrust(axTrusted: { false }, probe: { .success })
        #expect(check == TrustCheck(trusted: true, source: .probeRead))
    }

    @Test func aNoFromAXIsProcessTrustedStandsWhenTheDockReadIsDisabled() {
        let check = DockReader.checkTrust(axTrusted: { false }, probe: { .apiDisabled })
        #expect(check == TrustCheck(trusted: false, source: .probeRead))
    }

    @Test func aDockThatDoesNotAnswerIsNotTakenAsTrusted() {
        let check = DockReader.checkTrust(axTrusted: { false }, probe: { .cannotComplete })
        #expect(check == TrustCheck(trusted: false, source: .probeRead))
    }
}

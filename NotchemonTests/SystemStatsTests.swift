import Foundation
import IOKit.ps
import Testing
@testable import Notchemon

struct CPUTicksTests {
    @Test func usageIsTheBusyShareOfTheTicksBetweenSamples() {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 10)
        let new = CPUTicks(user: 130, system: 60, idle: 850, nice: 10)
        #expect(CPUTicks.usage(from: old, to: new) == 40.0 / 90.0)
    }

    @Test func usageSurvivesACounterThatWrapped() {
        let old = CPUTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 29, nice: 0)
        let new = CPUTicks(user: 10, system: 0, idle: 10, nice: 0)
        #expect(CPUTicks.usage(from: old, to: new) == 20.0 / 60.0)
    }

    @Test func noTicksBetweenSamplesHasNoUsage() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(CPUTicks.usage(from: ticks, to: ticks) == nil)
    }

    @Test func thisMacReportsTicks() {
        #expect(CPUTicks.sample() != nil)
    }
}

struct BatteryStatusTests {
    let battery: [String: Any] = [
        kIOPSTypeKey: kIOPSInternalBatteryType,
        kIOPSIsPresentKey: true,
        kIOPSCurrentCapacityKey: 42,
        kIOPSMaxCapacityKey: 100,
        kIOPSIsChargingKey: true,
    ]

    @Test func readsTheInternalBattery() {
        #expect(BatteryStatus.parse(battery) == BatteryStatus(fraction: 0.42, isCharging: true))
    }

    @Test func aDesktopWithNoPowerSourcesHasNoBattery() {
        #expect(BatteryStatus.parse([]) == nil)
    }

    @Test func aUPSIsNotTheMacsBattery() {
        var ups = battery
        ups[kIOPSTypeKey] = kIOPSUPSType
        #expect(BatteryStatus.parse([ups]) == nil)
    }

    @Test func skipsSourcesThatDoNotFitAndReadsTheNextOne() {
        var malformed = battery
        malformed[kIOPSCurrentCapacityKey] = "lots"
        var zeroMaximum = battery
        zeroMaximum[kIOPSMaxCapacityKey] = 0
        var removed = battery
        removed[kIOPSIsPresentKey] = false
        let status = BatteryStatus.parse([[:], malformed, zeroMaximum, removed, battery])
        #expect(status == BatteryStatus(fraction: 0.42, isCharging: true))
    }

    @Test func aMissingChargingFlagReadsAsNotCharging() {
        var description = battery
        description[kIOPSIsChargingKey] = nil
        #expect(BatteryStatus.parse(description) == BatteryStatus(fraction: 0.42, isCharging: false))
    }

    @Test func readingThisMacsPowerSourcesDoesNotCrash() {
        _ = BatteryStatus.current()
    }
}

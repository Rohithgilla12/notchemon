import Foundation
import IOKit.ps
import Observation

/// CPU ticks summed across every core since boot, as the kernel counts them.
struct CPUTicks: Sendable, Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32

    /// The busy share of the ticks between two samples, or nil when no tick
    /// passed. The counters are 32-bit and wrap, after about 41 days of
    /// uptime on a 12-core Mac, so each delta uses wrapping subtraction.
    static func usage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        let user = Double(new.user &- old.user)
        let system = Double(new.system &- old.system)
        let idle = Double(new.idle &- old.idle)
        let nice = Double(new.nice &- old.nice)
        let busy: Double = user + system + nice
        let total: Double = busy + idle
        return total > 0 ? busy / total : nil
    }

    static func sample() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
    }
}

struct BatteryStatus: Sendable, Equatable {
    var fraction: Double
    var isCharging: Bool

    /// The first internal battery among the power sources, or nil on a Mac
    /// without one. A UPS is a power source too, but not this Mac's battery.
    static func parse(_ descriptions: [[String: Any]]) -> BatteryStatus? {
        for description in descriptions {
            if let status = parse(description) { return status }
        }
        return nil
    }

    static func parse(_ description: [String: Any]) -> BatteryStatus? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              (description[kIOPSIsPresentKey] as? Bool) != false,
              let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
              let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
              maximum > 0
        else { return nil }
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        return BatteryStatus(fraction: min(current / maximum, 1), isCharging: charging)
    }

    static func current() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let descriptions: [[String: Any]] = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return parse(descriptions)
    }
}

/// Live machine stats for the open panel. It samples only between
/// `startMonitoring` and `stopMonitoring`, which the view ties to its
/// lifetime, so nothing polls while the notch is closed.
@MainActor
@Observable
final class SystemStats {
    private(set) var cpuUsage: Double?
    private(set) var memoryUsedGB: Double = 0
    private(set) var memoryTotalGB: Double = 0
    private(set) var diskFreeGB: Double = 0
    private(set) var battery: BatteryStatus?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?

    func startMonitoring() {
        stopMonitoring()
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Lets the system wake once for this and other timers due nearby.
        timer.tolerance = 0.5
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        // A delta across the closed stretch would show its average, not now.
        lastTicks = nil
        cpuUsage = nil
    }

    private func refresh() {
        if let ticks = CPUTicks.sample() {
            if let lastTicks { cpuUsage = CPUTicks.usage(from: lastTicks, to: ticks) ?? cpuUsage }
            lastTicks = ticks
        }
        updateMemory()
        updateDisk()
        battery = BatteryStatus.current()
    }

    private func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pages: UInt64 = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        // Memory is sold in binary gigabytes, so 16 GB of RAM reads as 16, not 17.2.
        let gibibyte: Double = 1_073_741_824
        memoryUsedGB = Double(pages) * Double(pageSize) / gibibyte
        memoryTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / gibibyte
    }

    private func updateDisk() {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attributes[.systemFreeSize] as? NSNumber
        else { return }
        diskFreeGB = free.doubleValue / 1_000_000_000
    }
}

import Foundation
import IOKit.ps
import Observation

@MainActor
@Observable
final class RotomDex {
    var cpuUsage: Double = 0
    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0
    var diskFreeGB: Double = 0
    var diskTotalGB: Double = 0
    var batteryPercentage: Double?
    var isCharging: Bool = false
    
    private var timer: Timer?
    private var previousCpuInfo: host_cpu_load_info?

    init() {}
    
    func startMonitoring() {
        stopMonitoring()
        updateStats()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStats()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateStats() {
        updateCPU()
        updateMemory()
        updateDisk()
        updateBattery()
    }
    
    private func updateCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()
        
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        
        if result == KERN_SUCCESS {
            if let prev = previousCpuInfo {
                let userDiff = Double(cpuInfo.cpu_ticks.0 - prev.cpu_ticks.0)
                let sysDiff  = Double(cpuInfo.cpu_ticks.1 - prev.cpu_ticks.1)
                let idleDiff = Double(cpuInfo.cpu_ticks.2 - prev.cpu_ticks.2)
                let niceDiff = Double(cpuInfo.cpu_ticks.3 - prev.cpu_ticks.3)
                
                let totalTicks = userDiff + sysDiff + idleDiff + niceDiff
                if totalTicks > 0 {
                    let usedTicks = userDiff + sysDiff + niceDiff
                    self.cpuUsage = usedTicks / totalTicks
                }
            }
            previousCpuInfo = cpuInfo
        }
    }
    
    private func updateMemory() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        
        if result == KERN_SUCCESS {
            var pageSizeRaw: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSizeRaw)
            let pageSize = Double(pageSizeRaw)
            let active = Double(vmStats.active_count) * pageSize
            let wire = Double(vmStats.wire_count) * pageSize
            let compressed = Double(vmStats.compressor_page_count) * pageSize
            let used = active + wire + compressed
            
            self.memoryUsedGB = used / 1_000_000_000
            
            let total = ProcessInfo.processInfo.physicalMemory
            self.memoryTotalGB = Double(total) / 1_000_000_000
        }
    }
    
    private func updateDisk() {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        if let path = paths.first,
           let dict = try? FileManager.default.attributesOfFileSystem(forPath: path) {
            if let free = dict[.systemFreeSize] as? NSNumber,
               let total = dict[.systemSize] as? NSNumber {
                self.diskFreeGB = free.doubleValue / 1_000_000_000
                self.diskTotalGB = total.doubleValue / 1_000_000_000
            }
        }
    }
    
    private func updateBattery() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        self.batteryPercentage = nil
        self.isCharging = false
        
        for source in sources {
            let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as! [String: Any]
            if let capacity = description[kIOPSCurrentCapacityKey] as? Double,
               let maxCapacity = description[kIOPSMaxCapacityKey] as? Double,
               let isCharging = description[kIOPSIsChargingKey] as? Bool {
                self.batteryPercentage = capacity / maxCapacity
                self.isCharging = isCharging
                break
            }
        }
    }
}

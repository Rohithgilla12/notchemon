import SwiftUI

struct SystemStatsView: View {
    @State private var stats = SystemStats()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                StatLabel(symbol: "cpu", text: stats.cpuUsage.map(Self.percent) ?? "--%")
                Spacer(minLength: 8)
                if let battery = stats.battery {
                    StatLabel(symbol: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent", text: Self.percent(battery.fraction))
                }
            }
            HStack(spacing: 0) {
                StatLabel(symbol: "memorychip", text: String(format: "%.1f/%.0f GB", stats.memoryUsedGB, stats.memoryTotalGB))
                Spacer(minLength: 8)
                StatLabel(symbol: "internaldrive", text: String(format: "%.0f GB free", stats.diskFreeGB))
            }
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.6))
        .onAppear { stats.startMonitoring() }
        .onDisappear { stats.stopMonitoring() }
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }
}

private struct StatLabel: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
    }
}

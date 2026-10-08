import SwiftUI

struct RotomDexView: View {
    @Bindable var rotomDex: RotomDex
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(rotomDex.isCharging ? .green : .yellow)
                Text(batteryText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "cpu")
                    .foregroundColor(.red)
                Text(String(format: "%.0f%%", rotomDex.cpuUsage * 100))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            
            HStack {
                Image(systemName: "memorychip")
                    .foregroundColor(.blue)
                Text(String(format: "%.1f/%.1f GB", rotomDex.memoryUsedGB, rotomDex.memoryTotalGB))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "internaldrive")
                    .foregroundColor(.orange)
                Text(String(format: "%.0f GB Free", rotomDex.diskFreeGB))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 2))
        )
        .onAppear {
            rotomDex.startMonitoring()
        }
        .onDisappear {
            rotomDex.stopMonitoring()
        }
    }
    
    private var batteryText: String {
        if let level = rotomDex.batteryPercentage {
            return String(format: "%.0f%%", level * 100)
        }
        return "--%"
    }
}

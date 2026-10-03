import Darwin
import Foundation
import IOKit.ps
import OverhangCore
import SwiftUI

/// Samples CPU, memory, disk, network and battery. Only runs while the tool is visible.
final class SystemStatsService: ObservableObject {
    static let shared = SystemStatsService()

    struct Battery: Equatable {
        var percent: Double
        var charging: Bool
        var onAC: Bool
    }

    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var diskUsed: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var downRate: Double = 0
    @Published private(set) var upRate: Double = 0
    @Published private(set) var netHistory: [Double] = []
    @Published private(set) var battery: Battery?
    @Published private(set) var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime

    private var timer: Timer?
    private var users = 0
    private var previousTicks: (used: UInt64, total: UInt64)?
    private var previousNet: (down: UInt64, up: UInt64, at: Date)?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousNet = nil
    }

    func retain() {
        users += 1
        start()
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { stop() }
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
        sampleNetwork()
        battery = Self.readBattery()
        uptime = ProcessInfo.processInfo.systemUptime
    }

    private func sampleCPU() {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let user = UInt64(load.cpu_ticks.0)
        let system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2)
        let nice = UInt64(load.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        if let previous = previousTicks, total > previous.total {
            cpu = Double(used - previous.used) / Double(total - previous.total)
            cpuHistory = Array((cpuHistory + [cpu]).suffix(60))
        }
        previousTicks = (used, total)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = UInt64(getpagesize())
        // Roughly what Activity Monitor calls "Memory Used": app + wired + compressed.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        memoryUsed = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return }
        diskTotal = Int64(total)
        diskUsed = Int64(total) - available
    }

    private func sampleNetwork() {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let interface = entry.pointee
            cursor = interface.ifa_next
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data
            else { continue }
            let name = String(cString: interface.ifa_name)
            // Physical Wi-Fi/Ethernet and cellular only; skip loopback, VPN tunnels, AWDL and bridges.
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            down += UInt64(stats.ifi_ibytes)
            up += UInt64(stats.ifi_obytes)
        }
        let now = Date()
        if let previous = previousNet {
            let elapsed = now.timeIntervalSince(previous.at)
            if elapsed > 0, down >= previous.down, up >= previous.up {
                downRate = Double(down - previous.down) / elapsed
                upRate = Double(up - previous.up) / elapsed
                netHistory = Array((netHistory + [downRate + upRate]).suffix(60))
            }
        }
        previousNet = (down, up, now)
    }

    static func readBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
        else { return nil }
        let sources = list as Array
        for source in sources {
            guard let unmanaged = IOPSGetPowerSourceDescription(info, source as CFTypeRef),
                  let description = unmanaged.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery",
                  let current = description["Current Capacity"] as? Double,
                  let max = description["Max Capacity"] as? Double, max > 0
            else { continue }
            return Battery(
                percent: current / max,
                charging: description["Is Charging"] as? Bool ?? false,
                onAC: description["Power Source State"] as? String == "AC Power"
            )
        }
        return nil
    }
}

enum ByteFormat {
    static func string(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .decimal) + "/s"
    }
}

struct SystemStatsView: View {
    @ObservedObject private var stats = SystemStatsService.shared

    var body: some View {
        HStack(spacing: 10) {
            StatCard(title: "CPU", value: "\(Int(stats.cpu * 100))%", fraction: stats.cpu, color: Theme.accent) {
                Sparkline(values: stats.cpuHistory, color: Theme.accent)
            }
            StatCard(title: "Memory", value: ByteFormat.string(Double(stats.memoryUsed)),
                     subtitle: "of " + ByteFormat.string(Double(stats.memoryTotal)),
                     fraction: Double(stats.memoryUsed) / Double(max(stats.memoryTotal, 1)), color: .purple) { EmptyView() }
            StatCard(title: "Disk", value: ByteFormat.string(Double(stats.diskTotal - stats.diskUsed)),
                     subtitle: "free of " + ByteFormat.string(Double(stats.diskTotal)),
                     fraction: Double(stats.diskUsed) / Double(max(stats.diskTotal, 1)), color: .orange) { EmptyView() }
            StatCard(title: "Network", value: "↓ " + ByteFormat.rate(stats.downRate), subtitle: "↑ " + ByteFormat.rate(stats.upRate),
                     fraction: nil, color: Theme.positive) {
                Sparkline(values: stats.netHistory, color: Theme.positive)
            }
            if let battery = stats.battery {
                StatCard(title: "Battery", value: "\(Int(battery.percent * 100))%",
                         subtitle: battery.charging ? "Charging" : battery.onAC ? "On power" : "On battery",
                         fraction: battery.percent, color: battery.percent < 0.2 ? Theme.negative : Theme.positive) { EmptyView() }
            }
        }
        .onAppear { stats.retain() }
        .onDisappear { stats.release() }
    }
}

private struct StatCard<Extra: View>: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let fraction: Double?
    let color: Color
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            if let fraction {
                RingGauge(value: fraction, color: color, lineWidth: 6)
                    .frame(width: 64, height: 64)
                    .frame(maxWidth: .infinity)
            }
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            extra().frame(height: fraction == nil ? 70 : 24)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }
}

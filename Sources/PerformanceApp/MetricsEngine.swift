import Foundation
import Darwin
import IOKit
import IOKit.storage
import IOKit.ps
import AppKit
import UserNotifications
import UniformTypeIdentifiers
import Metal
import Network
import IOBluetooth
import CoreBluetooth
import CoreWLAN

@MainActor
final class MetricsEngine: ObservableObject {
    @Published var cpuUsagePercent: Double = 0
    @Published var cpuUserPercent: Double = 0
    @Published var cpuSystemPercent: Double = 0
    @Published var cpuIdlePercent: Double = 100
    @Published var loadAverages: (one: Double, five: Double, fifteen: Double) = (0, 0, 0)
    @Published var perCoreUsage: [Double] = []
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var swapUsedGB: Double = 0
    @Published var memoryAppGB: Double = 0
    @Published var memoryWiredGB: Double = 0
    @Published var memoryCompressedGB: Double = 0

    @Published var downloadSpeedKBps: Double = 0
    @Published var uploadSpeedKBps: Double = 0

    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var downloadHistory: [Double] = []
    @Published var uploadHistory: [Double] = []

    @Published var diskFreeGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var diskReadKBps: Double = 0
    @Published var diskWriteKBps: Double = 0
    @Published var diskReadHistory: [Double] = []
    @Published var diskWriteHistory: [Double] = []
    @Published var gpuMetricsAvailable: Bool = false
    @Published var volumes: [VolumeInfo] = []

    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    @Published var topCPUProcesses: [ProcessUsage] = []
    @Published var topMemoryProcesses: [ProcessUsage] = []
    @Published var topNetworkProcesses: [ProcessUsage] = []

    @Published var localInterfaces: [LocalInterface] = []
    @Published var isVPNActive: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionType: String = "Unknown"
    @Published var wifiSSID: String? = nil
    @Published var wifiRSSI: Int? = nil      // dBm, nil when not on WiFi

    @Published var publicIPEnabled: Bool = true {
        didSet {
            if publicIPEnabled { fetchPublicIP() } else { publicIP = nil }
        }
    }
    @Published var publicIP: String?
    private var lastPublicIPFetch: Date?
    private var pathMonitor: NWPathMonitor?

    @Published var pingLatencyMs: Double?
    @Published var pingHistory: [Double] = []
    private var pingTimer: Timer?

    @Published var batteryPercent: Int?
    @Published var batteryIsCharging: Bool = false
    @Published var batteryTimeRemainingMinutes: Int?
    @Published var powerSourceName: String = "Unknown"

    @Published var batteryCycleCount: Int?
    @Published var batteryDesignCycleCount: Int?
    @Published var batteryHealthPercent: Double?
    @Published var batteryTemperatureC: Double?
    @Published var batteryVoltage: Double?
    @Published var batteryAmperage: Int?
    @Published var batteryCondition: String = "Normal"

    @Published var displays: [DisplayInfo] = []
    @Published var bluetoothDevices: [BluetoothDevice] = []
    @Published var bluetoothAuthState: CBManagerAuthorization = CBCentralManager.authorization

    // Held strongly so the permission dialog can fire and the delegate callback arrives.
    private var btAuthManager: CBCentralManager?
    private var btDelegate: BluetoothAuthDelegate?
    @Published var performanceCoreCount: Int = 0
    @Published var efficiencyCoreCount: Int = 0

    @Published var gpuName: String = "Unknown"
    @Published var gpuRecommendedMemoryGB: Double = 0
    @Published var gpuIsLowPower: Bool = false
    @Published var gpuIsRemovable: Bool = false
    @Published var gpuLocation: String = "Built-in"

    @Published var alertsEnabled: Bool = false {
        didSet { if alertsEnabled { requestNotificationAuthorization() } }
    }
    @Published var cpuAlertThreshold: Double = 90
    @Published var diskFreeAlertThresholdGB: Double = 10
    private var lastAlertFired: [String: Date] = [:]
    private let alertCooldown: TimeInterval = 300

    @Published var topProcessCount: Int = 6
    @Published var showRemovableVolumes: Bool = true
    @Published var persistHistoryEnabled: Bool = false
    private let historyFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.csv")
    }()
    private var historyFileHandle: FileHandle?

    enum MenuBarMetric: String, CaseIterable, Identifiable {
        case cpu, memory, network, disk
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "Memory"
            case .network: return "Network"
            case .disk: return "Disk"
            }
        }
    }

    @Published var menuBarMetric: MenuBarMetric = .cpu

    @Published var refreshInterval: Double = 1.0 {
        didSet { restartTimer() }
    }

    private let historyLimit = 300 // ~5 min at 1s interval
    private var timer: Timer?
    private var previousCPUTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var previousNetBytes: (received: UInt64, sent: UInt64)?
    private var previousNetTimestamp: Date?
    private var previousDiskBytes: (read: UInt64, write: UInt64)?
    private var previousDiskTimestamp: Date?
    private var thermalObserver: NSObjectProtocol?
    private var processSamplerInFlight = false
    private var networkSamplerInFlight = false
    private var previousProcessNetBytes: [String: (in: Double, out: Double)] = [:]
    private var previousProcessNetTimestamp: Date?

    var menuBarLabel: String {
        switch menuBarMetric {
        case .cpu: return String(format: "CPU %.0f%%", cpuUsagePercent)
        case .memory: return String(format: "MEM %.1fGB", memoryUsedGB)
        case .network: return String(format: "↓%.0f KB/s", downloadSpeedKBps)
        case .disk: return String(format: "DISK %.0fGB", diskFreeGB)
        }
    }

    init() {
        thermalState = ProcessInfo.processInfo.thermalState
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.thermalState = ProcessInfo.processInfo.thermalState
            }
        }
        updateGPUInfo()
        readCoreClusterCounts()
        startPathMonitor()
        startPingTimer()
        if publicIPEnabled { fetchPublicIP() }
        refresh()
        restartTimer()
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        performLatencyCheck()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performLatencyCheck() }
        }
    }

    private func performLatencyCheck() {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self else { return }
                if error == nil, response != nil {
                    let elapsedMs = Date().timeIntervalSince(start) * 1000
                    self.pingLatencyMs = elapsedMs
                    self.pingHistory.append(elapsedMs)
                    if self.pingHistory.count > 60 { self.pingHistory.removeFirst() }
                } else {
                    self.pingLatencyMs = nil
                }
            }
        }
        task.resume()
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = "Wi-Fi"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = "Ethernet"
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = "Cellular"
                } else if path.status == .satisfied {
                    self.connectionType = "Other"
                } else {
                    self.connectionType = "Offline"
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkPathMonitor"))
        pathMonitor = monitor
    }

    private func updateGPUInfo() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        gpuName = device.name
        gpuRecommendedMemoryGB = Double(device.recommendedMaxWorkingSetSize) / 1_073_741_824
        gpuIsLowPower = device.isLowPower
        gpuIsRemovable = device.isRemovable
        gpuLocation = device.isRemovable ? "External" : "Built-in"
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        updateCPU()
        updateMemory()
        updateNetwork()
        updateDisk()
        updateProcesses()
        updateNetworkProcesses()
        updateBattery()
        updateDisplays()
        updateWiFiSignal()
        updateBluetooth()
        checkAlerts()
        appendPersistedHistoryRow()

        if publicIPEnabled {
            if lastPublicIPFetch == nil || Date().timeIntervalSince(lastPublicIPFetch!) > 300 {
                fetchPublicIP()
            }
        }

        cpuHistory.append(cpuUsagePercent)
        if cpuHistory.count > historyLimit { cpuHistory.removeFirst() }
        memoryHistory.append(memoryUsedGB)
        if memoryHistory.count > historyLimit { memoryHistory.removeFirst() }
        downloadHistory.append(downloadSpeedKBps)
        if downloadHistory.count > historyLimit { downloadHistory.removeFirst() }
        uploadHistory.append(uploadSpeedKBps)
        if uploadHistory.count > historyLimit { uploadHistory.removeFirst() }
        diskReadHistory.append(diskReadKBps)
        if diskReadHistory.count > historyLimit { diskReadHistory.removeFirst() }
        diskWriteHistory.append(diskWriteKBps)
        if diskWriteHistory.count > historyLimit { diskWriteHistory.removeFirst() }
    }

    // MARK: - CPU

    private func updateCPU() {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t!
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                          PROCESSOR_CPU_LOAD_INFO,
                                          &numCPUsU,
                                          &cpuInfo,
                                          &numCPUInfo)
        guard result == KERN_SUCCESS else { return }

        let numCPUs = Int(numCPUsU)
        var ticksPerCore: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        let cpuLoadInfo = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCPUInfo)) { $0 }

        for i in 0..<numCPUs {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt32(cpuLoadInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(cpuLoadInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(cpuLoadInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(cpuLoadInfo[base + Int(CPU_STATE_NICE)])
            ticksPerCore.append((user, system, idle, nice))
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride))

        if previousCPUTicks.count == ticksPerCore.count {
            var coreUsages: [Double] = []
            var totalUser: Double = 0
            var totalSystem: Double = 0
            var totalNice: Double = 0
            var totalTicks: Double = 0

            for i in 0..<ticksPerCore.count {
                let prev = previousCPUTicks[i]
                let curr = ticksPerCore[i]
                let userDelta = Double(curr.user &- prev.user)
                let systemDelta = Double(curr.system &- prev.system)
                let niceDelta = Double(curr.nice &- prev.nice)
                let idleDelta = Double(curr.idle &- prev.idle)
                let usedDelta = userDelta + systemDelta + niceDelta
                let total = usedDelta + idleDelta
                coreUsages.append(total > 0 ? (usedDelta / total) * 100 : 0)
                totalUser += userDelta
                totalSystem += systemDelta
                totalNice += niceDelta
                totalTicks += total
            }

            perCoreUsage = coreUsages
            cpuUsagePercent = totalTicks > 0 ? ((totalUser + totalSystem + totalNice) / totalTicks) * 100 : 0
            cpuUserPercent = totalTicks > 0 ? (totalUser / totalTicks) * 100 : 0
            cpuSystemPercent = totalTicks > 0 ? (totalSystem / totalTicks) * 100 : 0
            cpuIdlePercent = max(100 - cpuUsagePercent, 0)
        }

        previousCPUTicks = ticksPerCore

        var loadavg = [Double](repeating: 0, count: 3)
        if getloadavg(&loadavg, 3) == 3 {
            loadAverages = (loadavg[0], loadavg[1], loadavg[2])
        }
    }

    // MARK: - Memory

    private func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        let used = Double(stats.active_count + stats.inactive_count + stats.wire_count) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        memoryUsedGB = used / 1_073_741_824
        memoryTotalGB = total / 1_073_741_824
        memoryAppGB = Double(stats.active_count + stats.inactive_count) * pageSize / 1_073_741_824
        memoryWiredGB = Double(stats.wire_count) * pageSize / 1_073_741_824
        memoryCompressedGB = Double(stats.compressor_page_count) * pageSize / 1_073_741_824

        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0) == 0 {
            swapUsedGB = Double(swapUsage.xsu_used) / 1_073_741_824
        }
    }

    // MARK: - Network

    private func updateNetwork() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0
        var interfaces: [LocalInterface] = []
        var vpnDetected = false

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let ifa = current.pointee
            let name = String(cString: ifa.ifa_name)
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), !name.hasPrefix("lo") {
                if let data = ifa.ifa_data {
                    let networkData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                    totalReceived += UInt64(networkData.ifi_ibytes)
                    totalSent += UInt64(networkData.ifi_obytes)
                }
            }
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), !name.hasPrefix("lo") {
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: buffer)
                    interfaces.append(LocalInterface(name: name, address: ip))
                    if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                        vpnDetected = true
                    }
                }
            }
            ptr = ifa.ifa_next
        }

        localInterfaces = interfaces
        isVPNActive = vpnDetected

        let now = Date()
        if let prev = previousNetBytes, let prevTime = previousNetTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let receivedDelta = Double(totalReceived &- prev.received)
                let sentDelta = Double(totalSent &- prev.sent)
                downloadSpeedKBps = max(receivedDelta, 0) / elapsed / 1024
                uploadSpeedKBps = max(sentDelta, 0) / elapsed / 1024
            }
        }

        previousNetBytes = (totalReceived, totalSent)
        previousNetTimestamp = now
    }

    // MARK: - Disk

    private func updateDisk() {
        var fsStat = statfs()
        if statfs("/", &fsStat) == 0 {
            let blockSize = Double(fsStat.f_bsize)
            diskTotalGB = Double(fsStat.f_blocks) * blockSize / 1_073_741_824
            diskFreeGB = Double(fsStat.f_bavail) * blockSize / 1_073_741_824
        }

        updateVolumes()

        var (totalRead, totalWrite): (UInt64, UInt64) = (0, 0)
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }

            if let read = stats["Bytes (Read)"] as? UInt64 {
                totalRead += read
            }
            if let write = stats["Bytes (Write)"] as? UInt64 {
                totalWrite += write
            }
        }

        let now = Date()
        if let prev = previousDiskBytes, let prevTime = previousDiskTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let readDelta = Double(totalRead &- prev.read)
                let writeDelta = Double(totalWrite &- prev.write)
                diskReadKBps = max(readDelta, 0) / elapsed / 1024
                diskWriteKBps = max(writeDelta, 0) / elapsed / 1024
            }
        }
        previousDiskBytes = (totalRead, totalWrite)
        previousDiskTimestamp = now
    }

    private func updateVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return
        }

        volumes = urls.compactMap { url -> VolumeInfo? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            return VolumeInfo(
                name: name,
                totalGB: Double(total) / 1_073_741_824,
                freeGB: Double(available) / 1_073_741_824,
                isRemovable: values.volumeIsRemovable ?? false
            )
        }
    }

    // MARK: - Top processes

    private func updateProcesses() {
        guard !processSamplerInFlight else { return }
        processSamplerInFlight = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-arcwwwxo", "pid,comm,%cpu,%mem"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        let capturedCount = topProcessCount
        task.terminationHandler = { [weak self] _ in
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n").dropFirst()

            var cpuList: [ProcessUsage] = []
            var memList: [ProcessUsage] = []

            for line in lines {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 4,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[parts.count - 2]),
                      let mem = Double(parts[parts.count - 1]) else { continue }
                let name = parts[1..<(parts.count - 2)].joined(separator: " ")
                cpuList.append(ProcessUsage(pid: pid, name: name, value: cpu))
                memList.append(ProcessUsage(pid: pid, name: name, value: mem))
            }

            let topCPU = Array(cpuList.sorted { $0.value > $1.value }.prefix(capturedCount))
            let topMem = Array(memList.sorted { $0.value > $1.value }.prefix(capturedCount))

            DispatchQueue.main.async {
                self?.topCPUProcesses = topCPU
                self?.topMemoryProcesses = topMem
                self?.processSamplerInFlight = false
            }
        }

        do {
            try task.run()
        } catch {
            processSamplerInFlight = false
        }
    }

    // MARK: - Per-app network usage

    private func updateNetworkProcesses() {
        guard !networkSamplerInFlight else { return }
        networkSamplerInFlight = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-x", "-L", "1", "-J", "bytes_in,bytes_out"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        task.terminationHandler = { [weak self] _ in
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n").dropFirst()

            var current: [String: (in: Double, out: Double)] = [:]
            for line in lines {
                let parts = line.split(separator: ",", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { continue }
                let name = String(parts[0])
                guard let bytesIn = Double(parts[1]), let bytesOut = Double(parts[2]) else { continue }
                current[name] = (bytesIn, bytesOut)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                let now = Date()
                if let prevTime = self.previousProcessNetTimestamp {
                    let elapsed = now.timeIntervalSince(prevTime)
                    if elapsed > 0 {
                        var list: [ProcessUsage] = []
                        for (name, bytes) in current {
                            let prev = self.previousProcessNetBytes[name] ?? (0, 0)
                            let deltaIn = max(bytes.in - prev.in, 0)
                            let deltaOut = max(bytes.out - prev.out, 0)
                            let kbps = (deltaIn + deltaOut) / elapsed / 1024
                            if kbps > 0.05 {
                                let displayName = name.split(separator: ".").dropLast().joined(separator: ".")
                                list.append(ProcessUsage(pid: 0, name: displayName.isEmpty ? name : displayName, value: kbps))
                            }
                        }
                        self.topNetworkProcesses = Array(list.sorted { $0.value > $1.value }.prefix(6))
                    }
                }
                self.previousProcessNetBytes = current
                self.previousProcessNetTimestamp = now
                self.networkSamplerInFlight = false
            }
        }

        do {
            try task.run()
        } catch {
            networkSamplerInFlight = false
        }
    }

    // MARK: - Process control

    func terminateProcess(pid: Int32) {
        kill(pid, SIGTERM)
    }

    func disconnectBluetooth(id: String) {
        let targetName = bluetoothDevices.first(where: { $0.id == id })?.name

        // Path 1: Classic Bluetooth via IOBluetooth
        IOBluetoothDevice(addressString: id)?.closeConnection()

        // Path 2: BLE via CoreBluetooth — CBPeripheral has no MAC address on macOS
        // so we match the connected peripheral by display name.
        if let central = btAuthManager, let name = targetName {
            // Service UUIDs covering common Apple peripherals + generic profiles
            let serviceUUIDs = [
                CBUUID(string: "1800"),   // Generic Access
                CBUUID(string: "180A"),   // Device Information
                CBUUID(string: "180F"),   // Battery
                CBUUID(string: "FE03"),   // AirPods audio
                CBUUID(string: "FD44"),   // Beats/AirPods
            ]
            for uuid in serviceUUIDs {
                for peripheral in central.retrieveConnectedPeripherals(withServices: [uuid]) {
                    if peripheral.name == name {
                        central.cancelPeripheralConnection(peripheral)
                    }
                }
            }
        }

        // Optimistic UI update so the row disappears immediately
        bluetoothDevices = bluetoothDevices.map { d in
            guard d.id == id else { return d }
            return BluetoothDevice(id: d.id, name: d.name, isConnected: false,
                                   batteryPercent: d.batteryPercent, icon: d.icon)
        }

        // Verify actual state after the OS has processed the disconnect
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            self?.readBluetoothDevices()
        }
    }

    // MARK: - Alerts

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkAlerts() {
        guard alertsEnabled else { return }

        if cpuUsagePercent >= cpuAlertThreshold {
            fireAlert(key: "cpu", title: "High CPU usage", body: String(format: "CPU usage is at %.0f%%", cpuUsagePercent))
        }
        if diskFreeGB > 0, diskFreeGB <= diskFreeAlertThresholdGB {
            fireAlert(key: "disk", title: "Low disk space", body: String(format: "Only %.1f GB free", diskFreeGB))
        }
        if thermalState == .serious || thermalState == .critical {
            fireAlert(key: "thermal", title: "System running hot", body: "Thermal pressure: \(thermalState.label)")
        }
    }

    private func fireAlert(key: String, title: String, body: String) {
        let now = Date()
        if let last = lastAlertFired[key], now.timeIntervalSince(last) < alertCooldown { return }
        lastAlertFired[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "\(key)-\(now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - History persistence

    private func appendPersistedHistoryRow() {
        guard persistHistoryEnabled else { return }

        if historyFileHandle == nil {
            if !FileManager.default.fileExists(atPath: historyFileURL.path) {
                let header = "timestamp,cpu_percent,memory_gb,download_kbps,upload_kbps,disk_free_gb\n"
                try? header.write(to: historyFileURL, atomically: true, encoding: .utf8)
            }
            historyFileHandle = try? FileHandle(forWritingTo: historyFileURL)
            historyFileHandle?.seekToEndOfFile()
        }

        let row = "\(Date().timeIntervalSince1970),\(cpuUsagePercent),\(memoryUsedGB),\(downloadSpeedKBps),\(uploadSpeedKBps),\(diskFreeGB)\n"
        if let data = row.data(using: .utf8) {
            historyFileHandle?.write(data)
        }
    }

    func exportHistoryCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "performance-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "timestamp,cpu_percent,memory_gb,download_kbps,upload_kbps,disk_read_kbps,disk_write_kbps\n"
        let count = cpuHistory.count
        for i in 0..<count {
            let mem = i < memoryHistory.count ? memoryHistory[i] : 0
            let down = i < downloadHistory.count ? downloadHistory[i] : 0
            let up = i < uploadHistory.count ? uploadHistory[i] : 0
            let dr = i < diskReadHistory.count ? diskReadHistory[i] : 0
            let dw = i < diskWriteHistory.count ? diskWriteHistory[i] : 0
            csv += "\(i),\(cpuHistory[i]),\(mem),\(down),\(up),\(dr),\(dw)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Battery / Power

    private func updateBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            batteryPercent = nil
            powerSourceName = "No battery"
            return
        }

        batteryPercent = info[kIOPSCurrentCapacityKey] as? Int
        let state = info[kIOPSPowerSourceStateKey] as? String
        batteryIsCharging = (state == kIOPSACPowerValue)
        powerSourceName = batteryIsCharging ? "AC Power" : "Battery"

        if let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int, timeToEmpty >= 0, !batteryIsCharging {
            batteryTimeRemainingMinutes = timeToEmpty
        } else if let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int, timeToFull >= 0, batteryIsCharging {
            batteryTimeRemainingMinutes = timeToFull
        } else {
            batteryTimeRemainingMinutes = nil
        }

        updateBatteryHealth()
    }

    // MARK: - Public IP (opt-in, calls a third-party service)

    private func fetchPublicIP() {
        lastPublicIPFetch = Date()
        guard let url = URL(string: "https://api.ipify.org?format=text") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let ip = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.publicIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.resume()
    }

    private func updateBatteryHealth() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            batteryCycleCount = nil
            return
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            batteryCycleCount = nil
            return
        }

        batteryCycleCount = props["CycleCount"] as? Int
        batteryDesignCycleCount = props["DesignCycleCount9C"] as? Int

        if let designCapacity = props["DesignCapacity"] as? Int, designCapacity > 0,
           let nominalCapacity = props["NominalChargeCapacity"] as? Int {
            batteryHealthPercent = (Double(nominalCapacity) / Double(designCapacity)) * 100
        } else {
            batteryHealthPercent = nil
        }

        if let temp = props["Temperature"] as? Int {
            batteryTemperatureC = Double(temp) / 100.0
        }
        if let voltage = props["Voltage"] as? Int {
            batteryVoltage = Double(voltage) / 1000.0
        }
        batteryAmperage = props["Amperage"] as? Int

        if let health = batteryHealthPercent {
            batteryCondition = health >= 80 ? "Normal" : "Service Recommended"
        }
    }

    // MARK: - Bluetooth

    func requestBluetoothAccess() {
        guard btDelegate == nil else { return }
        let delegate = BluetoothAuthDelegate { [weak self] auth in
            guard let self else { return }
            self.bluetoothAuthState = auth
            if auth == .allowedAlways {
                self.readBluetoothDevices()
            }
        }
        btDelegate = delegate
        btAuthManager = CBCentralManager(delegate: delegate, queue: .main)
    }

    private func updateBluetooth() {
        let auth = CBCentralManager.authorization
        bluetoothAuthState = auth
        switch auth {
        case .allowedAlways:
            readBluetoothDevices()
        case .notDetermined:
            requestBluetoothAccess()
        default:
            break
        }
    }

    private func readBluetoothDevices() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        bluetoothDevices = paired.map { device in
            let cod = device.classOfDevice
            let majorClass = (Int(cod) & 0x1F00) >> 8
            let icon: String
            switch majorClass {
            case 1: icon = "laptopcomputer"
            case 2: icon = "iphone"
            case 4: icon = "headphones"
            case 5: icon = "keyboard"
            default: icon = "dot.radiowaves.left.and.right"
            }
            let battery = bluetoothBattery(for: device)
            return BluetoothDevice(
                id: device.addressString ?? UUID().uuidString,
                name: device.nameOrAddress ?? "Unknown",
                isConnected: device.isConnected(),
                batteryPercent: battery,
                icon: icon
            )
        }
    }

    private func bluetoothBattery(for device: IOBluetoothDevice) -> Int? {
        guard device.isConnected(), let addr = device.addressString else { return nil }
        let matching = IOServiceMatching("IOHIDDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any] else { continue }
            // Match by BT address in the device address property
            if let deviceAddr = props["DeviceAddress"] as? String,
               deviceAddr.lowercased().replacingOccurrences(of: "-", with: ":") == addr.lowercased(),
               let pct = props["BatteryPercent"] as? Int {
                return pct
            }
        }
        return nil
    }

    // MARK: - CPU Core Clusters

    private func readCoreClusterCounts() {
        var pCores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.physicalcpu", &pCores, &size, nil, 0)
        performanceCoreCount = Int(pCores)

        var eCores: Int32 = 0
        sysctlbyname("hw.perflevel1.physicalcpu", &eCores, &size, nil, 0)
        efficiencyCoreCount = Int(eCores)
    }

    // MARK: - WiFi Signal

    private func updateWiFiSignal() {
        guard connectionType == "Wi-Fi" else {
            wifiSSID = nil
            wifiRSSI = nil
            return
        }
        let iface = CWWiFiClient.shared().interface()
        wifiSSID = iface?.ssid()
        if let rssi = iface?.rssiValue(), rssi != 0 {
            wifiRSSI = rssi
        } else {
            wifiRSSI = nil
        }
    }

    // MARK: - Displays

    private func updateDisplays() {
        displays = NSScreen.screens.enumerated().map { index, screen in
            let scale = screen.backingScaleFactor
            let frame = screen.frame
            // Use native pixel resolution (points × backing scale factor)
            let nativeW = Int(frame.width * scale)
            let nativeH = Int(frame.height * scale)
            return DisplayInfo(
                id: index,
                name: screen.localizedName,
                width: nativeW,
                height: nativeH,
                refreshRateHz: screen.maximumFramesPerSecond,
                scaleFactor: scale,
                isMain: screen == NSScreen.main
            )
        }
    }
}

struct DisplayInfo: Identifiable {
    let id: Int
    let name: String
    let width: Int
    let height: Int
    let refreshRateHz: Int
    let scaleFactor: Double
    let isMain: Bool
}

struct VolumeInfo: Identifiable {
    let name: String
    let totalGB: Double
    let freeGB: Double
    let isRemovable: Bool
    var id: String { name }
}

struct LocalInterface: Identifiable {
    let name: String
    let address: String
    var id: String { name }
}

struct ProcessUsage: Identifiable {
    let pid: Int32
    let name: String
    let value: Double
    var id: String { "\(pid)-\(name)" }
}

struct BluetoothDevice: Identifiable {
    let id: String
    let name: String
    let isConnected: Bool
    let batteryPercent: Int?
    let icon: String
}

// NSObject subclass required for CBCentralManagerDelegate conformance.
final class BluetoothAuthDelegate: NSObject, CBCentralManagerDelegate {
    private let onUpdate: (CBManagerAuthorization) -> Void

    init(onUpdate: @escaping (CBManagerAuthorization) -> Void) {
        self.onUpdate = onUpdate
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onUpdate(CBCentralManager.authorization)
    }
}

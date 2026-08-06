import Foundation
import IOBluetooth
import CoreBluetooth
import PerformanceAppCore

/// Owns Bluetooth authorisation, the paired-device read throttle, and the
/// battery caches (system_profiler parse + BLE GATT read). Publishes results
/// back to the engine through the `onDevices`/`onAuth` callbacks.
///
/// Extracted verbatim from `MetricsEngine`'s Bluetooth section in the Part-B
/// decomposition; `BluetoothAuthDelegate` and `BLEBatteryReader` moved with it.
@MainActor
final class BluetoothSampler {
    /// Called with a fresh paired-device list whenever one is read.
    var onDevices: (([BluetoothDevice]) -> Void)?
    /// Called with the current CoreBluetooth authorisation state each refresh.
    var onAuth: ((CBManagerAuthorization) -> Void)?

    // Held strongly so the permission dialog can fire and the delegate callback arrives.
    private var btAuthManager: CBCentralManager?
    private var btDelegate: BluetoothAuthDelegate?
    private var btBatteryCache: [String: BTBatteryInfo] = [:]
    private var btBatteryCacheDate: Date = .distantPast
    private var bleBatteryByName: [String: Int] = [:]
    private var bleBatteryReader: BLEBatteryReader?
    private var btDevicesCacheDate: Date = .distantPast

    /// Drops the read throttles so the next `update` reads immediately. Called
    /// when the popover or the Bluetooth window appears, so neither has to wait
    /// out an interval that was measured for the background case.
    func resetThrottle() {
        btDevicesCacheDate = .distantPast
        btBatteryCacheDate = .distantPast
    }

    func requestAccess() {
        guard btDelegate == nil else { return }
        let delegate = BluetoothAuthDelegate { [weak self] auth in
            guard let self else { return }
            self.onAuth?(auth)
            if auth == .allowedAlways {
                self.readBluetoothDevices()
            }
        }
        btDelegate = delegate
        btAuthManager = CBCentralManager(delegate: delegate, queue: .main)
    }

    /// - Parameter readDevices: Whether anything is on screen that shows the
    ///   device list or their battery levels. When nothing is, the paired-device
    ///   read and the `system_profiler` call behind the battery levels are both
    ///   skipped. That call costs 0.05s of CPU and ran every 25 seconds
    ///   regardless, which was 0.2% of a machine doing nothing.
    func update(readDevices: Bool) {
        let auth = CBCentralManager.authorization
        onAuth?(auth)
        guard readDevices else { return }
        switch auth {
        case .allowedAlways:
            // Ensure CBCentralManager exists — needed for BLE disconnect.
            // If already authorised at launch, requestAccess() is never called by
            // the notDetermined path, leaving btAuthManager nil.
            if btAuthManager == nil { requestAccess() }
            readBluetoothDevices()
        case .notDetermined:
            requestAccess()
        default:
            break
        }
    }

    private func readBluetoothDevices() {
        refreshBTBatteryCache()
        let now = Date()
        guard now.timeIntervalSince(btDevicesCacheDate) > 5 else { return }
        btDevicesCacheDate = now
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        let devices = paired.map { device -> BluetoothDevice in
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
            let addr = (device.addressString ?? "").lowercased().replacingOccurrences(of: "-", with: ":")
            let name = device.nameOrAddress ?? "Unknown"
            let info = btBatteryCache[addr]
            let earbud: Int? = info.flatMap { i in [i.left, i.right].compactMap { $0 }.min() }
            let primary: Int? = info?.main ?? earbud ?? bleBatteryByName[name]
            return BluetoothDevice(
                id: device.addressString ?? UUID().uuidString,
                name: name,
                isConnected: device.isConnected(),
                batteryPercent: primary,
                batteryLeft: info?.left,
                batteryRight: info?.right,
                batteryCase: info?.caseLevel,
                icon: icon
            )
        }
        onDevices?(devices)
    }

    private func refreshBTBatteryCache() {
        let now = Date()
        guard now.timeIntervalSince(btBatteryCacheDate) > 25 else { return }
        btBatteryCacheDate = now
        // BLE GATT battery read (runs alongside system_profiler parse)
        let reader = BLEBatteryReader()
        bleBatteryReader = reader
        reader.onResult = { [weak self] name, pct in
            self?.bleBatteryByName[name] = pct
        }
        reader.read()
        Task.detached(priority: .utility) { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            proc.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return }
            // Read before waiting. system_profiler's output is small enough
            // today that the other order happens to work, but a process that
            // fills the pipe buffer blocks writing while we wait for it to
            // exit, and nothing would ever break the tie.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard let captured = BTDeviceParser.parse(data) else { return }
            await MainActor.run { [weak self] in self?.btBatteryCache = captured }
        }
    }
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

// Reads GATT Battery Service (0x180F) from BLE peripherals already connected to the system.
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let batterySvc  = CBUUID(string: "180F")
    private static let batteryChar = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var inFlight: Set<CBPeripheral> = []
    var onResult: ((String, Int) -> Void)?   // peripheral.name → percent

    func read() {
        // Re-create central each time so state machine resets cleanly
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        let peripherals = central.retrieveConnectedPeripherals(withServices: [Self.batterySvc])
        for p in peripherals {
            p.delegate = self
            inFlight.insert(p)
            central.connect(p, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batterySvc])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        inFlight.remove(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { inFlight.remove(peripheral); return }
        for svc in services where svc.uuid == Self.batterySvc {
            peripheral.discoverCharacteristics([Self.batteryChar], for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { inFlight.remove(peripheral); return }
        for c in chars where c.uuid == Self.batteryChar {
            peripheral.readValue(for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { inFlight.remove(peripheral); central?.cancelPeripheralConnection(peripheral) }
        guard characteristic.uuid == Self.batteryChar,
              let data = characteristic.value, let raw = data.first,
              let name = peripheral.name else { return }
        let pct = Int(raw)
        guard pct >= 0, pct <= 100 else { return }
        onResult?(name, pct)
    }
}

import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// MARK: - Bluetooth

struct BluetoothDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(String(localized: "Bluetooth"), systemImage: "dot.radiowaves.left.and.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                InfoButton(text: String(localized: "Paired devices are read from the IOBluetooth framework — all devices you have ever paired, whether connected or not.\n\nBattery percentage is read from the IOHIDDevice registry for devices that expose it (Apple peripherals: AirPods, Magic Mouse, Magic Keyboard, etc.). Third-party peripherals may not expose battery data."))
            }

            if engine.bluetoothAuthState != .allowedAlways {
                SectionCard {
                    let isDenied = engine.bluetoothAuthState == .denied || engine.bluetoothAuthState == .restricted
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.largeTitle).foregroundStyle(.blue)
                        Text(String(localized: "Bluetooth Access Required"))
                            .font(.subheadline.weight(.semibold))
                        Text(isDenied
                             ? String(localized: "Access was denied. Go to System Settings → Privacy & Security → Bluetooth to enable it.")
                             : String(localized: "Allow Performance Monitor to read your paired Bluetooth devices."))
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if isDenied {
                            Button(String(localized: "Open Privacy Settings")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.regular)
                        } else {
                            Button(String(localized: "Grant Bluetooth Access")) { engine.requestBluetoothAccess() }
                                .buttonStyle(.borderedProminent).controlSize(.regular)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        let connected = engine.bluetoothDevices.filter { $0.isConnected }
                        let disconnected = engine.bluetoothDevices.filter { !$0.isConnected }

                        if engine.bluetoothDevices.isEmpty {
                            Text(String(localized: "No paired devices found."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            if !connected.isEmpty {
                                Text(String(localized: "Connected")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(connected) { device in
                                    BluetoothDeviceRow(device: device)
                                }
                            }
                            if !disconnected.isEmpty {
                                if !connected.isEmpty { Divider() }
                                Text(String(localized: "Not connected")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(disconnected) { device in
                                    BluetoothDeviceRow(device: device)
                                }
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }
}

struct BluetoothDeviceRow: View {
    let device: BluetoothDevice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.icon)
                .font(.system(size: 13))
                .foregroundStyle(device.isConnected ? .blue : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(device.name).font(.caption).lineLimit(1)
                .accessibilityValue(device.isConnected ? String(localized: "connected") : String(localized: "not connected"))
            Spacer()
            if device.batteryLeft != nil || device.batteryRight != nil || device.batteryCase != nil {
                HStack(spacing: 4) {
                    if let l = device.batteryLeft  { EarbudBatteryPill("L", l) }
                    if let r = device.batteryRight { EarbudBatteryPill("R", r) }
                    if let c = device.batteryCase  { EarbudBatteryPill(String(localized: "Case"), c) }
                }
            } else if let pct = device.batteryPercent {
                HStack(spacing: 3) {
                    Image(systemName: batterySystemImage(pct)).font(.caption2)
                    Text(String(format: "%ld%%", pct)).font(.caption.monospacedDigit())
                }
                .foregroundStyle(pct < 20 ? .red : .secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Battery"))
                .accessibilityValue(pct < 20 ? String(format: String(localized: "%ld percent, low"), pct) : String(format: String(localized: "%ld percent"), pct))
            }
            if !device.isConnected {
                Circle().fill(Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
    }

}

import Foundation

// Plain value types describing metric snapshots the engine produces and the
// views render. Extracted from MetricsEngine.swift in the Part-A decomposition.
// `LocalInterface` lives in PerformanceAppCore (pure, unit-tested); these
// remain app-level as they are simple data holders consumed only by the UI.

struct DisplayInfo: Identifiable {
    let id: Int
    let name: String
    let width: Int
    let height: Int
    let refreshRateHz: Int
    let scaleFactor: Double
    let isMain: Bool
    let isBuiltIn: Bool
    var colorProfile: String = ""
    var trueTone: Bool = false
    var connectionType: String = ""
}

struct VolumeInfo: Identifiable {
    let name: String
    let totalGB: Double
    let freeGB: Double
    let isRemovable: Bool
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
    let batteryPercent: Int?    // primary / overall; for earbuds = min(L, R)
    let batteryLeft: Int?       // AirPods left earbud
    let batteryRight: Int?      // AirPods right earbud
    let batteryCase: Int?       // AirPods case
    let icon: String
}

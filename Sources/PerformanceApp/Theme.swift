import SwiftUI
import Foundation

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    var color: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}

enum MetricTheme {
    static let cpu = Color.blue
    static let memory = Color.purple
    static let networkDown = Color.green
    static let networkUp = Color.orange
    static let disk = Color.indigo
    static let temperature = Color.red
    static let gpu = Color.cyan
    static let battery = Color.green

    static func color(for kind: DetailWindow.Kind) -> Color {
        switch kind {
        case .cpu: return cpu
        case .memory: return memory
        case .network: return networkDown
        case .disk: return disk
        case .gpu: return gpu
        case .battery: return battery
        case .bluetooth: return .blue
        }
    }

    static func icon(for kind: DetailWindow.Kind) -> String {
        switch kind {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .gpu: return "cube.transparent"
        case .battery: return "battery.100percent"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        }
    }
}

import SwiftUI

// UI-domain types for the extra menu-bar item and app-wide appearance.
// Extracted from MetricsEngine.swift in the Part-A decomposition. These keep
// SwiftUI (Color / Transferable) dependencies, so they stay in the app module
// rather than PerformanceAppCore.

enum MenuBarMetric: String, CaseIterable, Identifiable, Codable, Transferable {
    case cpu = "CPU"
    case memory = "Memory"
    case network = "Network"
    case disk = "Disk"
    case gpu = "GPU"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .cpu:     return "cpu"
        case .memory:  return "memorychip"
        case .network: return "network"
        case .disk:    return "internaldrive"
        case .gpu:     return "rectangle.3.group"
        }
    }
    var color: Color {
        switch self {
        case .cpu:     return MetricTheme.cpu
        case .memory:  return MetricTheme.memory
        case .network: return MetricTheme.networkDown
        case .disk:    return MetricTheme.disk
        case .gpu:     return MetricTheme.gpu
        }
    }
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.rawValue) { MenuBarMetric(rawValue: $0) ?? .cpu }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case sparkline = "Sparkline"
    case text      = "Text only"
    var id: String { rawValue }
}

struct MenuBarConfig {
    var enabled: Bool
    var style: MenuBarStyle
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
}

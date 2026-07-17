import SwiftUI
import Foundation
import AppKit

extension NSApplication {
    // NSApp.windows always includes internal plumbing windows (NSStatusBarWindow
    // for each status item, the shared NSPopover's window, MenuBarExtra's hidden
    // anchor window) that report isVisible == true even when nothing user-facing
    // is on screen. Naively checking isVisible alone means "is another window
    // still open" is always true, so the accessory activation policy never gets
    // restored. Only standard titled windows (Settings, detail windows) count.
    func hasOtherVisibleTitledWindow(besides excluded: NSWindow) -> Bool {
        windows.contains {
            $0 !== excluded && $0.isVisible && $0.styleMask.contains(.titled)
        }
    }
}

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
    static let cpu         = Color.blue
    static let memory      = Color.purple
    static let networkDown = Color.green
    static let networkUp   = Color.orange
    static let disk        = Color.indigo
    static let temperature = Color.red
    static let gpu         = Color.cyan
    static let battery     = Color.green

    // Temperature colour thresholds vary by sensor category (CPU runs hotter than battery).
    static func sensorTempColor(_ celsius: Double, category: String) -> Color {
        switch category {
        case "CPU", "GPU":
            return celsius < 60 ? .green : celsius < 75 ? .yellow : celsius < 90 ? .orange : .red
        case "Battery":
            return celsius < 35 ? .green : celsius < 45 ? .yellow : celsius < 55 ? .orange : .red
        default:
            return celsius < 40 ? .green : celsius < 55 ? .yellow : celsius < 70 ? .orange : .red
        }
    }
}

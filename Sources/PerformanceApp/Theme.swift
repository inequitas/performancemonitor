import SwiftUI
import Foundation
import AppKit
import PerformanceAppCore

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
        switch TempSeverityMapper.severity(celsius: celsius, category: category) {
        case .normal:   return .green
        case .warning:  return .yellow
        case .elevated: return .orange
        case .critical: return .red
        }
    }

    // Word form of the same severity bucket `sensorTempColor` renders as a colour,
    // so VoiceOver / colour-blind users get the same signal as the colour conveys.
    static func sensorTempSeverityWord(_ celsius: Double, category: String) -> String {
        switch TempSeverityMapper.severity(celsius: celsius, category: category) {
        case .normal:   return "normal"
        case .warning:  return "warning"
        case .elevated: return "elevated"
        case .critical: return "critical"
        }
    }
}

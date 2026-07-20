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
    // Display-only localized label. `rawValue` stays the fixed English form
    // used for persistence (UserDefaults) and must never be localized.
    var displayName: String {
        switch self {
        case .cpu:     return String(localized: "CPU")
        case .memory:  return String(localized: "Memory")
        case .network: return String(localized: "Network")
        case .disk:    return String(localized: "Disk")
        case .gpu:     return String(localized: "GPU")
        }
    }
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
    var displayName: String {
        switch self {
        case .sparkline: return String(localized: "Sparkline")
        case .text:      return String(localized: "Text only")
        }
    }
}

struct MenuBarConfig {
    var enabled: Bool
    var style: MenuBarStyle
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light:  return String(localized: "Light")
        case .dark:   return String(localized: "Dark")
        }
    }
}

/// UI language override. `rawValue` doubles as the language code written to
/// the `AppleLanguages` UserDefaults key (except `.system`, which removes
/// that key so macOS falls back to its normal language resolution).
///
/// Per-language display names are deliberately NOT localized — each name is
/// shown in its own language regardless of the app's current UI language,
/// same convention as e.g. the language picker in System Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case en     = "en"
    case nl     = "nl"
    case de     = "de"
    case fr     = "fr"
    case es     = "es"
    case zhHans = "zh-Hans"
    case ja     = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .en:     return "English"
        case .nl:     return "Nederlands"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        case .es:     return "Español"
        case .zhHans: return "简体中文"
        case .ja:     return "日本語"
        }
    }
}

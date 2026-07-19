import Foundation
import SwiftUI
import AppKit

/// Owns all user preferences: the persisted @Published values, their
/// UserDefaults writers, and the load-on-launch logic. Extracted from
/// MetricsEngine so the data engine no longer carries preference persistence
/// or app-level appearance / activation-policy manipulation.
///
/// Behaviour-preserving: every UserDefaults key string is identical to the
/// original engine implementation, and the didSet writers fire on the same
/// property changes. Preference changes that require engine-side action
/// (restarting the sample timer, restarting the ping timer, fetching/clearing
/// the public IP) are surfaced through the `on…Changed` callbacks, which the
/// engine wires up in its initializer.
@MainActor
final class SettingsStore: ObservableObject {

    // MARK: - Engine side-effect hooks (set by MetricsEngine)

    /// Fired when `refreshInterval` changes (engine restarts its sample timer).
    var onRefreshIntervalChanged: (() -> Void)?
    /// Fired when `pingServer` changes (engine clears ping history + restarts).
    var onPingServerChanged: (() -> Void)?
    /// Fired when `publicIPEnabled` changes (engine fetches or clears the IP).
    var onPublicIPEnabledChanged: ((Bool) -> Void)?

    /// Guards the load path so setting a property from stored defaults neither
    /// re-writes UserDefaults nor triggers the engine side-effect callbacks.
    private var isLoadingPreferences = false

    // MARK: - Preferences

    @Published var showInDock: Bool = true {
        didSet {
            guard !isLoadingPreferences else { return }
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            UserDefaults.standard.set(showInDock, forKey: Pref.showInDock)
        }
    }

    @Published var refreshInterval: Double = 1.0 {
        didSet {
            guard !isLoadingPreferences else { return }
            onRefreshIntervalChanged?()
            UserDefaults.standard.set(refreshInterval, forKey: Pref.refreshInterval)
        }
    }

    @Published var topProcessCount: Int = 6 {
        didSet { UserDefaults.standard.set(topProcessCount, forKey: Pref.topProcessCount) }
    }

    @Published var showRemovableVolumes: Bool = true {
        didSet { UserDefaults.standard.set(showRemovableVolumes, forKey: Pref.showRemovableVolumes) }
    }

    @Published var persistHistoryEnabled: Bool = false {
        didSet { UserDefaults.standard.set(persistHistoryEnabled, forKey: Pref.persistHistoryEnabled) }
    }

    @Published var publicIPEnabled: Bool = true {
        didSet {
            guard !isLoadingPreferences else { return }
            onPublicIPEnabledChanged?(publicIPEnabled)
            UserDefaults.standard.set(publicIPEnabled, forKey: Pref.publicIPEnabled)
        }
    }

    @Published var pingServer: MetricsEngine.PingServer = .apple {
        didSet {
            guard !isLoadingPreferences else { return }
            UserDefaults.standard.set(pingServer.rawValue, forKey: Pref.pingServer)
            onPingServerChanged?()
        }
    }

    @Published var appAppearance: AppAppearance = .system {
        didSet {
            guard !isLoadingPreferences else { return }
            UserDefaults.standard.set(appAppearance.rawValue, forKey: "appAppearance")
            applyAppearance()
        }
    }

    // Single source of truth for all per-metric menu bar config.
    // CPU on/sparkline by default; all others off.
    @Published var menuBarConfig: [MenuBarMetric: MenuBarConfig] = {
        Dictionary(uniqueKeysWithValues: MenuBarMetric.allCases.map {
            ($0, MenuBarConfig(enabled: $0 == .cpu, style: .sparkline))
        })
    }()

    @Published var menuBarOrder: [MenuBarMetric] = MenuBarMetric.allCases {
        didSet { UserDefaults.standard.set(menuBarOrder.map(\.rawValue), forKey: "menuBarOrder") }
    }

    @Published var diskDisplayMode: MetricsEngine.DiskDisplayMode = .io {
        didSet { UserDefaults.standard.set(diskDisplayMode.rawValue, forKey: "diskDisplayMode") }
    }

    @Published var networkSparklineUpload: Bool = false {
        didSet { UserDefaults.standard.set(networkSparklineUpload, forKey: "networkSparklineUpload") }
    }

    @Published var diskSparklineWrite: Bool = false {
        didSet { UserDefaults.standard.set(diskSparklineWrite, forKey: "diskSparklineWrite") }
    }

    @Published var panelOrder: [MetricsEngine.Panel] = MetricsEngine.Panel.allCases {
        didSet { UserDefaults.standard.set(panelOrder.map(\.rawValue), forKey: Pref.panelOrder) }
    }

    @Published var hiddenPanels: Set<MetricsEngine.Panel> = [] {
        didSet { UserDefaults.standard.set(Array(hiddenPanels).map(\.rawValue), forKey: Pref.hiddenPanels) }
    }

    // MARK: - Menu bar config helpers

    func isEnabled(_ metric: MenuBarMetric) -> Bool { menuBarConfig[metric]?.enabled ?? false }
    func styleFor(_ metric: MenuBarMetric) -> MenuBarStyle { menuBarConfig[metric]?.style ?? .sparkline }

    func setEnabled(_ enabled: Bool, for metric: MenuBarMetric) {
        menuBarConfig[metric, default: MenuBarConfig(enabled: false, style: .sparkline)].enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "extraBar.\(metric.rawValue.lowercased())")
    }
    func setStyle(_ style: MenuBarStyle, for metric: MenuBarMetric) {
        menuBarConfig[metric, default: MenuBarConfig(enabled: false, style: .sparkline)].style = style
        UserDefaults.standard.set(style.rawValue, forKey: "extraStyle.\(metric.rawValue.lowercased())")
    }

    // MARK: - Appearance

    func applyAppearance() {
        NSApp.appearance = switch appAppearance {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appAppearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    // MARK: - Persistence

    private enum Pref {
        static let showInDock               = "showInDock"
        static let refreshInterval          = "refreshInterval"
        static let topProcessCount          = "topProcessCount"
        static let showRemovableVolumes     = "showRemovableVolumes"
        static let persistHistoryEnabled    = "persistHistoryEnabled"
        static let publicIPEnabled          = "publicIPEnabled"
        static let menuBarMetric            = "menuBarMetric"
        static let menuBarStyle             = "menuBarStyle"
        static let panelOrder               = "panelOrder"
        static let hiddenPanels             = "hiddenPanels"
        static let pingServer               = "pingServer"
    }

    init() {
        loadPreferences()
    }

    private func loadPreferences() {
        isLoadingPreferences = true
        defer {
            isLoadingPreferences = false
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            applyAppearance()
        }
        let ud = UserDefaults.standard
        func bool(_ k: String) -> Bool?   { ud.object(forKey: k) != nil ? ud.bool(forKey: k) : nil }
        func dbl(_ k: String)  -> Double? { ud.object(forKey: k) != nil ? ud.double(forKey: k) : nil }
        func int_(_ k: String) -> Int?    { ud.object(forKey: k) != nil ? ud.integer(forKey: k) : nil }

        if let v = bool(Pref.showInDock)               { showInDock = v }
        if let v = bool(Pref.publicIPEnabled)           { publicIPEnabled = v }
        if let v = bool(Pref.showRemovableVolumes)      { showRemovableVolumes = v }
        if let v = bool(Pref.persistHistoryEnabled)     { persistHistoryEnabled = v }
        if let v = dbl(Pref.refreshInterval)            { refreshInterval = v }
        if let v = int_(Pref.topProcessCount)           { topProcessCount = v }
        if let v = ud.string(forKey: Pref.pingServer)     { pingServer = MetricsEngine.PingServer(rawValue: v) ?? .apple }
        if let raw = ud.stringArray(forKey: "menuBarOrder") {
            let loaded = raw.compactMap { MenuBarMetric(rawValue: $0) }
            let missing = MenuBarMetric.allCases.filter { !loaded.contains($0) }
            menuBarOrder = loaded + missing
        }
        if let dm = MetricsEngine.DiskDisplayMode(rawValue: ud.string(forKey: "diskDisplayMode") ?? "") {
            diskDisplayMode = dm
        }
        if let a = AppAppearance(rawValue: ud.string(forKey: "appAppearance") ?? "") {
            appAppearance = a
        }
        networkSparklineUpload = ud.bool(forKey: "networkSparklineUpload")
        diskSparklineWrite     = ud.bool(forKey: "diskSparklineWrite")

        if let raw = ud.stringArray(forKey: Pref.panelOrder) {
            let loaded = raw.compactMap { MetricsEngine.Panel(rawValue: $0) }
            let missing = MetricsEngine.Panel.allCases.filter { !loaded.contains($0) }
            panelOrder = loaded + missing
        }
        if let raw = ud.stringArray(forKey: Pref.hiddenPanels) {
            hiddenPanels = Set(raw.compactMap { MetricsEngine.Panel(rawValue: $0) })
        }
        for metric in MenuBarMetric.allCases {
            let key = metric.rawValue.lowercased()
            let enabled = ud.object(forKey: "extraBar.\(key)") != nil ? ud.bool(forKey: "extraBar.\(key)") : (metric == .cpu)
            let style   = MenuBarStyle(rawValue: ud.string(forKey: "extraStyle.\(key)") ?? "") ?? .sparkline
            menuBarConfig[metric] = MenuBarConfig(enabled: enabled, style: style)
        }
    }
}

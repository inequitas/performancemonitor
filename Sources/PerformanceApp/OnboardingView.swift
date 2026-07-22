import SwiftUI
import AppKit
import ServiceManagement

/// Decides whether the first-run welcome window should appear, and records
/// that it has been shown (or that it can be skipped) so it never appears
/// twice for the same user.
enum OnboardingGate {
    private static let hasCompletedKey = "hasCompletedOnboarding"

    /// Preference keys that only ever get written once a user has actually
    /// touched a setting. Their presence means this is not a fresh install,
    /// even if `hasCompletedOnboarding` itself predates this app version.
    private static let existingUserSignalKeys = [
        "panelOrder", "showInDock", "menuBarOrder", "refreshInterval"
    ]

    static func shouldShowOnboarding() -> Bool {
        let ud = UserDefaults.standard
        if ud.bool(forKey: hasCompletedKey) { return false }
        if existingUserSignalKeys.contains(where: { ud.object(forKey: $0) != nil }) {
            // Existing user from before onboarding existed — skip silently,
            // no need to show them a "welcome" window for an app they already use.
            ud.set(true, forKey: hasCompletedKey)
            return false
        }
        return true
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: hasCompletedKey)
    }
}

/// Small, single-page welcome window shown once on first launch. Explains
/// where the app lives, its core features, why it asks for Bluetooth and
/// notification permissions, and offers the Launch at Login toggle up front.
struct OnboardingView: View {
    let engine: MetricsEngine
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Welcome to Performance Monitor"))
                    .font(.title2.weight(.semibold))
                Text(String(localized: "This app lives in your menu bar, not the Dock. Look for its icon — CPU, memory, and more — next to the clock at the top of your screen."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "rectangle.stack.fill", color: .blue,
                           text: String(localized: "Click the menu bar icon for a quick overview of CPU, memory, network, disk, and more"))
                featureRow(icon: "macwindow", color: .indigo,
                           text: String(localized: "Open any card for a detailed window with history charts and process breakdowns"))
                featureRow(icon: "menubar.rectangle", color: .purple,
                           text: String(localized: "Choose which metrics show in the menu bar, and whether as text or a live graph"))
                featureRow(icon: "bell.badge.fill", color: .orange,
                           text: String(localized: "Get notified when CPU, memory, disk space, or temperature cross a threshold you set"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "About permissions"), systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "Performance Monitor will ask for Bluetooth access to show your paired devices and their battery levels, and for notification access to deliver the alerts above. Both are optional — the rest of the app works fully without them."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Label(String(localized: "Launch at login"), systemImage: "power")
                    .font(.callout)
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            .padding(.vertical, 2)

            HStack {
                Spacer()
                Button(String(localized: "Get Started")) {
                    OnboardingGate.markCompleted()
                    dismissWindow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial)
        .background(OnboardingWindowAccessor(settings: engine.settings))
        .preferredColorScheme(engine.settings.preferredColorScheme)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.18)).frame(width: 24, height: 24)
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            }
            Text(text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Mirrors SettingsView's WindowFocuser: brings the window forward, keeps the
// Dock icon visible while it's open, and restores the accessory activation
// policy on close (if Show in Dock is off). Also guarantees the "shown once"
// flag is set even if the window is closed via the titlebar instead of the
// "Get Started" button.
private struct OnboardingWindowAccessor: NSViewRepresentable {
    let settings: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.styleMask.remove(.resizable)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak settings] _ in
                Task { @MainActor in
                    OnboardingGate.markCompleted()
                    guard let settings, !settings.showInDock else { return }
                    if !NSApp.hasOtherVisibleTitledWindow(besides: window) {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

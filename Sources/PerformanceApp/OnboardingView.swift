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

/// First-run guided tour: a fixed-size, 5-step paged wizard that explains the
/// app and lets the user set it up as they go (menu-bar metrics, popover,
/// optional alerts, permissions + launch-at-login). Also reachable later from
/// the About tab's "Show the welcome tour again" row — the tour itself doesn't
/// need to know whether it's a first run or a re-open.
struct OnboardingView: View {
    let engine: MetricsEngine
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step = 0
    @State private var direction = 1
    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(current: step, total: stepCount)
                .padding(.top, 18)
                .padding(.bottom, 10)

            Divider()

            // Each step is its own small view; the wizard is a plain switch.
            // `.id(step)` makes SwiftUI treat every step as a distinct view so
            // the asymmetric transition below actually plays instead of the
            // content just cross-fading in place.
            // The clip has to sit on a stable parent rather than on the
            // transitioning view: `.clipped()` applied to the step itself would
            // only clip it to its own bounds, which move with the slide. This
            // fixed container is what keeps a sliding step inside the content
            // band.
            ZStack(alignment: .topLeading) {
                Group {
                    switch step {
                    case 0:  WelcomeStep()
                    case 1:  MenuBarStep(engine: engine, settings: engine.settings)
                    case 2:  PopoverStep(engine: engine)
                    case 3:  AlertsStep(alerts: engine.alerts)
                    default: PermissionsStep()
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()

            bottomBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 460, height: 520)
        .background(.regularMaterial)
        .background(OnboardingWindowAccessor(settings: engine.settings))
        .preferredColorScheme(engine.settings.preferredColorScheme)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            // "Skip" abandons the whole tour (steps 1-4 only); marks it done so
            // it never reappears automatically.
            if step < stepCount - 1 {
                Button(String(localized: "Skip")) { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            if step > 0 {
                Button(String(localized: "Back")) {
                    direction = -1
                    withAnimation(.easeInOut(duration: 0.28)) { step -= 1 }
                }
            }

            if step < stepCount - 1 {
                Button(String(localized: "Next")) {
                    direction = 1
                    withAnimation(.easeInOut(duration: 0.28)) { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(String(localized: "Get Started")) { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish() {
        OnboardingGate.markCompleted()
        dismissWindow()
    }
}

// MARK: - Chrome

/// Thin progress indicator: one dot per step, the current one filled/enlarged.
private struct ProgressDots: View {
    let current: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 18 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: current)
    }
}

/// Shared title + one-line subtitle for a step.
private struct StepHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
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

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Subtle static hint pointing up toward the menu bar.
            HStack(spacing: 6) {
                Image(systemName: "arrow.up").font(.caption.weight(.bold))
                Text(String(localized: "It lives up here, in your menu bar."))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Welcome to Performance Monitor"))
                        .font(.title2.weight(.semibold))
                    Text(String(localized: "This app lives in your menu bar, not the Dock. Look for its icon — CPU, memory, and more — next to the clock at the top of your screen."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step 2: Menu bar metrics + live preview

private struct MenuBarStep: View {
    let engine: MetricsEngine
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: String(localized: "What shows in your menu bar?"),
                       subtitle: String(localized: "Pick the metrics you want to see. You can fine-tune these anytime in Settings."))

            VStack(spacing: 0) {
                ForEach(Array(settings.menuBarOrder.enumerated()), id: \.element) { i, metric in
                    if i > 0 { Divider() }
                    metricToggle(metric)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Text(String(localized: "Live preview"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            MenuBarPreview(engine: engine, settings: settings)

            Spacer(minLength: 0)
        }
    }

    private func metricToggle(_ metric: MenuBarMetric) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(metric.color.opacity(0.15)).frame(width: 24, height: 24)
                Image(systemName: metric.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(metric.color)
                    .symbolEffectsRemoved()
            }
            .transaction { $0.animation = nil }
            Text(metric.displayName).font(.callout)
            Spacer()
            // While enabled, offer the same Text/Graph choice as the Menu Bar
            // settings tab (reusing styleFor/setStyle). Disk in Space mode is
            // always drawn as text, so the picker is hidden there — matching
            // the settings tab and what the live preview shows.
            if settings.isEnabled(metric),
               !(metric == .disk && settings.diskDisplayMode == .space) {
                Picker("", selection: Binding(
                    get: { settings.styleFor(metric) },
                    set: { settings.setStyle($0, for: metric) }
                )) {
                    Text(String(localized: "Text")).tag(MenuBarStyle.text)
                    Text(String(localized: "Graph")).tag(MenuBarStyle.sparkline)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 96)
                .transaction { $0.animation = nil }
            }
            Toggle("", isOn: Binding(
                get: { settings.isEnabled(metric) },
                set: { settings.setEnabled($0, for: metric) }
            )).labelsHidden()
        }
    }
}

/// Live mini menu bar. Renders each enabled metric with the very same
/// `MenuBarRenderer` code that draws the real status items, so the preview is
/// pixel-for-pixel what the user will actually see. Only redraws while this
/// view is on screen (i.e. the tour window is open on this step), so it costs
/// nothing when the window is closed.
private struct MenuBarPreview: View {
    @ObservedObject var engine: MetricsEngine
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let enabled = settings.menuBarOrder.filter { settings.isEnabled($0) }
        HStack(spacing: 8) {
            if enabled.isEmpty {
                Text(String(localized: "Nothing selected — pick at least one metric above."))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                // On-screen order matches the real menu bar: the topmost metric
                // in the order ends up rightmost, so draw the list reversed.
                ForEach(enabled.reversed()) { metric in
                    Image(nsImage: previewImage(for: metric))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
        // This redraws every metrics tick (~1/second) with fresh live images;
        // animating those transitions would jitter, so suppress locally now
        // that the root-level blanket suppression is gone (it would otherwise
        // have killed the new step-slide transition too).
        .transaction { $0.animation = nil }
    }

    private func previewImage(for metric: MenuBarMetric) -> NSImage {
        let severity = settings.menuBarThresholdColor ? engine.thresholdStatus(for: metric).severity : .normal
        let isDiskSpace = (metric == .disk && settings.diskDisplayMode == .space)
        let effectiveStyle: MenuBarStyle = isDiskSpace ? .text : settings.styleFor(metric)
        let image = MenuBarRenderer.image(
            metric: metric,
            effectiveStyle: effectiveStyle,
            text: engine.textOnlyLabel(for: metric),
            sparkText: engine.sparklineText(for: metric),
            history: engine.sparklineHistory(for: metric),
            severity: severity,
            isDiskSpace: isDiskSpace
        )
        image.isTemplate = false
        return image
    }
}

// MARK: - Step 3: The popover

private struct PopoverStep: View {
    let engine: MetricsEngine
    @State private var couldntOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: String(localized: "Your at-a-glance overview"),
                       subtitle: String(localized: "One click on the menu bar icon opens a compact overview of everything at once."))

            Button {
                couldntOpen = !engine.showMenuBarPopover()
            } label: {
                Label(String(localized: "Open the overview"), systemImage: "rectangle.stack.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if couldntOpen {
                Text(String(localized: "Couldn't open it automatically — click the app's icon in your menu bar to see it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(String(localized: "Click any card for a detailed window."), systemImage: "macwindow")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step 4: Alerts (optional)

private struct AlertsStep: View {
    @ObservedObject var alerts: AlertService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: String(localized: "Get a heads-up (optional)"),
                       subtitle: String(localized: "Optionally get a notification when something needs your attention. You can skip this entirely."))

            Toggle(isOn: $alerts.alertsEnabled) {
                Label(String(localized: "Enable alerts"), systemImage: "bell.badge.fill")
            }
            .toggleStyle(.switch)

            if alerts.alertsEnabled {
                HStack {
                    Text(String(localized: "Notify me when CPU is above"))
                        .font(.callout)
                    Spacer()
                    Stepper(value: $alerts.cpuThreshold, in: 50...100, step: 5) {
                        Text(String(format: "%.0f%%", alerts.cpuThreshold))
                            .font(.callout.monospacedDigit())
                    }
                    .fixedSize()
                }
                .padding(.top, 2)

                Text(String(localized: "Fine-tune memory, disk, GPU and thermal alerts later in Settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step 5: Permissions + launch at login

private struct PermissionsStep: View {
    @State private var launchAtLogin = LaunchAtLoginStatus.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: String(localized: "You're all set"),
                       subtitle: String(localized: "A couple of optional permissions, and you're ready to go."))

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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

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
                            LaunchAtLoginStatus.set(newValue)
                        } catch {
                            launchAtLogin = LaunchAtLoginStatus.refreshed()
                        }
                    }
            }
            .padding(.vertical, 2)

            Spacer(minLength: 0)
        }
    }
}

// Mirrors SettingsView's WindowFocuser: brings the window forward, keeps the
// Dock icon visible while it's open, and restores the accessory activation
// policy on close (if Show in Dock is off). Also guarantees the "shown once"
// flag is set even if the window is closed via the titlebar instead of the
// "Get Started"/"Skip" buttons.
private struct OnboardingWindowAccessor: NSViewRepresentable {
    let settings: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.remove(.resizable)
            // Anchor the window to the top-right, just under the menu bar — near
            // where the app's own status item lives — so the "it lives up here"
            // hint and the upward arrow line up with reality. `visibleFrame`
            // already excludes the menu bar, so its maxY is exactly the top of
            // the usable area. Prefer the screen under the mouse, falling back
            // to the main screen.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                ?? NSScreen.main
            if let vf = screen?.visibleFrame {
                let margin: CGFloat = 8
                let size = window.frame.size
                let x = vf.maxX - size.width - margin
                let y = vf.maxY - size.height - margin
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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

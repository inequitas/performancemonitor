import SwiftUI
import AppKit

/// Owns the long-lived engine and updater without making the App's scene body
/// observe them. `MetricsEngine` publishes ~80 @Published values every second;
/// if the App held it as `@StateObject`, SwiftUI would re-evaluate the entire
/// scene graph (`ViewGraphRootValueUpdater` / `AppBodyAccessor.updateBody`) on
/// every tick, even with every window closed — a measurable idle cost. This
/// container has no @Published of its own, so its `objectWillChange` never
/// fires and the scene body is evaluated once. Open windows still observe the
/// engine directly through their own `@ObservedObject`.
@MainActor
final class AppContainer: ObservableObject {
    let engine = MetricsEngine()
    let updater = UpdateChecker()
}

@main
struct PerformanceApp: App {
    @StateObject private var container = AppContainer()
    private var engine: MetricsEngine { container.engine }
    private var updater: UpdateChecker { container.updater }

    // Invisible 1×1 anchor — keeps the app alive as a menu bar app.
    // All visible icons are managed by ExtraMenuBarController via NSStatusBar.
    private static let anchorImage: NSImage = {
        let img = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        img.isTemplate = false
        return img
    }()

    init() {
        // On-device only: writes crash diagnostics to disk locally, never
        // transmits anything. See CrashReporter.swift.
        CrashReporter.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            MenuBarAnchorLabel(image: Self.anchorImage)
        }

        WindowGroup(id: "detail", for: MetricsEngine.Panel.self) { $kind in
            if let kind {
                DetailWindow(kind: kind, engine: engine)
            }
        }
        .defaultSize(width: detailWindowWidth, height: detailWindowHeight)
        .windowResizability(.contentSize)

        Window("Welcome to Performance Monitor", id: "onboarding") {
            OnboardingView(engine: engine)
        }
        .windowResizability(.contentSize)

        Window(String(localized: "History"), id: "history") {
            HistoryWindow(engine: engine)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(engine: engine, updater: updater)
        }
    }
}

// Invisible anchor's label view. Doubles as the hook for opening the
// one-time onboarding window: SwiftUI's openWindow action is only reachable
// from inside a View's environment, and this label is guaranteed to appear
// exactly once at launch.
private struct MenuBarAnchorLabel: View {
    let image: NSImage
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: image)
            .onAppear {
                guard OnboardingGate.shouldShowOnboarding() else { return }
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
    }
}

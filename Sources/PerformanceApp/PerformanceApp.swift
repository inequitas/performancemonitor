import SwiftUI
import AppKit

@main
struct PerformanceApp: App {
    @StateObject private var engine  = MetricsEngine()
    @StateObject private var updater = UpdateChecker()

    // Invisible 1×1 anchor — keeps the app alive as a menu bar app.
    // All visible icons are managed by ExtraMenuBarController via NSStatusBar.
    private static let anchorImage: NSImage = {
        let img = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }
        img.isTemplate = false
        return img
    }()

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

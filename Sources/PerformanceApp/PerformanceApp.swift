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
            Image(nsImage: Self.anchorImage)
        }

        WindowGroup(id: "detail", for: MetricsEngine.Panel.self) { $kind in
            if let kind {
                DetailWindow(kind: kind, engine: engine)
            }
        }
        .defaultSize(width: detailWindowWidth, height: detailWindowHeight)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(engine: engine, updater: updater)
        }
    }
}

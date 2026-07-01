import SwiftUI

@main
struct PerformanceApp: App {
    @StateObject private var engine = MetricsEngine()

    var body: some Scene {
        MenuBarExtra {
            OverviewView(engine: engine)
        } label: {
            if engine.menuBarStyle == .sparkline {
                Image(nsImage: engine.menuBarImage)
            } else {
                Text(engine.menuBarLabel)
            }
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "detail", for: DetailWindow.Kind.self) { $kind in
            if let kind {
                DetailWindow(kind: kind, engine: engine)
            }
        }
        .defaultSize(width: detailWindowWidth, height: detailWindowHeight)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(engine: engine)
        }
    }
}

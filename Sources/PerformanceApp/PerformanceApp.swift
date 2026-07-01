import SwiftUI

@main
struct PerformanceApp: App {
    @StateObject private var engine = MetricsEngine()

    var body: some Scene {
        MenuBarExtra {
            OverviewView(engine: engine)
        } label: {
            Text(engine.menuBarLabel)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "detail", for: DetailWindow.Kind.self) { $kind in
            if let kind {
                DetailWindow(kind: kind, engine: engine)
            }
        }
        .defaultSize(width: 420, height: 540)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(engine: engine)
        }
    }
}

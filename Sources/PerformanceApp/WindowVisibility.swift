import SwiftUI
import AppKit

/// Reports a window's real on-screen visibility into a binding, so a scene can
/// unmount its content while nobody can see it.
///
/// **Why every window scene needs this.** SwiftUI keeps a scene's view tree
/// alive after its window closes. A tree that observes `MetricsEngine` then
/// keeps re-evaluating its body on every published change — roughly 80 per
/// second — for a window that is not on screen. Measured on 28 Jul for a single
/// detail window: idle CPU went from 1.76% to 4.25% after one open and close,
/// and never came back down. Any `.task` loops in that tree keep running too,
/// which is what made the History window's 10-second reload a permanent cost.
///
/// Visibility is taken from the same two AppKit events that gate the expensive
/// samplers (`MetricsEngine.setPanelVisible`), so the view tree and the
/// sampling gate can never disagree about whether a window is on screen:
/// `didChangeOcclusionState` covers minimising and full occlusion, and
/// `willClose` covers closing.
///
/// The observer tokens are held by the coordinator and removed when the
/// representable goes away. The three hand-rolled copies this replaces all
/// discarded their tokens, so every window open left observers behind for the
/// rest of the process's life.
struct WindowVisibilityAccessor: NSViewRepresentable {
    /// Driven to `true` while the window is on screen, `false` once it is
    /// occluded, minimised or closed.
    @Binding var isVisible: Bool
    /// One-time setup, run as soon as the window exists — window level, content
    /// size, style mask, focus.
    var configure: ((NSWindow) -> Void)?
    /// Runs after `isVisible` changes. Used to gate sampling in the engine.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Runs once when the window closes, after visibility has been set false.
    var onClose: ((NSWindow) -> Void)?

    final class Coordinator {
        var tokens: [NSObjectProtocol] = []
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Captured explicitly: the notification closures outlive this struct
        // value, and a Binding copy keeps working on its own.
        let visibility = $isVisible
        let coordinator = context.coordinator
        let configure = self.configure
        let onVisibilityChange = self.onVisibilityChange
        let onClose = self.onClose

        // The window is not attached yet during makeNSView.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure?(window)

            let apply: (Bool) -> Void = { visible in
                visibility.wrappedValue = visible
                onVisibilityChange?(visible)
            }
            apply(window.occlusionState.contains(.visible))

            let center = NotificationCenter.default
            coordinator.tokens.append(center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { note in
                guard let win = note.object as? NSWindow else { return }
                Task { @MainActor in apply(win.occlusionState.contains(.visible)) }
            })

            coordinator.tokens.append(center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    apply(false)
                    onClose?(window)
                }
            })
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Restores the accessory activation policy when the last titled window closes,
/// so opening a window doesn't pin the Dock icon for the rest of the session.
/// Shared by every scene that can be opened while "Show in Dock" is off.
@MainActor
func restoreAccessoryPolicyIfLastWindow(besides window: NSWindow, settings: SettingsStore?) {
    guard let settings, !settings.showInDock else { return }
    if !NSApp.hasOtherVisibleTitledWindow(besides: window) {
        NSApp.setActivationPolicy(.accessory)
    }
}

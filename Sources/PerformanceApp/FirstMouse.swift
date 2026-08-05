import AppKit
import ObjectiveC

/// Makes a click land where it was aimed, even when the window was not focused.
///
/// When a click arrives in a window that is not active, AppKit asks the view
/// under the pointer whether it wants it. SwiftUI's hosting view says no, so the
/// click is spent bringing the window forward and the control under the cursor
/// never hears about it. Everything then takes two clicks: one to focus, one to
/// act.
///
/// That default exists to stop a stray click in a background window from doing
/// something irreversible. It is the wrong trade here. This app is glanced at
/// from inside whatever you were already doing, so its windows are almost never
/// the active one, and the only destructive control in them asks for
/// confirmation in a separate alert anyway.
///
/// The hosting view belongs to SwiftUI and its class is not public, so it is
/// taken from a window we own rather than named, and the override is installed
/// once per class encountered.
@MainActor
enum FirstMouse {
    private static var patched: Set<ObjectIdentifier> = []

    /// Installs the override for the class backing `window`'s content, if it has
    /// not been installed already. Safe to call on every window, every time.
    static func enable(on window: NSWindow) {
        guard let content = window.contentView else { return }
        install(for: object_getClass(content) ?? type(of: content))
    }

    /// Same, for a popover, whose content is a view controller rather than a
    /// window. The popover is the first thing most people click, so it matters
    /// as much as the windows do.
    static func enable(on popover: NSPopover) {
        guard let content = popover.contentViewController?.viewIfLoaded else { return }
        install(for: object_getClass(content) ?? type(of: content))
    }

    private static func install(for cls: AnyClass) {
        guard patched.insert(ObjectIdentifier(cls)).inserted else { return }
        let selector = #selector(NSView.acceptsFirstMouse(for:))
        let block: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
        let implementation = imp_implementationWithBlock(block)
        // The class inherits the method rather than defining it, so adding is
        // the normal path; replacing is the fallback if a future SwiftUI does
        // define its own.
        if !class_addMethod(cls, selector, implementation, "B@:@"),
           let method = class_getInstanceMethod(cls, selector) {
            method_setImplementation(method, implementation)
        }
    }
}

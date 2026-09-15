import Foundation
import PerformanceAppCore

/// How a finding reads to a person.
///
/// `SystemVerdict` in Core decides what is true; this decides how it is said.
/// The split keeps the rules testable without a running app and keeps the
/// wording next to the rest of the translated interface.
///
/// It lives here rather than on the banner because the banner is not the only
/// thing that says it: the JSON snapshot carries the same sentences, and two
/// copies would drift apart.
@MainActor
enum FindingWording {

    static func sentence(for kind: SystemFinding.Kind) -> String {
        switch kind {
        case let .throttling(serious):
            return serious
                ? String(localized: "Running hot, so macOS is slowing things down to cool off.")
                : String(localized: "Warm enough that macOS has started slowing things down.")

        case let .swapping(gb):
            return String(format: String(localized: "Memory is short, so the Mac is shuffling %.1f GB between memory and disk."), gb)

        case let .busyProcess(name, percent):
            // Through the glossary, so this reads "Spotlight (indexing)" rather
            // than "mds_stores" for the processes worth naming.
            let shown = GlossaryStore.shared.entry(for: name)?.title ?? name
            return String(format: String(localized: "%@ is using %.0f%% of the CPU."), shown, percent)

        case let .busy(percent):
            return String(format: String(localized: "CPU is at %.0f%%, spread across several processes."), percent)

        case let .memoryTight(percent):
            return String(format: String(localized: "Memory is %.0f%% full."), percent)

        case let .diskAlmostFull(freeGB):
            return String(format: String(localized: "Only %.1f GB left on the startup disk."), freeGB)
        }
    }

    /// What the reader can actually do about it. The statement above says
    /// what is happening; without this the line is an observation they can do
    /// nothing with.
    static func advice(for kind: SystemFinding.Kind) -> String {
        switch kind {
        case .throttling:
            return String(localized: "Everything will run slower until it cools down. Check what is driving the heat, and give the machine some air if it is on a soft surface.")

        case .swapping:
            return String(localized: "That shuffling is what makes a Mac feel slow. Quitting apps you are not using will free memory; Top Memory shows which are holding the most.")

        case let .busyProcess(name, _):
            // The glossary already knows what this process is and whether
            // being busy is normal for it, which is exactly the question the
            // reader has.
            if let known = GlossaryStore.shared.entry(for: name) {
                return known.expectedHigh
                    ? String(format: String(localized: "%@ Being busy is normal for this one."), known.description)
                    : known.description
            }
            return String(localized: "If you did not start it and it stays busy while you are doing nothing, it may be stuck. Top CPU lets you quit it.")

        case .busy:
            return String(localized: "No single process is responsible. Top CPU in the CPU window shows how it is divided.")

        case .memoryTight:
            return String(localized: "Not a problem by itself: macOS uses spare memory as cache and frees it when something needs it. It only matters once swap starts growing.")

        case .diskAlmostFull:
            return String(localized: "macOS needs free space to work properly. Emptying the Bin and checking Storage in System Settings is the usual fix.")
        }
    }
}

import Foundation

/// Something that happened to the machine, to be drawn against the history
/// graphs.
///
/// A graph showing a gap, or an hour of high CPU, does not say why. "The lid was
/// shut here" and "this is where it started throttling" turn a shape into an
/// explanation, which is the whole reason to keep history at all.
public struct SystemEvent: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sleep
        case wake(reason: WakeReason)
        /// Thermal throttling started. Recorded by the app as it happens, since
        /// nothing on the system keeps a log of it.
        case throttling
    }

    /// Why the machine woke, as far as it can honestly be told.
    ///
    /// `pmset` gives a driver-level reason like
    /// `smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty`. The recognisable
    /// parts of that are worth translating; the rest is not worth guessing at,
    /// and `unknown` shows no reason rather than inventing one.
    public enum WakeReason: String, Equatable, Sendable, CaseIterable {
        case lid, keyboard, power, network, scheduled, unknown
    }

    public let kind: Kind
    public let date: Date

    public var id: String { "\(date.timeIntervalSince1970)-\(String(describing: kind))" }

    public init(kind: Kind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// Reads sleep and wake events out of `pmset -g log`.
///
/// The log is the only record of this that survives a restart, which is what
/// makes it worth the cost of reading: everything else the app could mark on a
/// graph it would have to have been running to see.
///
/// Pure, so the parsing can be tested against captured output rather than
/// against whatever the machine happened to do.
public enum PMSetLogParser {

    /// Lines look like:
    ///
    ///     2026-08-06 08:08:29 +0200 Wake     Wake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid …
    ///     2026-08-06 08:06:33 +0200 Sleep    Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active …
    ///
    /// `DarkWake` is deliberately skipped. Those are the brief maintenance wakes
    /// macOS performs on its own several times an hour, invisible to whoever
    /// owns the Mac. On the machine this was written against there were 726 of
    /// them against 808 real wakes, which would have buried the events someone
    /// might actually recognise.
    public static func parse(_ output: String, limit: Int = 500) -> [SystemEvent] {
        var events: [SystemEvent] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            // Cheapest possible rejection first: the log is megabytes, and all
            // but a few thousand lines are of no interest.
            guard line.count > 26 else { continue }
            let afterStamp = line.dropFirst(26)
            let kind: SystemEvent.Kind
            if afterStamp.hasPrefix("Sleep") {
                kind = .sleep
            } else if afterStamp.hasPrefix("Wake ") || afterStamp.hasPrefix("Wake\t") {
                kind = .wake(reason: wakeReason(in: String(line)))
            } else {
                continue
            }
            guard let date = timestamp(String(line.prefix(25))) else { continue }
            events.append(SystemEvent(kind: kind, date: date))
        }
        // Newest first, then trimmed: a long-lived machine has thousands of
        // these and only the recent ones can line up with kept history.
        return Array(events.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// `2026-08-06 08:08:29 +0200`
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        // The log is written in the machine's locale-independent form, so
        // parsing must not follow the user's calendar or region.
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func timestamp(_ text: String) -> Date? {
        formatter.date(from: text)
    }

    static func wakeReason(in line: String) -> SystemEvent.WakeReason {
        // Checked in order of how specific each token is. "lid" is unambiguous;
        // HID activity means someone touched the keyboard or trackpad; the rest
        // are the ones worth naming at all.
        let lowered = line.lowercased()
        if lowered.contains(" lid ") || lowered.contains("lid open") { return .lid }
        if lowered.contains("hid activity") || lowered.contains("multi-touch") { return .keyboard }
        if lowered.contains("powerbutton") || lowered.contains("power button") { return .power }
        if lowered.contains("rtc") || lowered.contains("sleepservice") || lowered.contains("maintenance") {
            return .scheduled
        }
        if lowered.contains("wifi") || lowered.contains("ethernet") || lowered.contains("bluetooth") {
            return .network
        }
        return .unknown
    }
}

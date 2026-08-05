import Foundation

/// One thing worth telling the reader about the state of their Mac.
public struct SystemFinding: Equatable, Sendable, Identifiable {
    /// What was found. The associated values are what the wording needs; the
    /// wording itself lives in the app layer, with the rest of the translated
    /// interface.
    public enum Kind: Equatable, Sendable {
        /// Thermal throttling is active.
        case throttling(serious: Bool)
        /// Memory ran out and the machine is paging to disk.
        case swapping(gb: Double)
        /// One process accounts for most of the CPU load.
        case busyProcess(name: String, percent: Double)
        /// CPU is high with no single process to blame.
        case busy(percent: Double)
        /// Memory is nearly full, without swapping yet.
        case memoryTight(percent: Double)
        /// The startup disk is nearly full.
        case diskAlmostFull(freeGB: Double)
    }

    /// How much it matters, which decides both the order and the colour.
    public enum Severity: Int, Comparable, Sendable {
        case notable = 0, warning = 1, serious = 2
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// Which part of the app explains this further, so a row can open the right
    /// window. Deliberately not the app's own Panel type, which Core cannot see.
    public enum Topic: String, Equatable, Sendable {
        case cpu, memory, disk, thermal
    }

    public let kind: Kind
    public let severity: Severity
    public let topic: Topic

    public var id: String { "\(topic.rawValue)-\(severity.rawValue)" }

    public init(kind: Kind, severity: Severity, topic: Topic) {
        self.kind = kind
        self.severity = severity
        self.topic = topic
    }
}

/// Turns the numbers the app already samples into a short list of things worth
/// saying, most serious first.
///
/// The popover shows values and leaves the reader to interpret them, which most
/// people cannot: 78% memory used is fine, 78% with swap growing is not, and
/// nothing on screen says which is happening.
///
/// An earlier version returned only the single most urgent finding. That lost
/// the context that makes a number mean something: being told 3.7 GB has moved
/// to disk is not much use without knowing whether memory is also tight and
/// what is driving it. It now returns everything that applies.
///
/// Pure, and computed from values already published, so it adds no sampling and
/// nothing to the tick.
public enum SystemVerdict {

    /// Everything the rules need, so they can be tested without an engine or a
    /// running Mac.
    public struct Input: Equatable, Sendable {
        public var cpuPercent: Double
        public var memoryUsedGB: Double
        public var memoryTotalGB: Double
        public var swapUsedGB: Double
        public var diskFreeGB: Double
        /// 0 nominal, 1 fair, 2 serious, 3 critical, mirroring
        /// `ProcessInfo.ThermalState` without importing it into Core.
        public var thermalLevel: Int
        /// The busiest process, when one is known.
        public var topProcess: (name: String, percent: Double)?

        public init(cpuPercent: Double,
                    memoryUsedGB: Double,
                    memoryTotalGB: Double,
                    swapUsedGB: Double,
                    diskFreeGB: Double,
                    thermalLevel: Int,
                    topProcess: (name: String, percent: Double)? = nil) {
            self.cpuPercent = cpuPercent
            self.memoryUsedGB = memoryUsedGB
            self.memoryTotalGB = memoryTotalGB
            self.swapUsedGB = swapUsedGB
            self.diskFreeGB = diskFreeGB
            self.thermalLevel = thermalLevel
            self.topProcess = topProcess
        }

        public static func == (a: Input, b: Input) -> Bool {
            a.cpuPercent == b.cpuPercent && a.memoryUsedGB == b.memoryUsedGB
                && a.memoryTotalGB == b.memoryTotalGB && a.swapUsedGB == b.swapUsedGB
                && a.diskFreeGB == b.diskFreeGB && a.thermalLevel == b.thermalLevel
                && a.topProcess?.name == b.topProcess?.name
                && a.topProcess?.percent == b.topProcess?.percent
        }
    }

    /// Thresholds, named so the numbers are not scattered through the logic.
    public enum Threshold {
        /// Below this, swap is the ordinary background amount macOS keeps
        /// around even on an idle machine, and reporting it would be a false
        /// alarm.
        public static let swapGB = 2.0
        public static let memoryPercent = 85.0
        public static let cpuPercent = 80.0
        /// A process must account for most of the load before it is named,
        /// otherwise the sentence blames whatever happens to sort first in a
        /// list where everything is small.
        public static let dominantProcessPercent = 50.0
        public static let diskFreeGB = 10.0
    }

    /// Every finding that applies, most serious first. Empty means nothing is
    /// worth saying, which is the normal state.
    ///
    /// Thermal "fair" is deliberately absent: macOS reports it routinely under
    /// ordinary load, and a line that fires constantly teaches people to ignore
    /// it.
    public static func evaluate(_ input: Input) -> [SystemFinding] {
        var found: [SystemFinding] = []

        if input.thermalLevel >= 2 {
            let serious = input.thermalLevel >= 3
            found.append(SystemFinding(kind: .throttling(serious: serious),
                                       severity: serious ? .serious : .warning,
                                       topic: .thermal))
        }

        if input.swapUsedGB >= Threshold.swapGB {
            found.append(SystemFinding(kind: .swapping(gb: input.swapUsedGB),
                                       severity: .warning,
                                       topic: .memory))
        }

        if input.cpuPercent >= Threshold.cpuPercent {
            if let top = input.topProcess, top.percent >= Threshold.dominantProcessPercent {
                found.append(SystemFinding(kind: .busyProcess(name: top.name, percent: top.percent),
                                           severity: .notable,
                                           topic: .cpu))
            } else {
                found.append(SystemFinding(kind: .busy(percent: input.cpuPercent),
                                           severity: .notable,
                                           topic: .cpu))
            }
        }

        // Reported alongside swapping rather than instead of it: "memory is 94%
        // full and 3.7 GB has moved to disk" is the whole picture, and either
        // half on its own invites the wrong conclusion.
        let memoryPercent = input.memoryTotalGB > 0
            ? input.memoryUsedGB / input.memoryTotalGB * 100
            : 0
        if memoryPercent >= Threshold.memoryPercent {
            found.append(SystemFinding(kind: .memoryTight(percent: memoryPercent),
                                       severity: .notable,
                                       topic: .memory))
        }

        // 0 GB free means not measured yet, not out of space.
        if input.diskFreeGB > 0, input.diskFreeGB < Threshold.diskFreeGB {
            found.append(SystemFinding(kind: .diskAlmostFull(freeGB: input.diskFreeGB),
                                       severity: .warning,
                                       topic: .disk))
        }

        return found.sorted { $0.severity > $1.severity }
    }
}

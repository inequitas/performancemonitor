import Foundation

/// A one-line answer to "is my Mac alright?", derived from values the app has
/// already sampled.
///
/// The rest of the popover shows numbers and asks the reader to interpret them.
/// Most people cannot: 78% memory used is fine, 78% with swap growing is not,
/// and nothing on screen says which of those is happening. This turns the
/// numbers into a sentence.
///
/// Pure, and computed from values the engine already publishes, so it adds no
/// sampling and nothing to the tick.
public enum SystemVerdict: Equatable, Sendable {
    /// Nothing worth mentioning.
    case allQuiet
    /// Thermal throttling is active. Ranked first because it slows everything
    /// down regardless of what the other numbers say.
    case throttling(serious: Bool)
    /// Swap is growing, which means memory ran out and the machine is paging
    /// to disk. Worse than high memory use on its own.
    case swapping(gb: Double)
    /// A single process is using most of the CPU. Carries the name so the
    /// caller can look it up in the glossary.
    case busyProcess(name: String, percent: Double)
    /// CPU is high but no single process explains it.
    case busy(percent: Double)
    /// Memory is nearly full, without swapping yet.
    case memoryTight(percent: Double)
    /// The startup disk is nearly full.
    case diskAlmostFull(freeGB: Double)

    /// Everything the verdict needs, so the rules can be tested without an
    /// engine or a running Mac.
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
        /// around even on an idle machine, and saying anything about it would
        /// be a false alarm.
        public static let swapGB = 2.0
        public static let memoryPercent = 85.0
        public static let cpuPercent = 80.0
        /// A process needs to account for most of the load before it is worth
        /// naming, otherwise the sentence blames whatever happens to be top of
        /// a list where everything is small.
        public static let dominantProcessPercent = 50.0
        public static let diskFreeGB = 10.0
    }

    /// Picks the single most useful thing to say. Deliberately returns one
    /// verdict rather than a list: a line that says three things at once is a
    /// dashboard, and the reader already has one of those above it.
    ///
    /// Order is by how much the condition actually affects the machine, not by
    /// how large the number looks. Throttling comes first because it slows
    /// everything; swapping next because it is memory exhaustion rather than
    /// memory use; then CPU; then the merely tight.
    public static func evaluate(_ input: Input) -> SystemVerdict {
        if input.thermalLevel >= 2 {
            return .throttling(serious: input.thermalLevel >= 3)
        }
        if input.swapUsedGB >= Threshold.swapGB {
            return .swapping(gb: input.swapUsedGB)
        }
        if input.cpuPercent >= Threshold.cpuPercent {
            if let top = input.topProcess, top.percent >= Threshold.dominantProcessPercent {
                return .busyProcess(name: top.name, percent: top.percent)
            }
            return .busy(percent: input.cpuPercent)
        }
        let memoryPercent = input.memoryTotalGB > 0
            ? input.memoryUsedGB / input.memoryTotalGB * 100
            : 0
        if memoryPercent >= Threshold.memoryPercent {
            return .memoryTight(percent: memoryPercent)
        }
        if input.diskFreeGB > 0, input.diskFreeGB < Threshold.diskFreeGB {
            return .diskAlmostFull(freeGB: input.diskFreeGB)
        }
        return .allQuiet
    }

    /// True when the line is worth drawing attention to rather than stating
    /// quietly. Used for colour, not for whether to show anything.
    public var isNoteworthy: Bool {
        if case .allQuiet = self { return false }
        return true
    }
}

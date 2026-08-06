import AppIntents
import Foundation
import PerformanceAppCore

/// Shortcuts actions, so the numbers this app already has can drive automations
/// it has no business containing: cool the machine down before a render, warn
/// when the disk is nearly full, log temperature during a long build.
///
/// Everything here reads values the running app has already sampled. No intent
/// starts a measurement of its own, so none of them can cost idle CPU, and all
/// of them answer instantly.
///
/// Deliberately absent: per-domain power (CPU/GPU/ANE/DRAM watts) and the
/// extended sensor set. Those are only sampled while the Thermal window is open,
/// so an intent would answer with whatever was last on screen, or nothing. An
/// action that is right only sometimes is worse than one that does not exist.

// MARK: - Which value

/// The metrics that are always current, because they are sampled on every tick
/// whether or not a window is open.
enum MonitorMetric: String, AppEnum {
    case cpuUsage, memoryUsed, memoryPercent, swapUsed, diskFree
    case download, upload, battery, cpuTemperature, gpuTemperature

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [MonitorMetric: DisplayRepresentation] = [
        .cpuUsage:       "CPU usage (%)",
        .memoryUsed:     "Memory used (GB)",
        .memoryPercent:  "Memory used (%)",
        .swapUsed:       "Swap used (GB)",
        .diskFree:       "Free disk space (GB)",
        .download:       "Download speed (kB/s)",
        .upload:         "Upload speed (kB/s)",
        .battery:        "Battery level (%)",
        .cpuTemperature: "CPU temperature (°C)",
        .gpuTemperature: "GPU temperature (°C)",
    ]
}

// MARK: - Errors

enum MonitorIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notRunning
    case unavailable(MonitorMetric)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning:
            return "Performance Monitor is not running."
        case .unavailable(.battery):
            return "This Mac has no battery."
        case .unavailable:
            return "That reading is not available on this Mac."
        }
    }
}

// MARK: - Read one value

struct GetMetricIntent: AppIntent {
    static var title: LocalizedStringResource = "Get a system metric"
    static var description = IntentDescription(
        "Reads one live value from Performance Monitor, such as CPU usage or temperature."
    )

    @Parameter(title: "Metric") var metric: MonitorMetric

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$metric)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let engine = MetricsEngine.current else { throw MonitorIntentError.notRunning }

        let value: Double? = {
            switch metric {
            case .cpuUsage:       return engine.cpuUsagePercent
            case .memoryUsed:     return engine.memoryUsedGB
            case .memoryPercent:  return engine.memoryTotalGB > 0
                                       ? engine.memoryUsedGB / engine.memoryTotalGB * 100 : nil
            case .swapUsed:       return engine.swapUsedGB
            case .diskFree:       return engine.diskFreeGB
            case .download:       return engine.downloadSpeedKBps
            case .upload:         return engine.uploadSpeedKBps
            case .battery:        return engine.batteryPercent.map(Double.init)
            case .cpuTemperature: return engine.cpuTemperatureC
            case .gpuTemperature: return engine.gpuTemperatureC
            }
        }()

        guard let value else { throw MonitorIntentError.unavailable(metric) }
        // Rounded to one decimal: the underlying samplers are not more precise
        // than that, and a shortcut showing 41.83333 implies otherwise.
        let rounded = (value * 10).rounded() / 10
        return .result(value: rounded, dialog: IntentDialog(dialog(for: rounded)))
    }

    private func dialog(for value: Double) -> LocalizedStringResource {
        switch metric {
        case .cpuUsage:       return "CPU is at \(value)%."
        case .memoryUsed:     return "\(value) GB of memory in use."
        case .memoryPercent:  return "Memory is \(value)% full."
        case .swapUsed:       return "\(value) GB of swap in use."
        case .diskFree:       return "\(value) GB free on the startup disk."
        case .download:       return "Downloading at \(value) kB/s."
        case .upload:         return "Uploading at \(value) kB/s."
        case .battery:        return "Battery is at \(value)%."
        case .cpuTemperature: return "CPU is at \(value) °C."
        case .gpuTemperature: return "GPU is at \(value) °C."
        }
    }
}

// MARK: - Ask how the Mac is doing

struct GetSystemStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check how this Mac is doing"
    static var description = IntentDescription(
        "Answers in words rather than numbers: what is worth a look right now, and what to do about it."
    )

    /// The same sentences the popover shows, from `FindingWording`, so a
    /// shortcut and the banner can never tell different stories.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let engine = MetricsEngine.current else { throw MonitorIntentError.notRunning }

        let findings = SystemVerdict.evaluate(engine.verdictInput)
        guard !findings.isEmpty else {
            let quiet = String(localized: "Nothing worth a look. All quiet.")
            return .result(value: quiet, dialog: IntentDialog("\(quiet)"))
        }

        let text = findings
            .map { "\(FindingWording.sentence(for: $0.kind)) \(FindingWording.advice(for: $0.kind))" }
            .joined(separator: "\n\n")
        return .result(value: text, dialog: IntentDialog("\(text)"))
    }
}

// MARK: - Ask what is busiest

struct GetBusiestProcessIntent: AppIntent {
    static var title: LocalizedStringResource = "Get the busiest app"
    static var description = IntentDescription(
        "The app using the most CPU right now, with its helper processes counted together."
    )

    /// Opening the CPU window is what starts the process sampler, so this waits
    /// for one sample rather than answering with an empty list. The gate is
    /// released again immediately: the sampler keeps whatever it read, and
    /// nothing stays running for an intent that has finished.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let engine = MetricsEngine.current else { throw MonitorIntentError.notRunning }

        if engine.topCPUProcesses.isEmpty {
            await engine.sampleProcessesOnce()
        }
        guard let top = engine.topCPUProcesses.first else {
            throw MonitorIntentError.unavailable(.cpuUsage)
        }

        let name = GlossaryStore.shared.entry(for: top.name)?.title ?? top.name
        let dialog = String(format: String(localized: "%@ is using %.0f%% of the CPU."), name, top.value)
        return .result(value: name, dialog: IntentDialog("\(dialog)"))
    }
}

// MARK: - Phrases

struct MonitorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetSystemStatusIntent(),
            phrases: ["How is my Mac doing in \(.applicationName)"],
            shortTitle: "How is my Mac doing",
            systemImageName: "stethoscope"
        )
        AppShortcut(
            intent: GetMetricIntent(),
            phrases: ["Get a metric from \(.applicationName)"],
            shortTitle: "Get a metric",
            systemImageName: "gauge.with.needle"
        )
        AppShortcut(
            intent: GetBusiestProcessIntent(),
            phrases: ["What is busiest in \(.applicationName)"],
            shortTitle: "Busiest app",
            systemImageName: "cpu"
        )
    }
}

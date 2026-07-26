// Per-domain power reader — Apple Silicon only.
//
// Reads the IOReport "Energy Model" channel group (CPU/GPU/ANE/DRAM cumulative
// energy counters) via the `CIOReport` C shim, differences successive samples,
// and converts each domain's energy delta to watts with the pure
// `EnergyPower.watts` conversion in PerformanceAppCore.
//
// Nil-safe by construction: on hardware or macOS versions where IOReport, its
// symbols, or the "Energy Model" group are unavailable, `isOpen` is false and
// every read returns an empty snapshot — the feature simply shows nothing.

import Foundation
import PerformanceAppCore
import CIOReport

/// One reading of the per-domain power draw, in watts. Any field is `nil` when
/// its channel is absent on this Mac or no baseline exists yet (first sample).
struct PowerSnapshot {
    let cpuWatts:  Double?
    let gpuWatts:  Double?
    let aneWatts:  Double?
    let dramWatts: Double?

    /// True when at least one domain produced a value — used to decide whether
    /// the UI section has anything to show.
    var hasAny: Bool { cpuWatts != nil || gpuWatts != nil || aneWatts != nil || dramWatts != nil }
}

/// Owns the `CIOReportReader` handle and the previous cumulative sample used to
/// form deltas. `@unchecked Sendable` and only ever touched from the single
/// `PowerSampler` background task, exactly like `SMCReader`.
final class PowerReader: @unchecked Sendable {

    let isOpen: Bool
    private let handle: OpaquePointer?

    // Previous cumulative reading, per domain, for delta computation. Stored as
    // (rawEnergy, unit); reset to nil whenever a domain drops out of a sample.
    private var prev: [Domain: (energy: Int64, unit: EnergyPower.Unit)] = [:]
    private var prevTime: Date?

    private enum Domain: Hashable { case cpu, ecpu, pcpu, gpu, ane, dram }

    init() {
        handle = CIOReportOpen()
        isOpen = handle != nil
    }

    deinit {
        if let handle { CIOReportClose(handle) }
    }

    /// Takes a sample, differences it against the previous one, and returns the
    /// per-domain watts. The first call establishes the baseline and returns an
    /// empty snapshot. Returns an empty snapshot when unavailable.
    func sample() -> PowerSnapshot {
        let empty = PowerSnapshot(cpuWatts: nil, gpuWatts: nil, aneWatts: nil, dramWatts: nil)
        guard let handle else { return empty }

        var s = CIOReportSample()
        guard CIOReportSampleRead(handle, &s), s.valid else { return empty }

        let now = Date()
        let dt = prevTime.map { now.timeIntervalSince($0) } ?? 0
        prevTime = now

        // Combined CPU: prefer a package-level "CPU Energy" channel; otherwise
        // sum the E-core and P-core clusters when both are exposed.
        let cpuWatts: Double? = {
            if let w = watts(for: .cpu, from: s.cpu, dt: dt) { return w }
            let e = watts(for: .ecpu, from: s.ecpu, dt: dt)
            let p = watts(for: .pcpu, from: s.pcpu, dt: dt)
            if e == nil && p == nil { return nil }
            return (e ?? 0) + (p ?? 0)
        }()

        return PowerSnapshot(
            cpuWatts:  cpuWatts,
            gpuWatts:  watts(for: .gpu,  from: s.gpu,  dt: dt),
            aneWatts:  watts(for: .ane,  from: s.ane,  dt: dt),
            dramWatts: watts(for: .dram, from: s.dram, dt: dt)
        )
    }

    /// Differences one domain against its stored previous value and converts to
    /// watts. Updates the stored baseline. Returns nil on the first sample, when
    /// the domain is absent, or when the unit isn't a recognised energy unit.
    private func watts(for domain: Domain, from d: CIOReportDomain, dt: TimeInterval) -> Double? {
        guard d.present else { prev[domain] = nil; return nil }
        let unit = EnergyPower.Unit(rawValue: Int32(d.unit.rawValue)) ?? .unknown
        defer { prev[domain] = (d.energy, unit) }

        guard let previous = prev[domain], previous.unit == unit else { return nil }
        return EnergyPower.watts(energyDelta: d.energy - previous.energy, unit: unit, seconds: dt)
    }
}

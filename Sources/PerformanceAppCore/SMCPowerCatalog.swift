import Foundation

/// Curated map of known SMC power-reporting keys → friendly label.
///
/// Unlike temperature/fan sensors (see `SMCSensorCatalog`), total system
/// power is exposed under a single key that has stayed the same name across
/// Intel and every Apple Silicon generation in third-party SMC tooling
/// (Stats app, TG Pro, macmon) — no per-chip variants are known, so this
/// stays a flat list instead of the per-generation fallback pattern.
///
/// ## Spike findings (Apple M3 Pro MacBook Pro, tested 2026-07-22)
/// Dumped all ~2,300 SMC keys and inspected every key with a `P` prefix.
/// `PSTR` ("System Total Power") tracked load cleanly and plausibly:
/// ~15–19 W idle on AC power, rising to ~25–26 W under an 8-thread `yes`
/// CPU stress, and settling back down within a couple of seconds after the
/// load stopped — consistent with this machine's real power envelope.
/// No root/`powermetrics` reference was available in this sandboxed session
/// to diff against absolute ground truth, so this is corroborated by
/// known third-party SMC documentation plus the load-response behavior
/// above, not a live powermetrics comparison.
///
/// Other power-shaped `flt` keys were also seen moving with load (`PDTR`,
/// `PZC0`, `PZC1`, `PBAT`, `PDBR`, …) but their exact meaning (DC-in vs.
/// per-cluster vs. something else) is not consistently documented across
/// chip generations, so they were deliberately left out rather than shipped
/// as a guess. CPU/GPU package-power keys specifically were not identified
/// with confidence on this machine.
public enum SMCPowerCatalog {
    /// SMC key reporting total system power draw, in watts (`flt` type, 4 bytes).
    public static let systemPowerKey = "PSTR"

    static let labels: [String: String] = [
        systemPowerKey: "System Power",
    ]

    public static func categorize(key: String) -> String? {
        labels[key]
    }
}

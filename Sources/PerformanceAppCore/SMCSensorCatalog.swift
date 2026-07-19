import Foundation

/// Curated map of known Apple Silicon SMC temperature sensor keys → (friendly label, category).
/// Keys absent from this map are silently dropped; this prevents unnamed/garbage sensors appearing in the UI.
/// Covers M1 / M2 / M3 / M4 / M5 — keys that don't exist on a given chip are simply never discovered.
public enum SMCSensorCatalog {
    static let labels: [String: (String, String)] = [
        // ── CPU — M1 ──────────────────────────────────────────────────────────────
        "Tp09": ("CPU Efficiency Core 1",    "CPU"),  // M1 / M2 / M4
        "Tp0T": ("CPU Efficiency Core 2",    "CPU"),  // M1
        "Tp01": ("CPU Performance Core 1",   "CPU"),  // M1 / M2 / M4
        "Tp05": ("CPU Performance Core 2",   "CPU"),  // M1 / M2 / M4
        "Tp0D": ("CPU Performance Core 3",   "CPU"),  // M1 / M2
        "Tp0H": ("CPU Performance Core 4",   "CPU"),  // M1
        "Tp0L": ("CPU Performance Core 5",   "CPU"),  // M1
        "Tp0P": ("CPU Performance Core 6",   "CPU"),  // M1
        "Tp0X": ("CPU Performance Core 7",   "CPU"),  // M1 / M2
        "Tp0b": ("CPU Performance Core 8",   "CPU"),  // M1 / M2 / M4
        // ── CPU — M2 additional ───────────────────────────────────────────────────
        "Tp1h": ("CPU Efficiency Core 1",    "CPU"),
        "Tp1t": ("CPU Efficiency Core 2",    "CPU"),
        "Tp1p": ("CPU Efficiency Core 3",    "CPU"),
        "Tp1l": ("CPU Efficiency Core 4",    "CPU"),
        "Tp0f": ("CPU Performance Core 9",   "CPU"),
        "Tp0j": ("CPU Performance Core 10",  "CPU"),
        // ── CPU — M3 (Te*/Tf* prefix) ─────────────────────────────────────────────
        "Te05": ("CPU Efficiency Core 1",    "CPU"),  // M3 / M4
        "Te0L": ("CPU Efficiency Core 2",    "CPU"),  // M3
        "Te0P": ("CPU Efficiency Core 3",    "CPU"),  // M3
        "Te0S": ("CPU Efficiency Core 4",    "CPU"),  // M3 / M4
        "Te09": ("CPU Efficiency Core 3",    "CPU"),  // M4
        "Te0H": ("CPU Efficiency Core 4",    "CPU"),  // M4
        "Tf04": ("CPU Performance Core 1",   "CPU"),  // M3
        "Tf09": ("CPU Performance Core 2",   "CPU"),
        "Tf0A": ("CPU Performance Core 3",   "CPU"),
        "Tf0B": ("CPU Performance Core 4",   "CPU"),
        "Tf0D": ("CPU Performance Core 5",   "CPU"),
        "Tf0E": ("CPU Performance Core 6",   "CPU"),
        "Tf44": ("CPU Performance Core 7",   "CPU"),
        "Tf49": ("CPU Performance Core 8",   "CPU"),
        "Tf4A": ("CPU Performance Core 9",   "CPU"),
        "Tf4B": ("CPU Performance Core 10",  "CPU"),
        "Tf4D": ("CPU Performance Core 11",  "CPU"),
        "Tf4E": ("CPU Performance Core 12",  "CPU"),
        // ── CPU — M4 additional ───────────────────────────────────────────────────
        "Tp0V": ("CPU Performance Core 5",   "CPU"),
        "Tp0Y": ("CPU Performance Core 6",   "CPU"),
        "Tp0e": ("CPU Performance Core 8",   "CPU"),
        // ── GPU — M1 ──────────────────────────────────────────────────────────────
        "Tg05": ("GPU Cluster 1",            "GPU"),
        "Tg0D": ("GPU Cluster 2",            "GPU"),
        "Tg0L": ("GPU Cluster 3",            "GPU"),
        "Tg0T": ("GPU Cluster 4",            "GPU"),
        "Tg0b": ("GPU Cluster 5",            "GPU"),
        "Tg13": ("GPU Cluster 6",            "GPU"),
        "Tg1b": ("GPU Cluster 7",            "GPU"),
        "Tg23": ("GPU Cluster 8",            "GPU"),
        // ── GPU — M2 ──────────────────────────────────────────────────────────────
        "Tg0f": ("GPU Cluster 1",            "GPU"),
        "Tg0j": ("GPU Cluster 2",            "GPU"),
        // ── GPU — M3 (Tf* prefix) ─────────────────────────────────────────────────
        "Tf14": ("GPU Cluster 1",            "GPU"),
        "Tf18": ("GPU Cluster 2",            "GPU"),
        "Tf19": ("GPU Cluster 3",            "GPU"),
        "Tf1A": ("GPU Cluster 4",            "GPU"),
        "Tf24": ("GPU Cluster 5",            "GPU"),
        "Tf28": ("GPU Cluster 6",            "GPU"),
        "Tf29": ("GPU Cluster 7",            "GPU"),
        "Tf2A": ("GPU Cluster 8",            "GPU"),
        // ── GPU — M4 ──────────────────────────────────────────────────────────────
        "Tg0G": ("GPU Cluster 1",            "GPU"),
        "Tg0H": ("GPU Cluster 2",            "GPU"),
        "Tg1U": ("GPU Cluster 1",            "GPU"),
        "Tg1k": ("GPU Cluster 2",            "GPU"),
        "Tg0K": ("GPU Cluster 3",            "GPU"),
        "Tg0d": ("GPU Cluster 5",            "GPU"),
        "Tg0e": ("GPU Cluster 6",            "GPU"),
        "Tg0k": ("GPU Cluster 8",            "GPU"),
        // ── Trackpad — M1/M2 (single-sensor variants) ────────────────────────────
        "Ts0P": ("Trackpad",                 "Trackpad"),
        "Ts1P": ("Trackpad Actuator",        "Trackpad"),
        "Ts0S": ("Trackpad",                 "Trackpad"),
        "Ts1S": ("Trackpad Actuator",        "Trackpad"),
        // ── Trackpad haptic zones — M3/M4 (Force Touch actuator grid) ────────────
        "TD00": ("Zone A, Sensor 1",         "Trackpad"),
        "TD01": ("Zone A, Sensor 2",         "Trackpad"),
        "TD02": ("Zone A, Sensor 3",         "Trackpad"),
        "TD03": ("Zone A, Sensor 4",         "Trackpad"),
        "TD04": ("Zone A, Sensor 5",         "Trackpad"),
        "TD10": ("Zone B, Sensor 1",         "Trackpad"),
        "TD11": ("Zone B, Sensor 2",         "Trackpad"),
        "TD12": ("Zone B, Sensor 3",         "Trackpad"),
        "TD13": ("Zone B, Sensor 4",         "Trackpad"),
        "TD14": ("Zone B, Sensor 5",         "Trackpad"),
        "TD20": ("Zone C, Sensor 1",         "Trackpad"),
        "TD21": ("Zone C, Sensor 2",         "Trackpad"),
        "TD22": ("Zone C, Sensor 3",         "Trackpad"),
        "TD23": ("Zone C, Sensor 4",         "Trackpad"),
        "TD24": ("Zone C, Sensor 5",         "Trackpad"),
        "TDBP": ("Bottom Proximity",         "Trackpad"),
        "TDEL": ("Edge Left",                "Trackpad"),
        "TDER": ("Edge Right",               "Trackpad"),
        "TDTC": ("Center",                   "Trackpad"),
        "TDTP": ("Top Proximity",            "Trackpad"),
        // ── Storage ───────────────────────────────────────────────────────────────
        "TH0x": ("SSD",                      "Storage"),  // M-series NAND
        "TH0O": ("SSD",                      "Storage"),  // older variant
        "TH1O": ("SSD 2",                    "Storage"),
        "TH2O": ("SSD 3",                    "Storage"),
        "TH3O": ("SSD 4",                    "Storage"),
        // ── System / board ────────────────────────────────────────────────────────
        "TCHP": ("Charger Proximity",        "System"),
        "Ta0P": ("Airport Proximity",        "System"),
        "TW0P": ("WiFi Proximity",           "System"),
        "TPCD": ("Power Manager",            "System"),
        "TP0P": ("Power Supply",             "System"),
        "TaLP": ("Airflow Left",             "Airflow"),
        "TaRF": ("Airflow Right",            "Airflow"),
        // ── Memory ────────────────────────────────────────────────────────────────
        "Tm0P": ("Memory",                   "Memory"),
        "Tm02": ("Memory Module 1",          "Memory"),  // M1
        "Tm06": ("Memory Module 2",          "Memory"),
        "Tm08": ("Memory Module 3",          "Memory"),
        "Tm09": ("Memory Module 4",          "Memory"),
        "Tm0p": ("Memory Proximity 1",       "Memory"),  // M4
        "Tm1p": ("Memory Proximity 2",       "Memory"),
        "Tm2p": ("Memory Proximity 3",       "Memory"),
        // ── Battery (suppresses unknown display; not shown in UI) ─────────────────
        "TB0T": ("Battery",                  "Battery"),
        "TB1T": ("Battery 1",                "Battery"),
        "TB2T": ("Battery 2",                "Battery"),
    ]

    /// Returns nil for any key not in the curated map — prevents surfacing unnamed sensors.
    public static func categorize(key: String) -> (label: String, category: String)? {
        guard let (label, category) = labels[key] else { return nil }
        return (label: label, category: category)
    }
}

import Foundation

/// Classifies network interface names as physical (real NICs) vs virtual —
/// VPN tunnels, loopback, AirDrop/Handoff peer links, bridges, and other
/// synthetic interfaces. Used to keep cumulative data-usage totals from
/// double-counting bytes that already crossed a physical interface (e.g. a
/// VPN's `utun` tunnel re-wrapping traffic that also incremented `en0`).
public enum NetworkInterfaceFilter {
    private static let virtualPrefixes = [
        "lo",       // loopback
        "utun",     // VPN (IKEv2/WireGuard/etc.) and Personal Hotspot backhaul
        "ppp",      // legacy VPN (PPTP/L2TP)
        "ipsec",    // VPN
        "awdl",     // Apple Wireless Direct Link (AirDrop/Handoff)
        "llw",      // low-latency WLAN, paired with awdl
        "bridge",   // virtual bridge (e.g. Thunderbolt Bridge, container networking)
        "gif",      // generic tunnel interface
        "stf",      // 6to4 tunnel
        "p2p",      // AirPlay/AirDrop peer-to-peer
    ]

    /// Whether `name` (e.g. "en0", "utun3") identifies a physical network
    /// interface — real Wi-Fi/Ethernet hardware — as opposed to a virtual,
    /// tunnel, or loopback interface.
    public static func isPhysical(_ name: String) -> Bool {
        !virtualPrefixes.contains { name.hasPrefix($0) }
    }
}

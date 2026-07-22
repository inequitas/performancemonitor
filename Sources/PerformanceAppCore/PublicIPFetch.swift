import Foundation

/// Pure decision logic for the public-IP lookup in `MetricsEngine`, extracted
/// so the refetch cadence and response validation can be unit tested without
/// URLSession or NWPathMonitor.
///
/// Two bugs this exists to prevent from recurring:
///  - A failed attempt must not be treated as a fresh success: the 5-minute
///    throttle only applies after `lastSuccess`, and failures instead use a
///    short backoff so the next refresh tick retries soon (without hammering
///    the endpoint every tick).
///  - A network change (Wi-Fi <-> hotspot, cable unplugged, etc.) must force
///    a refetch regardless of either cadence, since the old public IP is no
///    longer valid for the new interface.
public enum PublicIPFetch {
    /// Normal refetch cadence once a fetch has succeeded.
    public static let successInterval: TimeInterval = 300
    /// Retry cadence after a failed attempt — short enough that the next
    /// refresh tick (typically a few seconds later) can retry promptly, but
    /// long enough not to refire on every single tick while an outage lasts.
    public static let failureBackoff: TimeInterval = 15

    /// Whether a fetch should be (re)triggered right now.
    ///
    /// - Parameters:
    ///   - lastSuccess: when the public IP was last fetched successfully, if ever.
    ///   - lastFailure: when the most recent attempt failed, if ever.
    ///   - now: the current time.
    ///   - networkChanged: true if the active network path changed since the
    ///     last check (e.g. a different interface type or connectivity
    ///     status) — forces a refetch regardless of the throttles above.
    ///   - inFlight: true if a fetch is already in progress — never start a
    ///     second one concurrently.
    public static func shouldFetch(
        lastSuccess: Date?,
        lastFailure: Date?,
        now: Date,
        networkChanged: Bool,
        inFlight: Bool
    ) -> Bool {
        guard !inFlight else { return false }
        if networkChanged { return true }

        if let lastFailure, now.timeIntervalSince(lastFailure) < failureBackoff {
            return false
        }
        if let lastSuccess, now.timeIntervalSince(lastSuccess) < successInterval {
            return false
        }
        return true
    }

    /// Basic shape check for a public-IP response body: trims whitespace and
    /// accepts plausible dotted-quad IPv4 or colon-separated IPv8-hextet
    /// IPv6 forms. Rejects empty bodies, HTML/text error pages, and anything
    /// else that isn't shaped like an address — this is a sanity filter, not
    /// a full RFC validator.
    public static func isPlausibleIPAddress(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        return isPlausibleIPv4(s) || isPlausibleIPv6(s)
    }

    private static func isPlausibleIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  part.allSatisfy(\.isNumber),
                  let value = Int(part), value >= 0, value <= 255
            else { return false }
        }
        return true
    }

    private static func isPlausibleIPv6(_ s: String) -> Bool {
        guard s.contains(":") else { return false }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.count <= 8 else { return false }
        let hexDigits = Set("0123456789abcdefABCDEF")
        for part in parts {
            guard part.isEmpty || (part.count <= 4 && part.allSatisfy { hexDigits.contains($0) }) else {
                return false
            }
        }
        return true
    }
}

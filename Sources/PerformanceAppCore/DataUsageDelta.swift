import Foundation

/// Turns two cumulative interface byte counters into the bytes transferred
/// between them.
///
/// Interface counters (`if_data.ifi_ibytes`/`ifi_obytes`) only ever increase
/// while an interface stays up. They reset to zero on reboot, on interface
/// restart (Wi-Fi toggled off/on, cable unplugged/replugged), or when macOS
/// swaps in a fresh interface after a link change. When the counter goes
/// backwards, that reset is the only explanation — the pure function treats
/// the current reading as "bytes since the reset" rather than producing a
/// negative or wrapped-around delta.
public enum DataUsageDelta {
    /// - Parameters:
    ///   - previous: the cumulative counter value from the last sample.
    ///   - current: the cumulative counter value from this sample.
    /// - Returns: bytes transferred since the previous sample. Never negative.
    public static func delta(previous: UInt64, current: UInt64) -> UInt64 {
        current >= previous ? current - previous : current
    }
}

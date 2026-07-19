import Foundation

/// Pure prefix-length → dotted-decimal netmask conversion.
public enum SubnetMask {
    /// Converts a CIDR prefix length (e.g. 24) to its dotted-decimal netmask
    /// string (e.g. "255.255.255.0"). Returns nil for a missing or zero
    /// prefix length, matching the original `LocalInterface.subnetMask`
    /// behavior this was extracted from.
    public static func string(forPrefixLength prefixLength: Int?) -> String? {
        guard let p = prefixLength, p > 0 else { return nil }
        let bits = p >= 32 ? UInt32.max : ~(UInt32.max >> p)
        return "\(bits >> 24).\((bits >> 16) & 0xFF).\((bits >> 8) & 0xFF).\(bits & 0xFF)"
    }
}

import Foundation

/// Pure four-character-code encode/decode used for SMC keys (e.g. "TC0P").
public enum FourCC {
    /// Packs up to the first 4 UTF-8 bytes of `key` into a big-endian UInt32.
    public static func encode(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// Unpacks a big-endian UInt32 back into its 4-character string form.
    /// Returns "????" if the bytes aren't valid UTF-8.
    public static func decode(_ code: UInt32) -> String {
        let b: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >>  8) & 0xFF),
            UInt8( code        & 0xFF)
        ]
        return String(bytes: b, encoding: .utf8) ?? "????"
    }
}

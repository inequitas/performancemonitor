import Foundation

/// Pure version-string comparison used by the update checker.
public enum VersionComparison {
    /// Compares two dot-separated version strings component by component
    /// (e.g. "1.2.10" vs "1.2.9"). Missing trailing components are treated
    /// as 0. Non-numeric components are dropped by `Int(...)` parsing, same
    /// as the original inline implementation this was extracted from.
    ///
    /// Returns true if `a` is newer than `b`.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let parts = { (s: String) -> [Int] in s.split(separator: ".").compactMap { Int($0) } }
        let va = parts(a), vb = parts(b)
        for i in 0..<max(va.count, vb.count) {
            let ai = i < va.count ? va[i] : 0
            let bi = i < vb.count ? vb[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}

import Foundation

/// Pure version-string comparison used by the update checker.
///
/// Supports a pragmatic subset of semver: a release part of dot-separated
/// numeric components, optionally followed by a `-`-introduced pre-release
/// part of dot-separated identifiers (e.g. "1.1.0-beta.1"). Pre-release
/// identifiers compare numerically when both sides parse as integers, and
/// lexically (ASCII) otherwise; a numeric identifier always sorts below an
/// alphanumeric one at the same position, per the semver spec. A version
/// with a pre-release part always sorts below the same release version
/// without one (e.g. "1.1.0-beta.1" < "1.1.0").
public enum VersionComparison {
    private struct Parsed {
        let release: [Int]
        /// nil means this is a plain release version (no "-..." suffix).
        let prerelease: [String]?
    }

    private static func parse(_ s: String) -> Parsed {
        let release: Substring
        let prerelease: Substring?
        if let dashIndex = s.firstIndex(of: "-") {
            release = s[s.startIndex..<dashIndex]
            prerelease = s[s.index(after: dashIndex)...]
        } else {
            release = s[...]
            prerelease = nil
        }
        let releaseParts = release.split(separator: ".").compactMap { Int($0) }
        let prereleaseParts = prerelease.map { $0.split(separator: ".").map(String.init) }
        return Parsed(release: releaseParts, prerelease: prereleaseParts)
    }

    /// Returns true if `a` is newer (higher precedence) than `b`.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        compare(a, b) == .orderedDescending
    }

    /// Returns true if `version` carries a `-`-introduced pre-release part
    /// (e.g. "1.1.0-beta.1"). Used to detect a build that's running a beta
    /// version string regardless of which update channel it currently checks.
    public static func isPrerelease(_ version: String) -> Bool {
        parse(version).prerelease != nil
    }

    private static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parse(a), pb = parse(b)

        for i in 0..<max(pa.release.count, pb.release.count) {
            let ai = i < pa.release.count ? pa.release[i] : 0
            let bi = i < pb.release.count ? pb.release[i] : 0
            if ai != bi { return ai > bi ? .orderedDescending : .orderedAscending }
        }

        switch (pa.prerelease, pb.prerelease) {
        case (nil, nil):
            return .orderedSame
        case (nil, .some):
            // a is a plain release, b is a pre-release of the same base version.
            return .orderedDescending
        case (.some, nil):
            return .orderedAscending
        case let (.some(pra), .some(prb)):
            return comparePrerelease(pra, prb)
        }
    }

    private static func comparePrerelease(_ a: [String], _ b: [String]) -> ComparisonResult {
        for i in 0..<max(a.count, b.count) {
            // Fewer identifiers (all preceding ones equal) sorts lower — semver rule.
            guard i < a.count else { return .orderedAscending }
            guard i < b.count else { return .orderedDescending }

            let ai = a[i], bi = b[i]
            if ai == bi { continue }

            switch (Int(ai), Int(bi)) {
            case let (x?, y?):
                return x > y ? .orderedDescending : .orderedAscending
            case (.some, nil):
                // Numeric identifiers always have lower precedence than alphanumeric ones.
                return .orderedAscending
            case (nil, .some):
                return .orderedDescending
            case (nil, nil):
                return ai > bi ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }
}

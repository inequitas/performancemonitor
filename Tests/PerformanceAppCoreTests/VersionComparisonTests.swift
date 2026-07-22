import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("VersionComparison")
struct VersionComparisonTests {

    @Test func patchVersionIsNewer() {
        #expect(VersionComparison.isNewer("1.0.1", than: "1.0"))
        #expect(!VersionComparison.isNewer("1.0", than: "1.0.1"))
    }

    @Test func numericComponentCompareNotLexical() {
        // 0.10 must beat 0.9 numerically, not "0.9" > "0.10" lexically.
        #expect(VersionComparison.isNewer("0.10", than: "0.9"))
        #expect(!VersionComparison.isNewer("0.9", than: "0.10"))
    }

    @Test func equalVersionsAreNotNewer() {
        #expect(!VersionComparison.isNewer("1.2.3", than: "1.2.3"))
        #expect(!VersionComparison.isNewer("1.0", than: "1.0.0"))
    }

    @Test func majorVersionDifference() {
        #expect(VersionComparison.isNewer("2.0", than: "1.9.9"))
        #expect(!VersionComparison.isNewer("1.9.9", than: "2.0"))
    }

    @Test func usageAfterStrippingVPrefix() {
        // UpdateChecker strips a leading "v"/"V" (CharacterSet(charactersIn: "vV"))
        // from the GitHub tag before ever calling isNewer — this mirrors that flow.
        let strippedTag = "v1.2.0".trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        #expect(strippedTag == "1.2.0")
        #expect(VersionComparison.isNewer(strippedTag, than: "1.1.9"))
        #expect(!VersionComparison.isNewer(strippedTag, than: "1.2.0"))
    }

    @Test func unstrippedVPrefixQuirkIsPreserved() {
        // isNewer itself does NOT strip a "v" prefix — this is a pre-existing quirk
        // of the extracted logic, not something this refactor should "fix". A "vN"
        // component fails Int parsing and is silently dropped by compactMap, so two
        // differently-prefixed versions can compare as equal. Pinned here so the
        // extraction is verified not to change behavior.
        #expect(!VersionComparison.isNewer("v2.0", than: "v1.0"))
    }

    @Test func emptyAndNonNumericStringsDoNotCrash() {
        #expect(!VersionComparison.isNewer("", than: ""))
        #expect(!VersionComparison.isNewer("abc", than: "def"))
    }

    // MARK: - Pre-release (semver) ordering

    @Test func prereleaseIsLowerThanSameReleaseVersion() {
        #expect(VersionComparison.isNewer("1.1.0", than: "1.1.0-beta.1"))
        #expect(!VersionComparison.isNewer("1.1.0-beta.1", than: "1.1.0"))
    }

    @Test func prereleaseNumericIdentifiersCompareNumerically() {
        #expect(VersionComparison.isNewer("1.1.0-beta.2", than: "1.1.0-beta.1"))
        #expect(VersionComparison.isNewer("1.1.0-beta.10", than: "1.1.0-beta.2"))
        #expect(!VersionComparison.isNewer("1.1.0-beta.2", than: "1.1.0-beta.10"))
        #expect(!VersionComparison.isNewer("1.1.0-beta.1", than: "1.1.0-beta.1"))
    }

    @Test func prereleaseOfDifferentBaseVersionsComparesByBaseFirst() {
        #expect(VersionComparison.isNewer("1.2.0-beta.1", than: "1.1.0-beta.99"))
        #expect(!VersionComparison.isNewer("1.1.0-beta.99", than: "1.2.0-beta.1"))
        // A newer base version's pre-release still beats an older base's final release.
        #expect(VersionComparison.isNewer("1.2.0-beta.1", than: "1.1.0"))
    }

    @Test func prereleaseWithFewerIdentifiersSortsLower() {
        // "beta" (1 identifier) < "beta.1" (2 identifiers) when the shared prefix matches.
        #expect(VersionComparison.isNewer("1.0.0-beta.1", than: "1.0.0-beta"))
        #expect(!VersionComparison.isNewer("1.0.0-beta", than: "1.0.0-beta.1"))
    }

    @Test func numericPrereleaseIdentifierAlwaysBelowAlphanumeric() {
        // Per semver: numeric identifiers always have lower precedence than
        // alphanumeric ones at the same position.
        #expect(VersionComparison.isNewer("1.0.0-beta", than: "1.0.0-1"))
        #expect(!VersionComparison.isNewer("1.0.0-1", than: "1.0.0-beta"))
    }

    @Test func nonNumericPrereleaseIdentifiersCompareLexically() {
        #expect(VersionComparison.isNewer("1.0.0-beta", than: "1.0.0-alpha"))
        #expect(!VersionComparison.isNewer("1.0.0-alpha", than: "1.0.0-beta"))
    }

    @Test func equalPrereleaseVersionsAreNotNewer() {
        #expect(!VersionComparison.isNewer("1.1.0-beta.3", than: "1.1.0-beta.3"))
    }

    @Test func differentBaseVersionComparisonUnaffectedByPrereleaseLogic() {
        // Plain (non-prerelease) comparisons across different base versions
        // must behave exactly as before this feature was added.
        #expect(VersionComparison.isNewer("1.2.0", than: "1.1.9"))
        #expect(!VersionComparison.isNewer("1.1.9", than: "1.2.0"))
        #expect(VersionComparison.isNewer("2.0.0", than: "1.99.99"))
    }

    // MARK: - isPrerelease

    @Test func isPrereleaseTrueForBetaSuffix() {
        #expect(VersionComparison.isPrerelease("1.1.0-beta.1"))
        #expect(VersionComparison.isPrerelease("1.1.0-beta"))
        #expect(VersionComparison.isPrerelease("1.0.0-alpha.2"))
    }

    @Test func isPrereleaseFalseForPlainRelease() {
        #expect(!VersionComparison.isPrerelease("1.1.0"))
        #expect(!VersionComparison.isPrerelease("1.0"))
        #expect(!VersionComparison.isPrerelease(""))
    }
}

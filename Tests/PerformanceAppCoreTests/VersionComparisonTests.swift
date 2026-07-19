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
}

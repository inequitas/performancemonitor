import Testing
@testable import PerformanceAppCore

@Suite("ProcessGlossary")
struct ProcessGlossaryTests {

    private func entry(_ match: GlossaryEntry.Match,
                       title: String = "T",
                       category: GlossaryEntry.Category = .system,
                       expectedHigh: Bool = false) -> GlossaryEntry {
        GlossaryEntry(match: match, title: title, category: category,
                      expectedHigh: expectedHigh, description: "D")
    }

    @Test func exactNameMatches() {
        let g = ProcessGlossary(entries: [entry(.name("mds_stores"), title: "Spotlight")])
        #expect(g.lookup(name: "mds_stores")?.title == "Spotlight")
    }

    @Test func unknownProcessReturnsNothing() {
        let g = ProcessGlossary(entries: [entry(.name("mds_stores"))])
        #expect(g.lookup(name: "something_else") == nil)
    }

    @Test func nameMatchIsCaseSensitive() {
        // Process names come straight from the kernel; treating them loosely
        // would let "Claude" match "claude", which are different processes.
        let g = ProcessGlossary(entries: [entry(.name("WindowServer"))])
        #expect(g.lookup(name: "windowserver") == nil)
    }

    @Test func truncatedNameMatchesTheLongerEntry() {
        // proc_name cuts at 32 characters, so the disk list can report a name
        // the CPU list reports in full.
        let full = "com.apple.WebKit.Networking.Servi"
        let truncated = String(full.prefix(32))
        let g = ProcessGlossary(entries: [entry(.name(full), title: "WebKit networking")])
        #expect(truncated.count == 32)
        #expect(g.lookup(name: truncated)?.title == "WebKit networking")
    }

    @Test func shortNameNeverClaimsALongerEntryByPrefix() {
        // "mds" must not match "mds_stores": it is a real, different process,
        // and it is nowhere near the truncation limit.
        let g = ProcessGlossary(entries: [entry(.name("mds_stores"), title: "Spotlight")])
        #expect(g.lookup(name: "mds") == nil)
    }

    @Test func exactNameWinsOverTruncatedPrefix() {
        let long = String(repeating: "a", count: 40)
        let observed = String(long.prefix(32))
        let g = ProcessGlossary(entries: [
            entry(.name(long), title: "long"),
            entry(.name(observed), title: "exact")
        ])
        #expect(g.lookup(name: observed)?.title == "exact")
    }

    @Test func bundleIDMatchesWhenNameDoesNot() {
        let g = ProcessGlossary(entries: [entry(.bundleID("com.example.thing"), title: "Thing")])
        #expect(g.lookup(name: "unrecognised", bundleID: "com.example.thing")?.title == "Thing")
    }

    @Test func longestBundlePrefixWins() {
        // A specific helper should beat the family it belongs to.
        let g = ProcessGlossary(entries: [
            entry(.bundleIDPrefix("com.example"), title: "family"),
            entry(.bundleIDPrefix("com.example.helper"), title: "specific")
        ])
        #expect(g.lookup(name: "x", bundleID: "com.example.helper.renderer")?.title == "specific")
    }

    @Test func exactBundleIDBeatsPrefix() {
        let g = ProcessGlossary(entries: [
            entry(.bundleIDPrefix("com.example"), title: "prefix"),
            entry(.bundleID("com.example.thing"), title: "exact")
        ])
        #expect(g.lookup(name: "x", bundleID: "com.example.thing")?.title == "exact")
    }

    @Test func pathPrefixAndSuffixMatch() {
        let g = ProcessGlossary(entries: [
            entry(.pathPrefix("/System/Library/"), title: "system path"),
            entry(.pathSuffix("/Contents/MacOS/Helper"), title: "helper path")
        ])
        #expect(g.lookup(name: "x", path: "/System/Library/CoreServices/foo")?.title == "system path")
        #expect(g.lookup(name: "x", path: "/Applications/A.app/Contents/MacOS/Helper")?.title == "helper path")
    }

    @Test func nameBeatsBundleAndPath() {
        let g = ProcessGlossary(entries: [
            entry(.pathPrefix("/usr/"), title: "path"),
            entry(.bundleID("com.example.thing"), title: "bundle"),
            entry(.name("thing"), title: "name")
        ])
        #expect(g.lookup(name: "thing", bundleID: "com.example.thing", path: "/usr/bin/thing")?.title == "name")
    }

    @Test func expectedHighIsCarried() {
        let g = ProcessGlossary(entries: [entry(.name("kernel_task"), expectedHigh: true)])
        #expect(g.lookup(name: "kernel_task")?.expectedHigh == true)
    }

    @Test func emptyGlossaryMatchesNothing() {
        let g = ProcessGlossary(entries: [])
        #expect(g.count == 0)
        #expect(g.lookup(name: "anything") == nil)
    }
}

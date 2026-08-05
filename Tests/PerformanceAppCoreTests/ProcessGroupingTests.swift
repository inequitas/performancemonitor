import Testing
@testable import PerformanceAppCore

@Suite("ProcessGrouping")
struct ProcessGroupingTests {

    private func usage(_ pid: Int32, _ name: String, _ value: Double) -> ProcessUsage {
        ProcessUsage(pid: pid, name: name, value: value)
    }

    // MARK: - What counts as a helper

    @Test func aHelperIsTheParentNamePlusASeparator() {
        #expect(ProcessGrouping.isHelper("Google Chrome Helper", of: "Google Chrome"))
        #expect(ProcessGrouping.isHelper("Code Helper (Renderer)", of: "Code"))
        #expect(ProcessGrouping.isHelper("node.worker", of: "node"))
        #expect(ProcessGrouping.isHelper("foo-bar", of: "foo"))
        #expect(ProcessGrouping.isHelper("foo_bar", of: "foo"))
        #expect(ProcessGrouping.isHelper("foo(1)", of: "foo"))
    }

    @Test func anIdenticalNameCounts() {
        #expect(ProcessGrouping.isHelper("zsh", of: "zsh"))
    }

    @Test func aSharedPrefixWithoutASeparatorDoesNot() {
        // Otherwise any app whose name prefixes another's would swallow it.
        #expect(!ProcessGrouping.isHelper("Slackware", of: "Slack"))
        #expect(!ProcessGrouping.isHelper("nodejs", of: "node"))
    }

    @Test func matchingIsCaseSensitive() {
        // `Claude` the app and `claude` the command line tool are different
        // programs and must not be added together.
        #expect(!ProcessGrouping.isHelper("claude", of: "Claude"))
    }

    @Test func anUnrelatedChildIsNotAHelper() {
        #expect(!ProcessGrouping.isHelper("swift-frontend", of: "zsh"))
    }

    // MARK: - Grouping

    @Test func helpersAreAddedUpUnderTheApp() {
        let found = ProcessGrouping.group(
            [usage(100, "Slack", 5), usage(101, "Slack Helper", 20), usage(102, "Slack Helper", 15)],
            parents: [100: 1, 101: 100, 102: 100],
            topCount: 10
        )
        #expect(found.count == 1)
        #expect(found[0].name == "Slack")
        #expect(found[0].value == 40)
        #expect(found[0].members.count == 3)
    }

    @Test func aTerminalDoesNotSwallowWhatWasRunFromIt() {
        // The reason grouping is not done on the parent chain alone: a shell
        // using no CPU would otherwise hide the compiler that is using all of
        // it, which is the opposite of what the list is for.
        let found = ProcessGrouping.group(
            [usage(100, "zsh", 0.1), usage(101, "swift-frontend", 90)],
            parents: [100: 1, 101: 100],
            topCount: 10
        )
        #expect(found.count == 2)
        #expect(found[0].name == "swift-frontend")
        #expect(found[0].members.isEmpty)
    }

    @Test func helpersOfHelpersReachTheApp() {
        let found = ProcessGrouping.group(
            [usage(100, "Code", 1), usage(101, "Code Helper", 1), usage(102, "Code Helper (Renderer)", 1)],
            parents: [100: 1, 101: 100, 102: 101],
            topCount: 10
        )
        #expect(found.count == 1)
        #expect(found[0].members.count == 3)
    }

    @Test func membersAreFlattenedNotNested() {
        // The UI renders members as a flat list, so a chain must not arrive as
        // a member that itself has members.
        let found = ProcessGrouping.group(
            [usage(100, "Code", 1), usage(101, "Code Helper", 1), usage(102, "Code Helper (Renderer)", 1)],
            parents: [100: 1, 101: 100, 102: 101],
            topCount: 10
        )
        #expect(found[0].members.allSatisfy { $0.members.isEmpty })
    }

    @Test func independentProcessesSharingANameMerge() {
        // Eleven Spotlight workers all started by launchd: no parent links them,
        // but one row saying so beats eleven identical ones.
        let found = ProcessGrouping.group(
            [usage(10, "mdworker_shared", 2), usage(11, "mdworker_shared", 3), usage(12, "mdworker_shared", 1)],
            parents: [10: 1, 11: 1, 12: 1],
            topCount: 10
        )
        #expect(found.count == 1)
        #expect(found[0].value == 6)
        #expect(found[0].members.count == 3)
    }

    @Test func aLoneProcessCarriesNoMembers() {
        // So a caller cannot tell a group of one from an ungrouped list.
        let found = ProcessGrouping.group([usage(1, "Finder", 3)], parents: [1: 1], topCount: 10)
        #expect(found[0].members.isEmpty)
    }

    @Test func membersAreOrderedLargestFirst() {
        let found = ProcessGrouping.group(
            [usage(100, "Slack", 1), usage(101, "Slack Helper", 9), usage(102, "Slack Helper", 5)],
            parents: [100: 1, 101: 100, 102: 100],
            topCount: 10
        )
        #expect(found[0].members.map(\.value) == [9, 5, 1])
    }

    @Test func theGroupTakesTheLowestPIDSoRowsDoNotJump() {
        // The row identity must not move between ticks as the values shuffle,
        // or SwiftUI treats it as a different row and the disclosure collapses.
        let found = ProcessGrouping.group(
            [usage(500, "Slack", 1), usage(100, "Slack", 9)],
            parents: [500: 1, 100: 1],
            topCount: 10
        )
        #expect(found[0].pid == 100)
    }

    @Test func groupsAreSortedByTheirTotal() {
        let found = ProcessGrouping.group(
            [usage(1, "Finder", 30),
             usage(100, "Slack", 5), usage(101, "Slack Helper", 20), usage(102, "Slack Helper", 15)],
            parents: [1: 1, 100: 1, 101: 100, 102: 100],
            topCount: 10
        )
        #expect(found.map(\.name) == ["Slack", "Finder"])
    }

    @Test func equalValuesAreOrderedByNameSoTheListDoesNotShuffle() {
        let found = ProcessGrouping.group(
            [usage(1, "beta", 0), usage(2, "alpha", 0)],
            parents: [:],
            topCount: 10
        )
        #expect(found.map(\.name) == ["alpha", "beta"])
    }

    @Test func aMissingParentIsTreatedAsItsOwnRoot() {
        let found = ProcessGrouping.group([usage(42, "orphan", 1)], parents: [:], topCount: 10)
        #expect(found.count == 1)
        #expect(found[0].name == "orphan")
    }

    @Test func aParentOutsideTheListStopsTheWalk() {
        // ps output can name a parent that has since exited.
        let found = ProcessGrouping.group([usage(2, "Slack Helper", 4)], parents: [2: 999], topCount: 10)
        #expect(found.count == 1)
        #expect(found[0].name == "Slack Helper")
    }

    @Test func aCyclicParentTableTerminates() {
        // Defensive: two pids naming each other must not spin forever.
        let found = ProcessGrouping.group(
            [usage(1, "loop", 1), usage(2, "loop", 1)],
            parents: [1: 2, 2: 1],
            topCount: 10
        )
        #expect(found.count == 1)
        #expect(found[0].value == 2)
    }

    @Test func aProcessThatIsItsOwnParentTerminates() {
        let found = ProcessGrouping.group([usage(1, "launchd", 1)], parents: [1: 1], topCount: 10)
        #expect(found.count == 1)
    }

    @Test func emptyInputYieldsNothing() {
        #expect(ProcessGrouping.group([], parents: [:], topCount: 10).isEmpty)
    }

    @Test func nonPositiveTopCountYieldsNothing() {
        #expect(ProcessGrouping.group([usage(1, "Finder", 1)], parents: [:], topCount: 0).isEmpty)
    }

    // MARK: - What the name cannot tell you

    @Test func theGlossaryCanNameTheOwningApp() {
        // plugin-container is Firefox, and nothing about either name says so.
        let found = ProcessGrouping.group(
            [usage(100, "firefox", 2), usage(101, "plugin-container", 5), usage(102, "plugin-container", 4)],
            parents: [100: 1, 101: 100, 102: 100],
            owners: ["firefox": "firefox", "plugin-container": "firefox"],
            topCount: 10
        )
        #expect(found.count == 1)
        #expect(found[0].name == "firefox")
        #expect(found[0].value == 11)
        #expect(found[0].members.count == 3)
    }

    @Test func aDeclaredOwnerNeedNotBeRunning() {
        // The five Spotlight processes are started independently by launchd and
        // there is no "Spotlight" process to hang them from, so the group name
        // is one the glossary supplies rather than one that is running.
        let found = ProcessGrouping.group(
            [usage(1, "mds_stores", 3), usage(2, "mdworker_shared", 2), usage(3, "corespotlightd", 1)],
            parents: [:],
            owners: ["mds_stores": "Spotlight", "mdworker_shared": "Spotlight", "corespotlightd": "Spotlight"],
            topCount: 10
        )
        #expect(found.count == 1)
        #expect(found[0].name == "Spotlight")
        #expect(found[0].value == 6)
    }

    @Test func ownershipAppliesAfterTheParentWalk() {
        // A helper reaches its app by name first, and only that app's name is
        // looked up, so one entry covers a whole family of helpers.
        let found = ProcessGrouping.group(
            [usage(100, "firefox", 1), usage(101, "firefox helper", 1), usage(102, "plugin-container", 1)],
            parents: [100: 1, 101: 100, 102: 100],
            owners: ["firefox": "Firefox", "plugin-container": "Firefox"],
            topCount: 10
        )
        #expect(found.count == 1)
        #expect(found[0].name == "Firefox")
        #expect(found[0].members.count == 3)
    }

    @Test func anUndeclaredProcessIsLeftAlone() {
        // WebKit's content processes serve several apps from one binary, so the
        // glossary names no owner and they must stay out of any app's total.
        let found = ProcessGrouping.group(
            [usage(1, "Safari", 4), usage(2, "com.apple.WebKit.WebContent", 9)],
            parents: [1: 1, 2: 1],
            owners: ["plugin-container": "firefox"],
            topCount: 10
        )
        #expect(found.count == 2)
        #expect(found.first?.name == "com.apple.WebKit.WebContent")
    }

    @Test func anEmptyOwnerTableChangesNothing() {
        let withTable = ProcessGrouping.group(
            [usage(1, "Finder", 3), usage(2, "Dock", 1)], parents: [:], owners: [:], topCount: 10)
        let without = ProcessGrouping.group(
            [usage(1, "Finder", 3), usage(2, "Dock", 1)], parents: [:], topCount: 10)
        #expect(withTable == without)
    }
}

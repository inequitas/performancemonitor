import Foundation

/// Rolls helper processes into the application that spawned them, so a browser
/// with twelve renderers is one row rather than twelve.
///
/// A top-ten list is worthless when a single app fills it. Chrome, Electron apps
/// and Xcode all spawn a helper per tab, window or compile job, and each one
/// individually looks unremarkable while together they account for most of the
/// machine.
///
/// ## What counts as a helper
///
/// A process is folded into its parent when its name is the parent's name, or
/// begins with the parent's name at a word boundary: "Google Chrome Helper
/// (Renderer)" under "Google Chrome", "Code Helper" under "Code". Walking up the
/// parent chain repeats this, so a helper of a helper still lands on the app.
///
/// The name test is what keeps this honest. Grouping purely on the parent chain
/// would put everything you ever started from a terminal under that terminal,
/// hiding the compiler that is actually burning the CPU behind a shell using
/// none of it. Requiring the names to relate means an unrelated child stays its
/// own row.
///
/// Processes that end up as their own root are then merged by name, which is how
/// eleven `mdworker_shared` instances started independently by `launchd` become
/// one Spotlight row. This does mean two unrelated shells both called `zsh` are
/// counted together; for a list whose purpose is "what is using my machine",
/// that reads better than seven identical rows.
///
/// ## What the name cannot tell you
///
/// `plugin-container` is Firefox and `mds_stores` is Spotlight, and no rule
/// could work that out: the names have nothing in common with the app they
/// belong to. Those are named in the glossary, which `owners` passes in here, so
/// the knowledge sits in data a person can read and correct rather than in
/// pattern matching that would have to guess.
///
/// Deliberately absent from that data: `com.apple.WebKit.WebContent` and its
/// siblings serve Safari, Mail, Notes and the App Store from one binary. macOS
/// knows which app is responsible, but only through private API, so they are
/// grouped under WebKit rather than attributed to any one app.
///
/// Pure, so the rules can be tested without running `ps`.
public enum ProcessGrouping {

    /// Groups `processes` and returns the `topCount` heaviest, largest first.
    ///
    /// - Parameters:
    ///   - processes: Every process sampled, not a pre-trimmed top list: a group
    ///     only outranks its neighbours once its members are added up, and
    ///     members that individually fall outside the top would be lost.
    ///   - parents: pid to parent pid. A pid missing here has no known parent
    ///     and is treated as its own root.
    ///   - owners: Process name to the application it belongs to, for the cases
    ///     no rule could infer. Applied after the parent walk, and only one step
    ///     deep, so the table cannot form a cycle.
    ///   - topCount: How many rows to return.
    /// - Returns: One entry per group. A group of one is returned as a plain
    ///   process with no members, so callers cannot tell it apart from an
    ///   ungrouped list.
    public static func group(_ processes: [ProcessUsage],
                             parents: [Int32: Int32],
                             owners: [String: String] = [:],
                             topCount: Int) -> [ProcessUsage] {
        guard topCount > 0 else { return [] }
        var names: [Int32: String] = [:]
        names.reserveCapacity(processes.count)
        for process in processes { names[process.pid] = process.name }

        // Group by the root's name rather than its pid, so independently
        // launched processes sharing a name merge too.
        var buckets: [String: [ProcessUsage]] = [:]
        var rootPIDs: [String: Int32] = [:]
        for process in processes {
            let root = self.root(of: process.pid, names: names, parents: parents)
            let rootName = names[root] ?? process.name
            let key = owners[rootName] ?? rootName
            buckets[key, default: []].append(process)
            // Lowest pid wins, so the identity of a row does not jump between
            // ticks as the values move around.
            rootPIDs[key] = Swift.min(rootPIDs[key] ?? root, root)
        }

        var grouped: [ProcessUsage] = []
        grouped.reserveCapacity(buckets.count)
        for (name, members) in buckets {
            // Summing %mem across helpers double counts the frameworks they
            // share, so a group's memory figure is an upper bound. It is still
            // the closest answer available to "what is this app costing me",
            // and it is what Activity Monitor shows too.
            let total = members.reduce(0) { $0 + $1.value }
            let pid = rootPIDs[name] ?? members[0].pid
            grouped.append(
                ProcessUsage(pid: pid,
                             name: name,
                             value: (total * 10).rounded() / 10,
                             members: members.count > 1
                                 ? members.sorted { $0.value > $1.value }
                                 : [])
            )
        }

        // Ties broken by name so the order does not shuffle between ticks when
        // several rows sit at 0.0.
        return Array(grouped.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name
        }.prefix(topCount))
    }

    /// Walks up the parent chain for as long as each step looks like a helper of
    /// the one above it.
    private static func root(of pid: Int32,
                             names: [Int32: String],
                             parents: [Int32: Int32]) -> Int32 {
        var current = pid
        // A parent chain is a handful of steps; the cap only exists so a corrupt
        // or cyclic table cannot spin forever.
        var seen: Set<Int32> = [pid]
        for _ in 0..<32 {
            guard let parent = parents[current],
                  let parentName = names[parent],
                  let currentName = names[current],
                  isHelper(currentName, of: parentName),
                  !seen.contains(parent) else { return current }
            seen.insert(parent)
            current = parent
        }
        return current
    }

    /// Whether `child` names a helper of `parent`: the same name, or the
    /// parent's name followed by a separator.
    ///
    /// The separator matters. Without it "Slackware" would be folded into
    /// "Slack", and any app whose name prefixes another's would swallow it.
    static func isHelper(_ child: String, of parent: String) -> Bool {
        if child == parent { return true }
        guard child.count > parent.count, child.hasPrefix(parent) else { return false }
        let separator = child[child.index(child.startIndex, offsetBy: parent.count)]
        return " .-_(".contains(separator)
    }
}

import Foundation

/// What a process is, in a sentence a person can act on.
///
/// The top-process lists show whatever name the system reports: `mds_stores`,
/// `trustd`, `kernel_task`. Those are meaningless to most people, and the two
/// reasonable reactions to a name you do not recognise are both wrong. Either
/// you ignore a process that genuinely is misbehaving, or you quit one that
/// macOS needs.
public struct GlossaryEntry: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable, CaseIterable {
        case system, background, security, helper, app, developer
    }

    /// How an observed process is recognised as this entry. Checked in the
    /// order given by `ProcessGlossary.lookup`, first hit wins.
    public enum Match: Equatable, Sendable {
        /// Exact process name, the common case.
        case name(String)
        /// Process name suffix. Chromium and Electron apps all name their
        /// child processes "<app> Helper (Renderer)" and similar, so one entry
        /// can explain the pattern rather than needing one per app.
        case nameSuffix(String)
        /// Exact bundle identifier.
        case bundleID(String)
        /// Bundle identifier prefix, for families of helpers.
        case bundleIDPrefix(String)
        /// Executable path prefix.
        case pathPrefix(String)
        /// Executable path suffix.
        case pathSuffix(String)
    }

    public let match: Match
    /// Readable name to show instead of the raw process name.
    public let title: String
    public let category: Category
    /// Who ships it, when that is worth saying. Apple, Microsoft, and so on.
    public let vendor: String?
    /// True when high usage is normal for this process and not a problem to
    /// chase. `kernel_task` deliberately burns CPU to keep the machine cool,
    /// so someone hunting a runaway process should be told to look elsewhere.
    public let expectedHigh: Bool
    public let description: String

    public init(match: Match,
                title: String,
                category: Category,
                vendor: String? = nil,
                expectedHigh: Bool = false,
                description: String) {
        self.match = match
        self.title = title
        self.category = category
        self.vendor = vendor
        self.expectedHigh = expectedHigh
        self.description = description
    }
}

/// Looks up what a process is. Pure, and deliberately free of any I/O so the
/// matching rules can be tested without a process list or a bundle.
public struct ProcessGlossary: Sendable {
    /// `proc_name` fills a buffer of `2 * MAXCOMLEN + 1` bytes, so names it
    /// returns are cut at 32 characters. `ps -o comm` has no such limit and
    /// returns the whole thing.
    ///
    /// That means the same process can arrive under two different names
    /// depending on which list it came from: the CPU and memory lists (via
    /// `ps`) see `com.apple.WebKit.Networking` in full, while the disk list
    /// (via `proc_name`) sees the first 32 characters of it. A name that
    /// arrives at exactly that length is therefore treated as possibly
    /// truncated and allowed to match an entry it is a prefix of.
    static let truncationLimit = 32

    private let entries: [GlossaryEntry]

    public init(entries: [GlossaryEntry]) {
        self.entries = entries
    }

    public var count: Int { entries.count }

    /// Finds the entry describing this process, or nil when it is not one the
    /// glossary knows about. Most processes on a Mac are not, and showing
    /// nothing is the right answer for those.
    ///
    /// - Parameters:
    ///   - name: the process name as reported, possibly truncated at 32 characters.
    ///   - bundleID: bundle identifier, when the caller knows it.
    ///   - path: executable path, when the caller knows it.
    public func lookup(name: String, bundleID: String? = nil, path: String? = nil) -> GlossaryEntry? {
        // Exact name first: the overwhelmingly common case, and the only one
        // that never produces a surprising match.
        if let hit = entries.first(where: { entry in
            if case let .name(n) = entry.match { return n == name }
            return false
        }) { return hit }

        // Then a truncated name against a longer entry. Only when the observed
        // name is long enough to have actually been cut, so a short name can
        // never claim a longer entry by being a prefix of it.
        if name.count >= Self.truncationLimit {
            if let hit = entries.first(where: { entry in
                if case let .name(n) = entry.match { return n.hasPrefix(name) }
                return false
            }) { return hit }
        }

        // Then a name suffix, so the Electron helper convention is covered
        // once. Longest suffix wins, so a specific helper beats the generic
        // "Helper" catch-all.
        let suffixHits = entries.filter { entry in
            if case let .nameSuffix(s) = entry.match { return name.hasSuffix(s) }
            return false
        }
        if let hit = suffixHits.max(by: { a, b in
            guard case let .nameSuffix(sa) = a.match, case let .nameSuffix(sb) = b.match
            else { return false }
            return sa.count < sb.count
        }) { return hit }

        if let bundleID {
            if let hit = entries.first(where: { entry in
                if case let .bundleID(b) = entry.match { return b == bundleID }
                return false
            }) { return hit }

            // Longest prefix wins, so a specific helper beats its family.
            let prefixHits = entries.filter { entry in
                if case let .bundleIDPrefix(p) = entry.match { return bundleID.hasPrefix(p) }
                return false
            }
            if let hit = prefixHits.max(by: { a, b in
                guard case let .bundleIDPrefix(pa) = a.match, case let .bundleIDPrefix(pb) = b.match
                else { return false }
                return pa.count < pb.count
            }) { return hit }
        }

        if let path {
            if let hit = entries.first(where: { entry in
                switch entry.match {
                case let .pathPrefix(p): return path.hasPrefix(p)
                case let .pathSuffix(s): return path.hasSuffix(s)
                default: return false
                }
            }) { return hit }
        }

        return nil
    }
}

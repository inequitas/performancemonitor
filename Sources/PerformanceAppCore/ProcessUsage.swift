import Foundation

/// A single process/app resource-usage row (CPU %, memory %, or network kB/s).
///
/// Pure value type with no AppKit/SwiftUI dependencies. Lives in Core so the
/// `ps`/`nettop` parsers can produce it and be unit tested without the app
/// target. Moved out of `Models.swift` in the Part-B (sampler) decomposition.
public struct ProcessUsage: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let value: Double
    /// The individual processes summed into this row when it stands for an app
    /// and its helpers, largest first. Empty for a plain single process, so a
    /// caller that ignores this field sees the list it always saw.
    ///
    /// Members are always leaf processes: `ProcessGrouping` flattens a parent
    /// chain rather than nesting it, so this never needs walking recursively.
    public let members: [ProcessUsage]

    public var id: String { "\(pid)-\(name)" }

    public init(pid: Int32, name: String, value: Double, members: [ProcessUsage] = []) {
        self.pid = pid
        self.name = name
        self.value = value
        self.members = members
    }
}

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
    public var id: String { "\(pid)-\(name)" }

    public init(pid: Int32, name: String, value: Double) {
        self.pid = pid
        self.name = name
        self.value = value
    }
}

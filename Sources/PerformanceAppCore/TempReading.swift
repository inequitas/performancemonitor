import Foundation

/// A single temperature sensor reading with its curated label and category.
///
/// Pure value type consumed by the SMC sampler and the Thermal detail view.
/// Moved out of `MetricsEngine` (where it was a nested struct) into Core in the
/// Part-B (sampler) decomposition so it can be shared without SwiftUI.
public struct TempReading: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let category: String
    public let celsius: Double

    public init(key: String, label: String, category: String, celsius: Double) {
        self.key = key
        self.label = label
        self.category = category
        self.celsius = celsius
    }
}

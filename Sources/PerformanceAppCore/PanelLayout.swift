import Foundation

/// Anything that can be arranged by `PanelLayout.compute` — a two-per-row grid
/// where full-width items get their own row.
public protocol PanelLayoutItem: Identifiable where ID == String {
    var isFullWidth: Bool { get }
}

public struct PanelRow<Item: PanelLayoutItem>: Identifiable {
    public var first: Item?
    public var second: Item?
    public var full: Item?

    public init(first: Item? = nil, second: Item? = nil, full: Item? = nil) {
        self.first = first
        self.second = second
        self.full = full
    }

    public var id: String {
        [first?.id, second?.id, full?.id].compactMap { $0 }.joined(separator: "-")
    }
}

/// Pure panel-grid layout algorithm: pairs non-full-width items two-per-row in
/// order, and gives full-width items their own row (flushing any pending
/// single item to its own row first).
public enum PanelLayout {
    public static func compute<Item: PanelLayoutItem>(_ items: [Item]) -> [PanelRow<Item>] {
        var rows: [PanelRow<Item>] = []
        var pending: Item?
        for item in items {
            if item.isFullWidth {
                if let p = pending { rows.append(PanelRow(first: p)); pending = nil }
                rows.append(PanelRow(full: item))
            } else {
                if let p = pending {
                    rows.append(PanelRow(first: p, second: item)); pending = nil
                } else {
                    pending = item
                }
            }
        }
        if let p = pending { rows.append(PanelRow(first: p)) }
        return rows
    }
}

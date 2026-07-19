import Testing
@testable import PerformanceAppCore

/// Minimal stand-in for `MetricsEngine.Panel` used only to exercise the
/// generic layout algorithm without pulling in SwiftUI/AppKit.
private struct MockPanel: PanelLayoutItem, Equatable {
    let id: String
    let isFullWidth: Bool
}

@Suite("PanelLayout")
struct PanelLayoutTests {

    private func p(_ id: String, full: Bool = false) -> MockPanel {
        MockPanel(id: id, isFullWidth: full)
    }

    @Test func emptyInputProducesNoRows() {
        #expect(PanelLayout.compute([MockPanel]()).isEmpty)
    }

    @Test func pairsUpTwoNarrowItemsPerRow() {
        let rows = PanelLayout.compute([p("a"), p("b"), p("c"), p("d")])
        #expect(rows.count == 2)
        #expect(rows[0].first?.id == "a")
        #expect(rows[0].second?.id == "b")
        #expect(rows[1].first?.id == "c")
        #expect(rows[1].second?.id == "d")
    }

    @Test func oddNarrowItemGetsTrailingSoloRow() {
        let rows = PanelLayout.compute([p("a"), p("b"), p("c")])
        #expect(rows.count == 2)
        #expect(rows[1].first?.id == "c")
        #expect(rows[1].second == nil)
    }

    @Test func fullWidthItemGetsOwnRow() {
        let rows = PanelLayout.compute([p("network", full: true)])
        #expect(rows.count == 1)
        #expect(rows[0].full?.id == "network")
        #expect(rows[0].first == nil)
        #expect(rows[0].second == nil)
    }

    @Test func pendingNarrowItemFlushesBeforeFullWidthRow() {
        // a is narrow and left pending, then a full-width item arrives —
        // `a` must get flushed to its own row before the full-width row.
        let rows = PanelLayout.compute([p("a"), p("network", full: true), p("b")])
        #expect(rows.count == 3)
        #expect(rows[0].first?.id == "a")
        #expect(rows[0].second == nil)
        #expect(rows[1].full?.id == "network")
        #expect(rows[2].first?.id == "b")
    }

    @Test func consecutiveFullWidthItemsEachGetOwnRow() {
        let rows = PanelLayout.compute([p("network", full: true), p("bluetooth", full: true)])
        #expect(rows.count == 2)
        #expect(rows[0].full?.id == "network")
        #expect(rows[1].full?.id == "bluetooth")
    }

    @Test func rowIdJoinsConstituentIds() {
        let row = PanelRow(first: p("a"), second: p("b"))
        #expect(row.id == "a-b")
    }
}

import SwiftUI
import Charts
import PerformanceAppCore

// 95th-percentile max — prevents rare big spikes from collapsing all smaller bars.
func p95Max(_ a: [Double], _ b: [Double]) -> Double {
    ChartMath.p95Max(a, b)
}

func absoluteMax(_ a: [Double], _ b: [Double]) -> Double {
    ChartMath.absoluteMax(a, b)
}

enum ChartDisplayStyle: String, CaseIterable, Identifiable {
    case line, area, bar
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .line: return "chart.xyaxis.line"
        case .area: return "chart.bar.fill"
        case .bar: return "chart.bar"
        }
    }
}

struct MetricChart: View {
    let values: [Double]
    let unit: String
    /// Fixed upper bound for the y-axis (e.g. 100 for percentages). If nil, scales to the data's max.
    let fixedMax: Double?
    let showAxes: Bool
    /// Show horizontal grid lines only — no labels, no current-value rule. Intended for flipped butterfly halves.
    let showGridLines: Bool
    let color: Color
    let style: ChartDisplayStyle
    let valueFormatter: (Double) -> String

    /// When true, removes the chart's built-in top/bottom scale inset so the data area fills the frame exactly.
    /// Use this for butterfly halves whose external label columns must align with the chart scale.
    let fillFrame: Bool

    init(values: [Double], unit: String = "", fixedMax: Double? = nil, showAxes: Bool = true, showGridLines: Bool = false, fillFrame: Bool = false, color: Color = .accentColor, style: ChartDisplayStyle = .area, valueFormatter: @escaping (Double) -> String = { String(format: "%.1f", $0) }) {
        self.values = values
        self.unit = unit
        self.fixedMax = fixedMax
        self.showAxes = showAxes
        self.showGridLines = showGridLines
        self.fillFrame = fillFrame
        self.color = color
        self.style = style
        self.valueFormatter = valueFormatter
    }

    private var upperBound: Double {
        let dataMax = values.max() ?? 0
        let bound = fixedMax ?? max(dataMax * 1.2, 1)
        return max(bound, 0.001)
    }

    private var currentValue: Double { values.last ?? 0 }

    var body: some View {
        Chart {
            ForEach(values.indices, id: \.self) { index in
                let value = values[index]
                switch style {
                case .area:
                    AreaMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                case .line:
                    LineMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                case .bar:
                    BarMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(color.gradient)
                }
            }
            if showAxes {
                RuleMark(y: .value("Current", currentValue))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(valueFormatter(currentValue))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartYScale(domain: 0...upperBound, range: fillFrame ? .plotDimension(padding: 0) : .plotDimension)
        .chartXAxis(.hidden)
        .chartYAxis {
            if showAxes {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(valueFormatter(v))
                                .font(.caption2)
                        }
                    }
                }
            } else if showGridLines {
                // No labels — use trailing position so no left margin is reserved
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                }
            } else {
                AxisMarks { _ in }
            }
        }
    }
}

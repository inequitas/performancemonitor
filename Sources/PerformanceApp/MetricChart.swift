import SwiftUI
import Charts

enum ChartDisplayStyle: String, CaseIterable, Identifiable {
    case line, area, bar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .line: return "Line"
        case .area: return "Area"
        case .bar: return "Bar"
        }
    }
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
    let color: Color
    let style: ChartDisplayStyle
    let valueFormatter: (Double) -> String

    init(values: [Double], unit: String = "", fixedMax: Double? = nil, showAxes: Bool = true, color: Color = .accentColor, style: ChartDisplayStyle = .area, valueFormatter: @escaping (Double) -> String = { String(format: "%.1f", $0) }) {
        self.values = values
        self.unit = unit
        self.fixedMax = fixedMax
        self.showAxes = showAxes
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
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
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
        .chartYScale(domain: 0...upperBound)
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
            }
        }
    }
}

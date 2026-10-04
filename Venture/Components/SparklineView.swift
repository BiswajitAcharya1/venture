import Charts
import SwiftUI

struct SparklineView: View {
    let primary: [Int]
    var comparison: [Int]?
    var height: CGFloat = 100

    var body: some View {
        Chart {
            ForEach(Array(primary.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Point", index),
                    y: .value("Drift", value),
                    series: .value("Path", "Current")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(VentureTheme.ink)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            if let comparison {
                ForEach(Array(comparison.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Point", index),
                        y: .value("Drift", value),
                        series: .value("Path", "Protected")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(VentureTheme.sage)
                    .lineStyle(StrokeStyle(lineWidth: 1.7, dash: [4, 5]))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityLabel("Drift trend")
    }
}

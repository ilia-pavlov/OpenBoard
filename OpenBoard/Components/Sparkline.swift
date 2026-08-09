import SwiftUI
import Charts

/// Rating-history sparkline: gradient area + line, last point dotted.
struct Sparkline: View {
    var values: [Int]
    var tint: Color = .obGold

    private struct Point: Identifiable {
        let id: Int
        let value: Int
    }

    private var points: [Point] {
        values.enumerated().map { Point(id: $0.offset, value: $0.element) }
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("Game", point.id), y: .value("Rating", point.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("Game", point.id), y: .value("Rating", point.value))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(tint)
            if point.id == points.count - 1 {
                PointMark(x: .value("Game", point.id), y: .value("Rating", point.value))
                    .symbolSize(70)
                    .foregroundStyle(tint)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .accessibilityLabel("Rating history from \(values.first ?? 0) to \(values.last ?? 0)")
        .accessibilityHidden(values.count < 2)
    }

    private var yDomain: ClosedRange<Int> {
        guard let min = values.min(), let max = values.max(), min != max else {
            let v = values.first ?? 0
            return (v - 50)...(v + 50)
        }
        let pad = Swift.max(10, (max - min) / 6)
        return (min - pad)...(max + pad)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    Sparkline(values: [210, 255, 240, 298, 341, 322, 420])
        .frame(width: 260, height: 70)
        .padding()
        .background(Color.obBackground)
        .preferredColorScheme(.dark)
}

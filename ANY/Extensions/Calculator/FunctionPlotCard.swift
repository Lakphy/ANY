import Charts
import SwiftUI

/// Monochrome graph of a function of x, with the y range fitted to the curve.
struct FunctionPlotCard: View {
    let equation: String
    let points: [Point]
    let yDomain: ClosedRange<Double>

    static let xDomain: ClosedRange<Double> = -10...10
    // Charts tints hierarchical styles with the accent color, so the grays are explicit.
    private static let axisColor = Color.primary.opacity(0.35)
    private static let gridColor = Color.primary.opacity(0.08)
    private static let labelColor = Color.primary.opacity(0.4)
    private static let sampleCount = 400

    struct Point: Identifiable {
        let x: Double
        let y: Double
        /// Consecutive finite samples share a segment; gaps (asymptotes, undefined ranges) split it.
        let segment: Int
        var id: Double { x }
    }

    init(equation: String, function: String) {
        self.equation = equation
        let step = (Self.xDomain.upperBound - Self.xDomain.lowerBound) / Double(Self.sampleCount)
        let samples = (0...Self.sampleCount).map { index -> (Double, Double?) in
            let x = Self.xDomain.lowerBound + Double(index) * step
            let y = try? ExpressionEvaluator.evaluate(function, variables: ["x": x])
            return (x, y.flatMap { $0.isFinite ? $0 : nil })
        }
        yDomain = Self.fittedRange(samples.compactMap(\.1))

        var points: [Point] = []
        var segment = 0
        var previous: Double?
        for (x, y) in samples {
            guard let y else {
                segment += 1
                previous = nil
                continue
            }
            // A jump across most of the visible range is an asymptote, not a steep curve.
            if let previous, abs(y - previous) > (yDomain.upperBound - yDomain.lowerBound) * 0.8 {
                segment += 1
            }
            points.append(Point(x: x, y: y, segment: segment))
            previous = y
        }
        self.points = points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardHeader(symbol: "function", title: "函数图像")
            Text(equation)
                .font(Theme.Typography.headline.monospaced())
                .lineLimit(1)
                .textSelection(.enabled)

            Chart {
                RuleMark(y: .value("y", 0))
                    .foregroundStyle(Self.axisColor)
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                RuleMark(x: .value("x", 0))
                    .foregroundStyle(Self.axisColor)
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                ForEach(points) { point in
                    LineMark(x: .value("x", point.x), y: .value("y", point.y), series: .value("segment", point.segment))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
            }
            .chartXScale(domain: Self.xDomain)
            .chartYScale(domain: yDomain)
            .chartLegend(.hidden)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) {
                    AxisGridLine().foregroundStyle(Self.gridColor)
                    AxisValueLabel().font(Theme.Typography.micro).foregroundStyle(Self.labelColor)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(Self.gridColor)
                    AxisValueLabel().font(Theme.Typography.micro).foregroundStyle(Self.labelColor)
                }
            }
            .frame(height: 148)
        }
    }

    /// Fits the y axis to the bulk of the curve, ignoring the extreme 2% on each side so
    /// asymptotes (tan, 1/x) don't flatten everything else.
    private static func fittedRange(_ values: [Double]) -> ClosedRange<Double> {
        guard !values.isEmpty else { return -1...1 }
        let sorted = values.sorted()
        let trim = sorted.count / 50
        var low = sorted[trim]
        var high = sorted[sorted.count - 1 - trim]
        if high - low < 1e-9 {
            low -= 1
            high += 1
        }
        let padding = (high - low) * 0.1
        return (low - padding)...(high + padding)
    }
}

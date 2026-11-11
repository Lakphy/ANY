import Charts
import Foundation
import Observation
import SwiftUI

@Observable
final class CalculatorExtension: ANYExtension {
    let manifest = ExtensionManifest(
        id: "calculator",
        title: "计算器",
        subtitle: "在搜索框中直接计算数学表达式",
        icon: .symbol("plus.forwardslash.minus")
    )

    static let fractionDigitOptions = [0, 2, 4, 6, 10]

    var maximumFractionDigits: Int {
        didSet { storage.set(maximumFractionDigits, forKey: Keys.maximumFractionDigits) }
    }

    var usesGroupingSeparator: Bool {
        didSet { storage.set(usesGroupingSeparator, forKey: Keys.usesGroupingSeparator) }
    }

    @ObservationIgnored private let storage = ExtensionStorage(extensionID: "calculator")

    private enum Keys {
        static let maximumFractionDigits = "maximumFractionDigits"
        static let usesGroupingSeparator = "usesGroupingSeparator"
    }

    init() {
        maximumFractionDigits = storage.value(Int.self, forKey: Keys.maximumFractionDigits) ?? 10
        usesGroupingSeparator = storage.value(Bool.self, forKey: Keys.usesGroupingSeparator) ?? true
    }

    func results(for query: SearchQuery) async -> [ResultItem] {
        let expression = query.text
        if let function = ExpressionEvaluator.functionOfX(expression) {
            return [plotItem(for: function)]
        }
        guard ExpressionEvaluator.looksLikeExpression(expression),
              let value = try? ExpressionEvaluator.evaluate(expression),
              value.isFinite
        else { return [] }

        let display = format(value, forDisplay: true)
        let raw = format(value, forDisplay: false)

        return [
            ResultItem(
                id: "result",
                title: display,
                subtitle: "= \(expression)",
                icon: manifest.icon,
                kind: .instant(score: 1000),
                actions: [
                    .copy(raw, title: "复制结果", shortcut: nil),
                    .copy("\(expression) = \(raw)", title: "复制算式"),
                    ItemAction("用结果继续计算", systemImage: "arrow.turn.down.right") { _ in .setQuery(raw) },
                ],
                card: AnyView(CalculationCard(expression: expression, result: display))
            ),
        ]
    }

    private func plotItem(for function: String) -> ResultItem {
        let equation = "y = \(function)"
        return ResultItem(
            id: "plot",
            title: equation,
            subtitle: "函数图像",
            icon: .symbol("function"),
            kind: .instant(score: 1000),
            actions: [
                .copy(equation, title: "复制函数", shortcut: nil),
            ],
            card: AnyView(FunctionPlotCard(equation: equation, function: function))
        )
    }

    func makeSettingsView() -> AnyView? {
        AnyView(CalculatorSettingsView(ext: self))
    }

    /// Display output follows the user's locale and grouping preference; copied output is plain digits.
    func format(_ value: Double, forDisplay: Bool) -> String {
        let magnitude = abs(value)
        if magnitude >= 1e15 || (magnitude < 1e-10 && magnitude > 0) {
            return String(format: "%.\(max(maximumFractionDigits, 1))g", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        if forDisplay {
            formatter.usesGroupingSeparator = usesGroupingSeparator
        } else {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.usesGroupingSeparator = false
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct CalculatorSettingsView: View {
    @Bindable var ext: CalculatorExtension

    var body: some View {
        Section {
            Picker("最多小数位数", selection: $ext.maximumFractionDigits) {
                ForEach(CalculatorExtension.fractionDigitOptions, id: \.self) { digits in
                    Text(digits == 0 ? "取整" : "\(digits) 位").tag(digits)
                }
            }
            Toggle("显示千位分隔符", isOn: $ext.usesGroupingSeparator)
            LabeledContent("示例", value: ext.format(1_234_567.891_234_5, forDisplay: true))
        } header: {
            Text("结果格式")
        } footer: {
            Text("支持 + − × ÷ ^ %、括号，以及 sqrt、sin、cos、log、ln、π 等。复制结果时始终不带分隔符。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CalculationCard: View {
    let expression: String
    let result: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardHeader(symbol: "plus.forwardslash.minus", title: "计算器")
            HStack(spacing: Theme.Space.l) {
                column(expression, caption: "算式", font: Theme.Typography.title, style: .secondary)
                Image(systemName: "arrow.right")
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(.tertiary)
                column(result, caption: "结果", font: Theme.Typography.display, style: .primary)
            }
            .frame(height: 56)
        }
    }

    private func column(_ text: String, caption: String, font: Font, style: HierarchicalShapeStyle) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Text(text)
                .font(font.monospacedDigit())
                .foregroundStyle(style)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .textSelection(.enabled)
            Text(caption)
                .font(Theme.Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

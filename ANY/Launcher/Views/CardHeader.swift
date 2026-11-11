import SwiftUI

/// The small caption line at the top of every result card: what the card is, plus optional
/// trailing metadata such as a timestamp.
struct CardHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.m)
            trailing
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(.tertiary)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(symbol: String, title: String) {
        self.init(symbol: symbol, title: title) { EmptyView() }
    }
}

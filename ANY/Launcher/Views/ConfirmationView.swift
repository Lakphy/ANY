import SwiftUI

/// Replaces the list inside the panel while an action awaits confirmation (↩ confirms, esc cancels).
struct ConfirmationView: View {
    let pending: LauncherViewModel.PendingConfirmation
    let model: LauncherViewModel

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: pending.isDestructive ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: Theme.Space.s) {
                Text(pending.confirmation.title)
                    .font(Theme.Typography.headline)
                if let message = pending.confirmation.message {
                    Text(message)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: Theme.Space.m) {
                Button("取消", action: model.cancelPending)
                    .buttonStyle(.glass)
                Button(pending.confirmation.confirmTitle, action: model.confirmPending)
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .buttonSizing(.flexible)
            .frame(width: 280)
            .padding(.top, Theme.Space.xs)
        }
        .padding(Theme.Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

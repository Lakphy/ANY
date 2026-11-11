import AppKit
import SwiftUI

/// A brief confirmation near the bottom of the screen, e.g. "已复制到剪贴板".
struct Toast {
    enum Style {
        case success
        case info
        case warning
        case failure

        var symbol: String {
            switch self {
            case .success: "checkmark"
            case .info: "info"
            case .warning: "exclamationmark"
            case .failure: "xmark"
            }
        }

        var duration: Duration {
            switch self {
            case .success, .info: .seconds(1.6)
            case .warning, .failure: .seconds(3)
            }
        }
    }

    var message: String
    var style: Style = .success
}

/// Shows one toast at a time in a floating glass capsule. A new toast replaces the current one.
final class ToastController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// Transparent margin so the glass edge and its shadow aren't clipped by the window.
    private static let margin: CGFloat = Theme.Space.xxl

    func show(_ toast: Toast) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let isReplacing = panel.isVisible

        let hosting = NSHostingView(rootView: ToastView(toast: toast).padding(Self.margin))
        hosting.wantsLayer = true
        let size = hosting.fittingSize
        panel.contentView = hosting

        if let screen = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.minY + screen.height * 0.1)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        panel.orderFrontRegardless()

        // Glass can't render through window transparency, so the toast scales rather than fades.
        ScaleAnimation.animate(hosting, from: isReplacing ? 0.92 : 0.5, to: 1, curve: .spring(duration: 0.4, bounce: 0.3))

        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: toast.style.duration)
            guard !Task.isCancelled else { return }
            ScaleAnimation.animate(hosting, from: 1, to: 0.01, curve: .easeIn(duration: 0.18))
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }
}

private struct ToastView: View {
    let toast: Toast

    @State private var hasAppeared = false

    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let maxMessageWidth: CGFloat = 380

    /// Single-line width up to a cap; longer messages wrap onto a second line.
    private var messageWidth: CGFloat {
        let width = (toast.message as NSString).size(withAttributes: [.font: Self.font]).width
        return min(ceil(width) + 1, Self.maxMessageWidth)
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: toast.style.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: Theme.IconSize.small, height: Theme.IconSize.small)
                .background(.fill.secondary, in: .circle)
                .symbolEffect(.bounce, value: hasAppeared)

            Text(toast.message)
                .font(Font(Self.font))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: messageWidth, alignment: .leading)
        }
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .glassEffect(.regular, in: .capsule)
        .onAppear { hasAppeared = true }
    }
}

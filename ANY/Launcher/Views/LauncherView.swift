import AppKit
import SwiftUI

enum LauncherLayout {
    /// Nine rows.
    static let listHeight: CGFloat = Theme.Metrics.rowHeight * 9
    /// Transparent margin so the glass edge and its shadow aren't clipped by the window.
    static let margin: CGFloat = Theme.Space.xxxl
    /// Bottom-right corner, measured into the glass, that grabs the resize handle.
    static let resizeCornerReach: CGFloat = 44

    static var panelSize: CGSize {
        CGSize(width: Theme.Metrics.panelWidth, height: Theme.Metrics.searchBarHeight + 1 + listHeight)
    }

    static var windowSize: CGSize {
        CGSize(width: panelSize.width + margin * 2, height: panelSize.height + margin * 2)
    }

    /// Smallest pinned panel that still fits the search bar and a few rows.
    static var minimumWindowSize: CGSize {
        let panel = CGSize(
            width: 440,
            height: Theme.Metrics.searchBarHeight + 1 + Theme.Metrics.rowHeight * 4
        )
        return CGSize(width: panel.width + margin * 2, height: panel.height + margin * 2)
    }
}

/// One glass surface, Spotlight-style: search field, hairline, content.
/// Everything inside the panel is plain content; the panel itself is the only glass.
struct LauncherView: View {
    @Bindable var model: LauncherViewModel
    var chrome: LauncherChrome

    @State private var pointerInCorner = false
    @State private var pinHovered = false
    @State private var windowBounds = LauncherLayout.windowSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
    }

    private var showsPinButton: Bool {
        chrome.isPinned || pointerInCorner || pinHovered
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(model: model)
                .frame(height: Theme.Metrics.searchBarHeight)
                .padding(.horizontal, Theme.Metrics.contentInset)

            if let toolbar = model.pageToolbar {
                toolbar
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Theme.Metrics.contentInset + Theme.Metrics.leadingGlyphWidth + Theme.Metrics.iconGap)
                    .padding(.trailing, Theme.Metrics.contentInset)
                    .padding(.bottom, Theme.Space.m)
                    .transition(.opacity)
            }

            Divider()
                .padding(.horizontal, Theme.Metrics.contentInset)

            ZStack {
                if let pending = model.pendingConfirmation {
                    ConfirmationView(pending: pending, model: model)
                        .transition(.pop)
                } else {
                    page
                        .id(model.current.id)
                        .transition(.page(forward: model.isNavigatingForward))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerShape(shape)
        .glassEffect(.regular, in: shape)
        .overlay(alignment: .bottomTrailing) {
            ResizeHandle()
                .opacity(chrome.isPinned ? 1 : 0)
                .animation(.easeOut(duration: 0.16), value: chrome.isPinned)
                .allowsHitTesting(chrome.isPinned)
        }
        .padding(LauncherLayout.margin)
        .overlay(alignment: .topTrailing) {
            PinButton(isPinned: chrome.isPinned) {
                withAnimation(Motion.overlay) { chrome.togglePin() }
            }
            .onHover { pinHovered = $0 }
            .opacity(showsPinButton ? 1 : 0)
            .scaleEffect(showsPinButton ? 1 : 0.82)
            .animation(Motion.overlay, value: showsPinButton)
            .allowsHitTesting(showsPinButton)
            .padding(.top, LauncherLayout.margin - PinButton.diameter / 2)
            .padding(.trailing, LauncherLayout.margin - PinButton.diameter / 2)
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { windowBounds = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                pointerInCorner = pinCornerContains(point)
            case .ended:
                pointerInCorner = false
            }
        }
    }

    /// Top-right of the window, including the pin, so the button stays up while the pointer moves onto it.
    private func pinCornerContains(_ point: CGPoint) -> Bool {
        point.x >= windowBounds.width - 76 && point.y <= 64
    }

    @ViewBuilder
    private var page: some View {
        switch model.current.page {
        case .list(let source):
            if source.showsDetail {
                SplitListView(model: model, source: source)
            } else {
                ResultListView(model: model, emptyText: source.emptyText)
            }
        case .detail(let detail) where detail.wrapsInScrollView:
            ScrollView {
                detail.content
                    .padding(Theme.Metrics.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        case .detail(let detail):
            detail.content
        }
    }
}

/// Pops out of the panel's top-right corner. Once pinned, it stays so the panel can be unpinned.
private struct PinButton: View {
    static let diameter: CGFloat = 28

    let isPinned: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isPinned || isHovering ? .primary : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.diameter, height: Self.diameter)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .animation(Motion.hoverSelection, value: isHovering)
        .help(isPinned ? "取消固定" : "固定在最前台")
        .accessibilityLabel(isPinned ? "取消固定" : "固定在最前台")
    }
}

/// A short piece of the panel's own corner, inset so it sits just inside the glass.
/// Same center and continuous curve as the panel, which is the iPad window grip.
private struct ResizeHandle: View {
    private static let cursor = NSCursor.frameResize(position: .bottomRight, directions: .all)
    private static let inset: CGFloat = 6
    private static let length: CGFloat = 18
    private static let lineWidth: CGFloat = 2.5

    @State private var isHovering = false

    var body: some View {
        let corner = Theme.Radius.panel - Self.inset
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .stroke(
                Color.primary.opacity(isHovering ? 0.72 : 0.34),
                style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
            )
            .frame(width: corner * 2, height: corner * 2)
            .padding(Self.lineWidth / 2)
            .mask(alignment: .bottomTrailing) {
                Rectangle().frame(width: Self.length, height: Self.length)
            }
            .padding(Self.inset - Self.lineWidth / 2)
            .frame(
                width: LauncherLayout.resizeCornerReach,
                height: LauncherLayout.resizeCornerReach,
                alignment: .bottomTrailing
            )
            .contentShape(.rect)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    Self.cursor.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .animation(Motion.hoverSelection, value: isHovering)
            .help("拖动调整大小")
            .accessibilityLabel("调整大小")
    }
}

private struct SearchField: View {
    @Bindable var model: LauncherViewModel

    var body: some View {
        HStack(spacing: Theme.Metrics.iconGap) {
            ZStack {
                if model.canGoBack {
                    BackGlyph(icon: model.pageIcon, action: model.pop)
                        .id(model.current.id)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .transaction { $0.animation = nil }
            .frame(width: Theme.Metrics.leadingGlyphWidth, height: Theme.Metrics.leadingGlyphWidth)

            if case .detail = model.current.page {
                Text(model.pageTitle)
                    .font(Theme.Typography.title)
                    .lineLimit(1)
                    .transition(.opacity)
                Spacer()
            } else {
                SearchTextField(
                    text: $model.query,
                    placeholder: model.searchPlaceholder,
                    font: Theme.Typography.titleNSFont,
                    focusRequest: model.focusRequest
                )
            }
        }
    }
}

/// Takes the magnifier's place inside an extension page: shows the page's glyph, turns into a back chevron on hover.
private struct BackGlyph: View {
    let icon: ItemIcon
    let action: () -> Void

    @State private var isHovering = false

    private var symbol: String {
        if isHovering { return "chevron.backward" }
        if case .symbol(let name) = icon { return name }
        return "chevron.backward"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: isHovering ? 14 : 16, weight: .medium))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: Theme.Metrics.leadingGlyphWidth, height: Theme.Metrics.leadingGlyphWidth)
                .background(.fill.tertiary.opacity(isHovering ? 1 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("返回（⌫）")
    }
}

import SwiftUI

/// One glass surface, like the launcher: tool header, hairline, the selected text and the tool's
/// content, hairline, action hints. Sized to its content up to the room beside the selection.
struct SelectionPopupView: View {
    let model: SelectionPopupModel

    @State private var scrollContentHeight: CGFloat = 0

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
    }

    private var actions: [ItemAction] { model.session?.actions ?? [] }

    private var scrollMaxHeight: CGFloat {
        let chrome = SelectionPopupLayout.headerHeight + (actions.isEmpty ? 0 : SelectionPopupLayout.footerHeight) + 2
        return max(model.maxHeight - chrome, 80)
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectionPopupHeader(model: model)

            Divider()
                .padding(.horizontal, Theme.Metrics.contentInset)

            ScrollView {
                scrollContent
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { scrollContentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .frame(height: min(scrollContentHeight, scrollMaxHeight))

            if !actions.isEmpty {
                Divider()
                    .padding(.horizontal, Theme.Metrics.contentInset)
                SelectionPopupFooter(actions: actions, perform: model.perform)
            }
        }
        .frame(width: SelectionPopupLayout.width)
        .containerShape(shape)
        .glassEffect(.regular, in: shape)
        .scaleEffect(model.isPresented ? 1 : SelectionPopupLayout.hiddenScale, anchor: model.growthAnchor)
        .padding(SelectionPopupLayout.margin)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { model.reportHeight($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.placement == .below ? .top : .bottom)
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let selection = model.selection {
                SelectedTextQuote(text: selection.text)
            }
            if let session = model.session {
                session.content
                    .id(model.toolID)
                    .transition(.opacity)
            }
        }
        .padding(Theme.Metrics.listInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The text the tools are working on, quiet and above their results.
private struct SelectedTextQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Capsule()
                .fill(.fill.secondary)
                .frame(width: 2)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Metrics.rowInset)
        .padding(.top, Theme.Space.xs)
        .padding(.bottom, Theme.Space.s)
    }
}

// MARK: - Header

private struct SelectionPopupHeader: View {
    @Bindable var model: SelectionPopupModel

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ToolSwitcher(model: model)

            Group {
                if let accessory = model.session?.accessory {
                    accessory
                } else if let tool = model.tool {
                    Text(tool.title)
                        .font(Theme.Typography.bodyMedium)
                }
            }
            .id(model.toolID)
            .transition(.opacity)

            Spacer(minLength: Theme.Space.s)

            if model.isPinned {
                HeaderIconButton(symbol: "xmark", help: "关闭（esc）") { model.close() }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            HeaderIconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                help: model.isPinned ? "取消固定" : "固定，点击别处时不关闭",
                isActive: model.isPinned
            ) {
                withAnimation(Motion.overlay) { model.isPinned.toggle() }
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: SelectionPopupLayout.headerHeight)
        .background {
            Color.clear
                .contentShape(.rect)
                .gesture(WindowDragGesture())
        }
    }
}

/// The active tool's glyph, or a row of them to switch between when there are several.
private struct ToolSwitcher: View {
    let model: SelectionPopupModel

    @Namespace private var selection

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            if model.tools.count > 1 {
                ForEach(Array(model.tools.enumerated()), id: \.element.id) { index, tool in
                    ToolButton(
                        tool: tool,
                        shortcut: index < 9 ? "⌘\(index + 1)" : nil,
                        isSelected: tool.id == model.toolID,
                        selection: selection
                    ) {
                        model.selectTool(tool.id)
                    }
                }
            } else if let tool = model.tool {
                Image(systemName: tool.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Metrics.leadingGlyphWidth, height: Theme.Metrics.leadingGlyphWidth)
            }
        }
    }
}

private struct ToolButton: View {
    let tool: SelectionTool
    let shortcut: String?
    let isSelected: Bool
    let selection: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected || isHovering ? .primary : .secondary)
                .frame(width: Theme.Metrics.leadingGlyphWidth, height: Theme.Metrics.leadingGlyphWidth)
                .background {
                    if isSelected {
                        Circle()
                            .fill(.fill.secondary)
                            .matchedGeometryEffect(id: "tool", in: selection)
                    } else if isHovering {
                        Circle().fill(.fill.quaternary)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .animation(Motion.hoverSelection, value: isHovering)
        .help(shortcut.map { "\(tool.title)（\($0)）" } ?? tool.title)
        .accessibilityLabel(tool.title)
    }
}

private struct HeaderIconButton: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive || isHovering ? .primary : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Theme.Metrics.leadingGlyphWidth, height: Theme.Metrics.leadingGlyphWidth)
                .background(.fill.tertiary.opacity(isHovering ? 1 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .animation(Motion.hoverSelection, value: isHovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Footer

/// The session's actions as clickable key hints: the first two on the left, one more on the right.
private struct SelectionPopupFooter: View {
    let actions: [ItemAction]
    let perform: (ItemAction) -> Void

    private var trailing: (ItemAction, KeyShortcut)? {
        for action in actions.dropFirst(2) {
            if let shortcut = action.shortcut { return (action, shortcut) }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(Array(actions.prefix(2).enumerated()), id: \.element.id) { index, action in
                KeyHintButton(title: action.title, keys: index == 0 ? "↩" : "⌘↩") { perform(action) }
            }
            Spacer(minLength: Theme.Space.s)
            if let (action, shortcut) = trailing {
                KeyHintButton(title: action.title, keys: shortcut.displayText) { perform(action) }
            }
        }
        .padding(.horizontal, Theme.Space.xs + Theme.Space.xxs)
        .frame(height: SelectionPopupLayout.footerHeight)
    }
}

private struct KeyHintButton: View {
    let title: String
    let keys: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs + Theme.Space.xxs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isHovering ? .primary : .secondary)
                Text(keys)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Space.xs)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Theme.Space.xs, style: .continuous))
            }
            .padding(.leading, Theme.Space.s)
            .padding(.trailing, Theme.Space.xs)
            .frame(height: 24)
            .background(.fill.quaternary.opacity(isHovering ? 1 : 0), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .animation(Motion.hoverSelection, value: isHovering)
    }
}

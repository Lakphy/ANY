import SwiftUI

struct ResultListView: View {
    let model: LauncherViewModel
    let emptyText: String
    /// Sidebar mode for two-column pages: smaller rows, and clicking selects rather than runs,
    /// since the selection drives the detail pane.
    var isSidebar = false

    @Namespace private var selection

    var body: some View {
        if !model.current.hasLoaded && model.items.isEmpty && !model.query.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.current.hasLoaded && model.items.isEmpty {
            emptyState
                .controlSize(isSidebar ? .small : .regular)
        } else {
            list
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.query.isEmpty {
            ContentUnavailableView(emptyText, systemImage: "tray")
        } else {
            ContentUnavailableView.search(text: model.query)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.current.sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(Theme.Typography.captionSemibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Theme.Metrics.rowInset)
                                .padding(.top, Theme.Space.m)
                                .padding(.bottom, Theme.Space.xs)
                        }
                        ForEach(section.items) { item in
                            row(for: item)
                        }
                    }
                }
            }
            .contentMargins(.horizontal, Theme.Metrics.listInset, for: .scrollContent)
            .contentMargins(.vertical, Theme.Space.s, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .onChange(of: model.scrollRequest) {
                guard let id = model.current.selectedID else { return }
                withAnimation(Motion.selection) { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private func row(for item: ResultItem) -> some View {
        let isSelected = item.id == model.current.selectedID
        if let card = item.card, item.isInteractive || item.allowsTextSelection, !isSidebar {
            // Interactive content reacts to the pointer itself; a selection fill on top of it
            // would flash on every hover.
            ResultCard(content: card, isSelected: isSelected && !item.isInteractive, selection: selection)
                .contentShape(.rect)
                .simultaneousGesture(TapGesture().onEnded {
                    withAnimation(Motion.selection) { model.select(item.id) }
                })
                .modifier(RowBehavior(item: item, isSelected: isSelected, isSidebar: isSidebar, model: model))
        } else {
            Button {
                if isSidebar {
                    withAnimation(Motion.selection) { model.select(item.id) }
                } else {
                    model.select(item.id)
                    model.performPrimary()
                }
            } label: {
                if let card = item.card, !isSidebar {
                    ResultCard(content: card, isSelected: isSelected, selection: selection)
                } else {
                    ResultRow(item: item, isSelected: isSelected, selection: selection, isCompact: isSidebar)
                }
            }
            .buttonStyle(ResultRowButtonStyle())
            .focusEffectDisabled()
            .modifier(RowBehavior(item: item, isSelected: isSelected, isSidebar: isSidebar, model: model))
        }
    }
}

/// Selection tracking, hover and the context menu, shared by every kind of row.
private struct RowBehavior: ViewModifier {
    let item: ResultItem
    let isSelected: Bool
    let isSidebar: Bool
    let model: LauncherViewModel

    func body(content: Content) -> some View {
        content
            .id(item.id)
            .onGeometryChange(for: CGRect?.self, of: { isSelected ? $0.frame(in: .global) : nil }) { frame in
                if let frame { model.selectedRowFrame = frame }
            }
            .onContinuousHover { phase in
                if !isSidebar, case .active = phase { model.hoverSelect(item.id) }
            }
            .contextMenu {
                ForEach(Array(item.actions.enumerated()), id: \.element.id) { index, action in
                    Button {
                        model.select(item.id)
                        model.performAction(at: index)
                    } label: {
                        if let systemImage = action.systemImage {
                            Label(action.title, systemImage: systemImage)
                        } else {
                            Text(action.title)
                        }
                    }
                }
            }
    }
}

/// Rows sink slightly while pressed.
private struct ResultRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Large full-width result, e.g. a calculation or a clipboard hit. Shares the selection
/// highlight with rows, so the highlight morphs between the card and the rows below it.
struct ResultCard: View {
    let content: AnyView
    let isSelected: Bool
    let selection: Namespace.ID

    var body: some View {
        let shape = Theme.itemShape(radius: Theme.Radius.card)
        content
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(.fill.quaternary)
                if isSelected {
                    shape
                        .fill(.fill.secondary)
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .padding(.vertical, Theme.Space.xs)
    }
}

struct ResultRow: View {
    let item: ResultItem
    let isSelected: Bool
    let selection: Namespace.ID
    var isCompact = false

    var body: some View {
        HStack(spacing: Theme.Metrics.iconGap) {
            ItemIconView(icon: item.icon, size: isCompact ? Theme.IconSize.small : Theme.IconSize.row)

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(item.title)
                    .font(Theme.Typography.body)
                    .lineLimit(1)
                if !isCompact, let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Space.m)

            if let accessory = item.accessory {
                Text(accessory)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Theme.Metrics.rowInset)
        .frame(height: isCompact ? Theme.Metrics.compactRowHeight : Theme.Metrics.rowHeight)
        .background {
            if isSelected {
                Theme.itemShape(radius: isCompact ? Theme.Radius.compactRow : Theme.Radius.row)
                    .fill(.fill.secondary)
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
    }
}

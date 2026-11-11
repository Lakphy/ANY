import SwiftUI

/// Two-column list page: a compact list on the left, the selected item's detail on the right.
struct SplitListView: View {
    let model: LauncherViewModel
    let source: any ListDataSource

    var body: some View {
        HStack(spacing: 0) {
            ResultListView(model: model, emptyText: source.emptyText, isSidebar: true)
                .frame(width: Theme.Metrics.sidebarWidth)

            Divider()

            ZStack {
                if let item = model.selectedItem, let detail = source.detail(for: item) {
                    detail
                        .id(item.id)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.selection, value: model.current.selectedID)
        }
    }
}

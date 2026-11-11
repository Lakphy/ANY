import SwiftUI

/// A screen in the launcher's navigation stack. The root page is the global search;
/// extensions push their own list or detail pages from actions.
enum LauncherPage {
    case list(any ListDataSource)
    case detail(DetailPage)
}

protocol ListDataSource: AnyObject {
    var title: String { get }
    var icon: ItemIcon { get }
    var searchPlaceholder: String { get }
    var emptyText: String { get }
    /// Text already in the search field when the page opens.
    var initialQuery: String { get }

    func sections(for query: SearchQuery) async -> [ResultSection]

    /// A row of controls below the search field. Call `reload` after a change that affects the results.
    func toolbar(query: String, reload: @escaping () -> Void) -> AnyView?

    /// Content for the right-hand pane. Returning non-nil switches the page to a two-column
    /// layout: a compact list on the left, the selected item's detail on the right.
    func detail(for item: ResultItem) -> AnyView?
    var showsDetail: Bool { get }
}

extension ListDataSource {
    var emptyText: String { "没有结果" }
    var initialQuery: String { "" }
    func toolbar(query: String, reload: @escaping () -> Void) -> AnyView? { nil }
    func detail(for item: ResultItem) -> AnyView? { nil }
    var showsDetail: Bool { false }
}

struct DetailPage {
    var title: String
    var icon: ItemIcon
    var actions: [ItemAction]
    /// False for content that scrolls by itself, such as a `Form`.
    var wrapsInScrollView: Bool
    var content: AnyView

    init<Content: View>(
        title: String,
        icon: ItemIcon,
        actions: [ItemAction] = [],
        wrapsInScrollView: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.actions = actions
        self.wrapsInScrollView = wrapsInScrollView
        self.content = AnyView(content())
    }
}

import AppKit
import Observation
import SwiftUI

@Observable
final class LauncherViewModel {
    struct PageState: Identifiable {
        let id = UUID()
        let page: LauncherPage
        var query = ""
        var sections: [ResultSection] = []
        var selectedID: String?
        var hasLoaded = false
    }

    struct PendingConfirmation {
        let confirmation: ItemAction.Confirmation
        let action: ItemAction
        let item: ResultItem?
        let isDestructive: Bool
    }

    private(set) var stack: [PageState]
    private(set) var pendingConfirmation: PendingConfirmation?
    /// Incremented whenever the search field should regain focus.
    private(set) var focusRequest = 0
    /// Incremented when the list should scroll the selection into view. Hover selection doesn't
    /// request scrolling, so the row under the pointer never jumps away.
    private(set) var scrollRequest = 0
    /// Direction of the latest page change, so the incoming page slides in from the right side.
    private(set) var isNavigatingForward = true

    /// Frame of the selected row in the panel's (flipped) coordinates, used to anchor the actions menu.
    @ObservationIgnored var selectedRowFrame: CGRect?
    @ObservationIgnored weak var host: (any ExtensionHost)?
    @ObservationIgnored private let root: any ListDataSource
    @ObservationIgnored private let usage: UsageStore
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var lastHoverLocation: NSPoint?

    init(root: any ListDataSource, usage: UsageStore) {
        self.root = root
        self.usage = usage
        self.stack = [PageState(page: .list(root))]
    }

    // MARK: - Current page

    var current: PageState { stack[stack.endIndex - 1] }
    var canGoBack: Bool { stack.count > 1 }

    var query: String {
        get { current.query }
        set {
            guard newValue != current.query else { return }
            updateCurrent { $0.query = newValue }
            reload(preservingSelection: false)
        }
    }

    var pageTitle: String {
        switch current.page {
        case .list(let source): source.title
        case .detail(let detail): detail.title
        }
    }

    var pageIcon: ItemIcon {
        switch current.page {
        case .list(let source): source.icon
        case .detail(let detail): detail.icon
        }
    }

    var searchPlaceholder: String {
        if case .list(let source) = current.page { return source.searchPlaceholder }
        return ""
    }

    var items: [ResultItem] { current.sections.flatMap(\.items) }

    var selectedItem: ResultItem? {
        guard let id = current.selectedID else { return nil }
        return items.first { $0.id == id }
    }

    var currentActions: [ItemAction] {
        switch current.page {
        case .list: selectedItem?.actions ?? []
        case .detail(let detail): detail.actions
        }
    }

    static func shortcut(for action: ItemAction, at index: Int) -> KeyShortcut? {
        switch index {
        case 0: .primary
        case 1: .secondary
        default: action.shortcut
        }
    }

    // MARK: - Lifecycle

    func prepareForPresentation() {
        searchTask?.cancel()
        pushTask?.cancel()
        stack = [PageState(page: .list(root))]
        pendingConfirmation = nil
        focusRequest += 1
        lastHoverLocation = NSEvent.mouseLocation
        reload(preservingSelection: false)
    }

    private func reload(preservingSelection: Bool) {
        guard case .list(let source) = current.page else { return }
        let pageID = current.id
        let query = SearchQuery(raw: current.query)
        let previousIndex = items.firstIndex { $0.id == current.selectedID }

        searchTask?.cancel()
        searchTask = Task {
            let sections = await source.sections(for: query)
            guard !Task.isCancelled, let index = stack.firstIndex(where: { $0.id == pageID }) else { return }

            let ids = sections.flatMap { $0.items.map(\.id) }
            var selection = ids.first
            if preservingSelection {
                if let selected = stack[index].selectedID, ids.contains(selected) {
                    selection = selected
                } else if let previousIndex, !ids.isEmpty {
                    selection = ids[min(previousIndex, ids.count - 1)]
                }
            }
            stack[index].sections = sections
            stack[index].selectedID = selection
            stack[index].hasLoaded = true
            scrollRequest += 1
        }
    }

    var pageToolbar: AnyView? {
        guard case .list(let source) = current.page else { return nil }
        return source.toolbar(query: query) { [weak self] in
            self?.reload(preservingSelection: false)
            self?.focusSearchField()
        }
    }

    func focusSearchField() {
        focusRequest += 1
    }

    // MARK: - Navigation

    /// List pages are loaded before they're pushed, so they slide in already populated. Pages that
    /// open with a query (which may hit the network) slide in at once and fill in when ready.
    func push(_ page: LauncherPage) {
        pushTask?.cancel()
        if case .list(let source) = page, !source.initialQuery.isEmpty {
            isNavigatingForward = true
            withAnimation(Motion.page) { stack.append(PageState(page: page, query: source.initialQuery)) }
            focusRequest += 1
            reload(preservingSelection: false)
            return
        }
        pushTask = Task {
            let state = await Self.loadedState(for: page)
            guard !Task.isCancelled else { return }
            isNavigatingForward = true
            withAnimation(Motion.page) { stack.append(state) }
            focusRequest += 1
            scrollRequest += 1
        }
    }

    /// Jumps straight to `source` on top of the root page, e.g. for ⌘, → Settings.
    /// Without animation when the panel is about to appear, so it opens already there.
    func open(_ source: any ListDataSource, selecting itemID: String? = nil, animated: Bool) async {
        if case .list(let top) = current.page, top === source {
            if let itemID, items.contains(where: { $0.id == itemID }) {
                withAnimation(Motion.selection) { updateCurrent { $0.selectedID = itemID } }
                scrollRequest += 1
            }
            return
        }
        pushTask?.cancel()
        pendingConfirmation = nil
        // Like `push`, a page that opens with a query (which may hit the network) shows at once
        // and fills in when ready.
        let hasQuery = !source.initialQuery.isEmpty
        var state = hasQuery
            ? PageState(page: .list(source), query: source.initialQuery)
            : await Self.loadedState(for: .list(source))
        if let itemID, state.sections.contains(where: { $0.items.contains { $0.id == itemID } }) {
            state.selectedID = itemID
        }
        isNavigatingForward = true
        var transaction = Transaction(animation: animated ? Motion.page : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            stack.removeSubrange(1...)
            stack.append(state)
        }
        focusRequest += 1
        scrollRequest += 1
        if hasQuery {
            reload(preservingSelection: false)
        }
    }

    private static func loadedState(for page: LauncherPage) async -> PageState {
        var state = PageState(page: page)
        if case .list(let source) = page {
            state.sections = await source.sections(for: SearchQuery(raw: ""))
            state.selectedID = state.sections.first?.items.first?.id
            state.hasLoaded = true
        }
        return state
    }

    func pop() {
        guard canGoBack else { return }
        isNavigatingForward = false
        withAnimation(Motion.page) { _ = stack.removeLast() }
        focusRequest += 1
        reload(preservingSelection: true)
    }

    /// Returns false when there's nothing left to unwind and the launcher should close.
    func handleEscape() -> Bool {
        if canGoBack {
            pop()
        } else if !query.isEmpty {
            query = ""
        } else {
            return false
        }
        return true
    }

    // MARK: - Selection

    func select(_ id: String) {
        updateCurrent { $0.selectedID = id }
    }

    /// Selects the hovered row, but only when the pointer itself moved. Rows also report hover
    /// when keyboard navigation scrolls them under a resting pointer; those are ignored.
    func hoverSelect(_ id: String) {
        let location = NSEvent.mouseLocation
        guard location != lastHoverLocation else { return }
        lastHoverLocation = location
        guard current.selectedID != id else { return }
        withAnimation(Motion.hoverSelection) {
            updateCurrent { $0.selectedID = id }
        }
    }

    func moveSelection(by delta: Int) {
        let ids = items.map(\.id)
        guard !ids.isEmpty else { return }
        let currentIndex = ids.firstIndex { $0 == current.selectedID } ?? -1
        let next = min(max(currentIndex + delta, 0), ids.count - 1)
        guard ids[next] != current.selectedID else { return }
        withAnimation(Motion.selection) {
            updateCurrent { $0.selectedID = ids[next] }
        }
        scrollRequest += 1
    }

    // MARK: - Actions

    func performPrimary() {
        guard selectedItem?.isInteractive != true else { return }
        performAction(at: 0)
    }

    func performSecondary() {
        guard selectedItem?.isInteractive != true else { return }
        performAction(at: 1)
    }

    func performAction(at index: Int) {
        let actions = currentActions
        guard actions.indices.contains(index) else { return }
        perform(actions[index])
    }

    func performShortcut(matching event: NSEvent) -> Bool {
        guard let action = currentActions.first(where: { $0.shortcut?.matches(event) == true }) else { return false }
        perform(action)
        return true
    }

    func confirmPending() {
        guard let pending = pendingConfirmation else { return }
        withAnimation(Motion.overlay) { pendingConfirmation = nil }
        execute(pending.action, on: pending.item)
    }

    func cancelPending() {
        withAnimation(Motion.overlay) { pendingConfirmation = nil }
    }

    private func perform(_ action: ItemAction) {
        let item = selectedItem
        if let confirmation = action.confirmation {
            withAnimation(Motion.overlay) {
                pendingConfirmation = PendingConfirmation(
                    confirmation: confirmation,
                    action: action,
                    item: item,
                    isDestructive: action.style == .destructive
                )
            }
            return
        }
        execute(action, on: item)
    }

    private func execute(_ action: ItemAction, on item: ResultItem?) {
        guard let host else { return }
        if let item, !canGoBack {
            usage.recordUse(of: item.id)
        }
        let context = ActionContext(query: current.query, host: host)
        Task {
            let outcome = await action.handler(context)
            apply(outcome)
        }
    }

    private func apply(_ outcome: ActionOutcome) {
        switch outcome {
        case .dismiss: host?.hideLauncher()
        case .keepOpen: break
        case .refresh: reload(preservingSelection: true)
        case .push(let page): push(page)
        case .pop: pop()
        case .setQuery(let text): query = text
        }
    }

    private func updateCurrent(_ update: (inout PageState) -> Void) {
        update(&stack[stack.endIndex - 1])
    }
}

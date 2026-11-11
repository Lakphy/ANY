import SwiftUI

/// Something ANY can do with text selected in any app, offered by an extension through
/// `ANYExtension.selectionTools()`. The selection popup shows one tool at a time, with a
/// switcher in its header when several are available.
struct SelectionTool: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let makeSession: @MainActor (SelectionContext) -> any SelectionSession
}

struct SelectionContext {
    let selection: TextSelection
    /// Hiding the launcher through this host closes the popup instead, so actions such as
    /// `ItemAction.paste` put their text in place of the selection.
    let host: any ExtensionHost
}

/// One tool working on one selection: what the popup shows and what its keys do.
protocol SelectionSession: AnyObject {
    /// Shown in the popup header next to the tool, e.g. translation's language menu.
    var accessory: AnyView? { get }
    var content: AnyView { get }
    /// Listed in the popup's footer. The first runs with ↩ and the second with ⌘↩; the rest by
    /// their own shortcut. `.dismiss` closes the popup.
    var actions: [ItemAction] { get }
    /// What ⌘C copies when no text in the popup is selected.
    var copyableText: String? { get }

    /// ↑ and ↓, e.g. to pick between several results. Returns false when there's nothing to move.
    func moveSelection(by delta: Int) -> Bool
    /// The popup closed or moved on to another tool; stop work in flight.
    func end()
}

extension SelectionSession {
    var accessory: AnyView? { nil }
    var copyableText: String? { nil }
    func moveSelection(by delta: Int) -> Bool { false }
    func end() {}
}

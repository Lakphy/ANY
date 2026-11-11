import SwiftUI

/// Static description of a built-in extension, shown in Settings and used for namespacing.
struct ExtensionManifest {
    let id: String
    let title: String
    let subtitle: String
    let icon: ItemIcon
    var isEnabledByDefault = true
    var canBeDisabled = true
}

/// A first-party feature module. Every capability in ANY (apps, calculator, clipboard, ...)
/// is an extension registered in `ExtensionRegistry`, so new features plug in without
/// touching the launcher or search engine.
///
/// Contract for `results(for:)`:
/// - `.application` / `.command` items are candidates; the search engine fuzzy-filters and ranks them.
///   Return the full candidate set regardless of the query.
/// - `.instant` items are computed answers for the query (e.g. calculator) and are always shown.
/// - `.fallback` items are offered when nothing else is wanted (e.g. web search).
protocol ANYExtension: AnyObject {
    var manifest: ExtensionManifest { get }

    /// Called when the extension is enabled (at launch or when toggled on in Settings).
    func activate(context: ExtensionContext)
    /// Called when the extension is disabled or the app terminates.
    func deactivate()
    /// Called right before the launcher panel becomes visible.
    func launcherWillAppear()

    func results(for query: SearchQuery) async -> [ResultItem]

    /// Extension-specific `Section`s for its page in Settings, shown below the enable switch.
    /// Extensions own their preferences; return nil when there's nothing to configure.
    func makeSettingsView() -> AnyView?

    /// What the extension can do with text selected in any app, offered in the selection popup.
    func selectionTools() -> [SelectionTool]
}

extension ANYExtension {
    func activate(context: ExtensionContext) {}
    func deactivate() {}
    func launcherWillAppear() {}
    func makeSettingsView() -> AnyView? { nil }
    func selectionTools() -> [SelectionTool] { [] }
}

struct SearchQuery: Equatable {
    let raw: String

    var text: String { raw.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { text.isEmpty }
}

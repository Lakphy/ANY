import AppKit
import SwiftUI

enum ItemIcon {
    /// SF Symbol on a neutral tile. ANY's own UI is strictly black, white and gray.
    case symbol(String)
    /// Finder icon of the file or bundle at the path.
    case file(String)
    case image(NSImage)
    case emoji(String)
}

struct ResultItem: Identifiable {
    enum Kind {
        case application
        case command
        /// A computed answer for the current query; higher scores rank first. Scores below
        /// `SearchEngine.strongInstantScore` give way to a strong title match.
        case instant(score: Double)
        case fallback
    }

    var id: String
    var title: String
    var subtitle: String?
    var icon: ItemIcon
    var accessory: String?
    var keywords: [String]
    var kind: Kind
    /// The first action is primary (↩), the second secondary (⌘↩).
    var actions: [ItemAction]
    /// When set, the item is shown as a large full-width card with this content instead of a row.
    var card: AnyView?
    /// The card handles its own clicks (links, tabs, copy buttons): clicking it only selects it and
    /// ↩ does nothing, so using the content never closes the launcher. Actions stay in ⌘K.
    var isInteractive: Bool
    /// The card's text can be selected with the mouse, so clicking it only selects the item
    /// instead of running the primary action. ↩ still works.
    var allowsTextSelection: Bool

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: ItemIcon,
        accessory: String? = nil,
        keywords: [String] = [],
        kind: Kind = .command,
        actions: [ItemAction],
        card: AnyView? = nil,
        isInteractive: Bool = false,
        allowsTextSelection: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accessory = accessory
        self.keywords = keywords
        self.kind = kind
        self.actions = actions
        self.card = card
        self.isInteractive = isInteractive
        self.allowsTextSelection = allowsTextSelection
    }
}

struct ResultSection: Identifiable {
    let id: String
    var title: String?
    var items: [ResultItem]
}

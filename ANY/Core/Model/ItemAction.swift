import Foundation

struct ItemAction: Identifiable {
    enum Style {
        case regular
        case destructive
    }

    struct Confirmation {
        var title: String
        var message: String?
        var confirmTitle: String
    }

    let id: String
    var title: String
    var systemImage: String?
    var shortcut: KeyShortcut?
    var style: Style
    /// When set, the launcher asks the user before running the handler.
    var confirmation: Confirmation?
    var handler: @MainActor (ActionContext) async -> ActionOutcome

    init(
        _ title: String,
        systemImage: String? = nil,
        shortcut: KeyShortcut? = nil,
        style: Style = .regular,
        confirmation: Confirmation? = nil,
        handler: @escaping @MainActor (ActionContext) async -> ActionOutcome
    ) {
        self.id = title
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.style = style
        self.confirmation = confirmation
        self.handler = handler
    }
}

struct ActionContext {
    let query: String
    let host: any ExtensionHost
}

/// What the launcher should do after an action finishes.
enum ActionOutcome {
    case dismiss
    case keepOpen
    /// Re-run the current page's search, keeping the selection where possible.
    case refresh
    case push(LauncherPage)
    case pop
    case setQuery(String)
}

import AppKit

/// The ⌘K actions menu as a native `NSMenu`, so it gets the system's Liquid Glass menu
/// appearance, keyboard navigation and shortcut rendering for free.
final class ActionMenu: NSObject {
    private let menu = NSMenu()
    private let perform: (Int) -> Void

    init(title: String?, actions: [ItemAction], perform: @escaping (Int) -> Void) {
        self.perform = perform
        super.init()
        menu.autoenablesItems = false

        if let title {
            menu.addItem(.sectionHeader(title: title))
        }

        var addedDestructiveSeparator = false
        for (index, action) in actions.enumerated() {
            if action.style == .destructive && !addedDestructiveSeparator && index > 0 {
                menu.addItem(.separator())
                addedDestructiveSeparator = true
            }

            let item = NSMenuItem(title: action.title, action: #selector(run(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let systemImage = action.systemImage {
                item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
            }
            if let shortcut = LauncherViewModel.shortcut(for: action, at: index) {
                item.keyEquivalent = shortcut.keyEquivalent
                item.keyEquivalentModifierMask = shortcut.modifiers
            }
            menu.addItem(item)
        }
    }

    /// Blocks until the menu is dismissed; menu items only hold `self` weakly, so the caller keeps it alive.
    func popUp(at point: NSPoint, in view: NSView) {
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc private func run(_ sender: NSMenuItem) {
        perform(sender.tag)
    }
}

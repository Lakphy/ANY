import SwiftUI

/// Settings inside the launcher, as two columns: app-level pages and every extension on the
/// left, iOS-style, with the selected page's form on the right.
final class SettingsDataSource: ListDataSource {
    let title = "设置"
    let icon = ItemIcon.symbol("gearshape.fill")
    let searchPlaceholder = "搜索设置…"
    let showsDetail = true

    private let settings: AppSettings
    private let registry: ExtensionRegistry
    private let matcher = FuzzyMatcher()

    private static let extensionPrefix = "extension."

    static func itemID(forExtension id: String) -> String {
        extensionPrefix + id
    }

    init(settings: AppSettings, registry: ExtensionRegistry) {
        self.settings = settings
        self.registry = registry
    }

    func sections(for query: SearchQuery) async -> [ResultSection] {
        let sections = [
            ResultSection(id: "app", title: nil, items: appItems),
            ResultSection(id: "extensions", title: "扩展", items: extensionItems),
        ]
        guard !query.isEmpty else { return sections }

        let matches = sections.flatMap(\.items)
            .compactMap { item in matcher.score(query: query.text, item: item).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        return [ResultSection(id: "matches", title: nil, items: matches)]
    }

    func detail(for item: ResultItem) -> AnyView? {
        switch item.id {
        case "general":
            return AnyView(GeneralSettingsView(settings: settings))
        case "about":
            return AnyView(ScrollView { AboutView().padding(Theme.Metrics.contentInset).frame(maxWidth: .infinity, alignment: .leading) })
        default:
            let id = item.id.dropFirst(Self.extensionPrefix.count)
            guard let ext = registry.extensions.first(where: { $0.manifest.id == id }) else { return nil }
            return AnyView(ExtensionSettingsPage(ext: ext, registry: registry))
        }
    }

    private var appItems: [ResultItem] {
        [
            ResultItem(
                id: "general",
                title: "通用",
                icon: .symbol("gearshape.fill"),
                keywords: ["general", "hotkey", "快捷键", "登录", "selection", "划词", "辅助功能"],
                actions: []
            ),
            ResultItem(
                id: "about",
                title: "关于 ANY",
                icon: .symbol("info.circle.fill"),
                keywords: ["about", "version", "版本"],
                actions: []
            ),
        ]
    }

    private var extensionItems: [ResultItem] {
        registry.extensions.map { ext in
            let manifest = ext.manifest
            return ResultItem(
                id: Self.extensionPrefix + manifest.id,
                title: manifest.title,
                subtitle: manifest.subtitle,
                icon: manifest.icon,
                keywords: [manifest.id],
                actions: []
            )
        }
    }
}

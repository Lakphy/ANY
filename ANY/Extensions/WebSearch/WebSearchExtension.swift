import Observation
import SwiftUI

@Observable
final class WebSearchExtension: ANYExtension {
    let manifest = ExtensionManifest(
        id: "web-search",
        title: "网页搜索",
        subtitle: "用搜索引擎搜索输入内容，或直接打开网址",
        icon: .symbol("globe")
    )

    struct Engine: Identifiable {
        let id: String
        let name: String
        let urlTemplate: String
        let symbol: String
    }

    let engines = [
        Engine(id: "google", name: "Google", urlTemplate: "https://www.google.com/search?q=%@", symbol: "magnifyingglass"),
        Engine(id: "bing", name: "Bing", urlTemplate: "https://www.bing.com/search?q=%@", symbol: "magnifyingglass"),
        Engine(id: "baidu", name: "百度", urlTemplate: "https://www.baidu.com/s?wd=%@", symbol: "pawprint.fill"),
        Engine(id: "github", name: "GitHub", urlTemplate: "https://github.com/search?q=%@", symbol: "chevron.left.forwardslash.chevron.right"),
    ]

    private(set) var disabledEngineIDs: Set<String> {
        didSet { storage.set(disabledEngineIDs, forKey: Keys.disabledEngineIDs) }
    }

    var opensURLsDirectly: Bool {
        didSet { storage.set(opensURLsDirectly, forKey: Keys.opensURLsDirectly) }
    }

    @ObservationIgnored private let storage = ExtensionStorage(extensionID: "web-search")

    private enum Keys {
        static let disabledEngineIDs = "disabledEngineIDs"
        static let opensURLsDirectly = "opensURLsDirectly"
    }

    private static let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))

    init() {
        disabledEngineIDs = storage.value(Set<String>.self, forKey: Keys.disabledEngineIDs) ?? []
        opensURLsDirectly = storage.value(Bool.self, forKey: Keys.opensURLsDirectly) ?? true
    }

    func isEngineEnabled(_ id: String) -> Bool {
        !disabledEngineIDs.contains(id)
    }

    func setEngine(_ id: String, enabled: Bool) {
        if enabled {
            disabledEngineIDs.remove(id)
        } else {
            disabledEngineIDs.insert(id)
        }
    }

    func results(for query: SearchQuery) async -> [ResultItem] {
        guard !query.isEmpty else { return [] }
        let text = query.text
        var items: [ResultItem] = []

        if opensURLsDirectly, let url = Self.detectURL(in: text) {
            items.append(ResultItem(
                id: "open-url",
                title: "打开 \(url.absoluteString)",
                icon: .symbol("safari.fill"),
                kind: .instant(score: 900),
                actions: [
                    .open(url, title: "在浏览器中打开", systemImage: "safari"),
                    .copy(url.absoluteString, title: "复制网址"),
                ]
            ))
        }

        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) else { return items }
        for engine in engines where isEngineEnabled(engine.id) {
            guard let url = URL(string: engine.urlTemplate.replacingOccurrences(of: "%@", with: encoded)) else { continue }
            items.append(ResultItem(
                id: engine.id,
                title: "使用 \(engine.name) 搜索",
                subtitle: "“\(text)”",
                icon: .symbol(engine.symbol),
                kind: .fallback,
                actions: [
                    .open(url, title: "在 \(engine.name) 中搜索", systemImage: "magnifyingglass"),
                    .copy(url.absoluteString, title: "复制搜索链接"),
                ]
            ))
        }
        return items
    }

    func makeSettingsView() -> AnyView? {
        AnyView(WebSearchSettingsView(ext: self))
    }

    private static func detectURL(in text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return URL(string: text)
        }
        let pattern = #"^(localhost|([a-z0-9-]+\.)+[a-z]{2,})(:\d+)?(/.*)?$"#
        guard lowercased.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://\(text)")
    }
}

private struct WebSearchSettingsView: View {
    @Bindable var ext: WebSearchExtension

    var body: some View {
        Section {
            ForEach(ext.engines) { engine in
                Toggle(isOn: Binding(
                    get: { ext.isEngineEnabled(engine.id) },
                    set: { ext.setEngine(engine.id, enabled: $0) }
                )) {
                    Label {
                        Text(engine.name)
                    } icon: {
                        ItemIconView(icon: .symbol(engine.symbol), size: Theme.IconSize.small)
                    }
                }
            }
        } header: {
            Text("搜索引擎")
        } footer: {
            Text("开启的搜索引擎会出现在搜索结果底部。")
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("识别网址并直接打开", isOn: $ext.opensURLsDirectly)
        } footer: {
            Text("输入如 github.com 的内容时，将其作为第一个结果直接打开。")
                .foregroundStyle(.secondary)
        }
    }
}

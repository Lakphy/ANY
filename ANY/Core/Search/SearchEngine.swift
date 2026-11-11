import Foundation

/// The root page: aggregates results from every enabled extension and ranks them.
final class SearchEngine: ListDataSource {
    let title = "ANY"
    let icon = ItemIcon.symbol("sparkle.magnifyingglass")
    let searchPlaceholder = "搜索应用、命令，或输入算式…"

    private let registry: ExtensionRegistry
    private let usage: UsageStore
    private let matcher = FuzzyMatcher()

    private static let recentLimit = 6
    private static let resultLimit = 60
    /// Instant results at or above this score always lead; weaker ones (such as a clipboard hit)
    /// follow the results when the query already matches an app or command by title prefix.
    static let strongInstantScore: Double = 100
    private static let strongMatchScore: Double = 0.8

    init(registry: ExtensionRegistry, usage: UsageStore) {
        self.registry = registry
        self.usage = usage
    }

    func sections(for query: SearchQuery) async -> [ResultSection] {
        var candidates: [ResultItem] = []
        for ext in registry.enabledExtensions {
            let namespace = ext.manifest.id
            for var item in await ext.results(for: query) {
                item.id = "\(namespace)/\(item.id)"
                candidates.append(item)
            }
        }
        return query.isEmpty ? emptyStateSections(candidates) : rankedSections(candidates, query: query)
    }

    private func emptyStateSections(_ candidates: [ResultItem]) -> [ResultSection] {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recents = usage.recentIDs(limit: Self.recentLimit).compactMap { byID[$0] }
        let recentIDs = Set(recents.map(\.id))

        let commands = candidates.filter {
            if case .command = $0.kind { return !recentIDs.contains($0.id) }
            return false
        }

        return [
            ResultSection(id: "recent", title: "最近使用", items: recents),
            ResultSection(id: "commands", title: "命令", items: commands),
        ].filter { !$0.items.isEmpty }
    }

    private func rankedSections(_ candidates: [ResultItem], query: SearchQuery) -> [ResultSection] {
        var instant: [(item: ResultItem, score: Double)] = []
        var matched: [(item: ResultItem, score: Double)] = []
        var fallbacks: [ResultItem] = []
        var hasStrongMatch = false

        for item in candidates {
            switch item.kind {
            case .instant(let score):
                instant.append((item, score))
            case .fallback:
                fallbacks.append(item)
            case .application, .command:
                if let match = matcher.score(query: query.text, item: item) {
                    matched.append((item, match * 100 + usage.boost(for: item.id)))
                    hasStrongMatch = hasStrongMatch || match >= Self.strongMatchScore
                }
            }
        }

        instant.sort { $0.score > $1.score }
        matched.sort { $0.score > $1.score || ($0.score == $1.score && $0.item.title < $1.item.title) }

        let (leading, trailing) = hasStrongMatch
            ? (instant.filter { $0.score >= Self.strongInstantScore }, instant.filter { $0.score < Self.strongInstantScore })
            : (instant, [])

        return [
            ResultSection(id: "instant", title: nil, items: leading.map(\.item)),
            ResultSection(id: "results", title: "结果", items: matched.prefix(Self.resultLimit).map(\.item)),
            ResultSection(id: "instant-trailing", title: nil, items: trailing.map(\.item)),
            ResultSection(id: "fallback", title: "使用 “\(query.text)” 进行…", items: fallbacks),
        ].filter { !$0.items.isEmpty }
    }
}

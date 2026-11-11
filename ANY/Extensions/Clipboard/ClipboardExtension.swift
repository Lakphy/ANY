import Observation
import SwiftUI

@Observable
final class ClipboardExtension: ANYExtension {
    let manifest = ExtensionManifest(
        id: "clipboard",
        title: "剪贴板历史",
        subtitle: "记录并搜索复制过的文本",
        icon: .symbol("doc.on.clipboard.fill")
    )

    private(set) var history: ClipboardHistory?
    let preferences = ClipboardPreferences(storage: ExtensionStorage(extensionID: "clipboard"))

    func activate(context: ExtensionContext) {
        let history = ClipboardHistory(
            fileURL: context.storage.dataDirectory.appending(path: "history.json"),
            preferences: preferences
        )
        preferences.onLimitChange = { [weak history] in history?.trimToLimit() }
        history.startMonitoring()
        self.history = history
    }

    func deactivate() {
        history?.stopMonitoring()
        history = nil
        preferences.onLimitChange = nil
    }

    func results(for query: SearchQuery) async -> [ResultItem] {
        guard let history else { return [] }
        var items = [
            ResultItem(
                id: "history",
                title: "剪贴板历史",
                subtitle: "剪贴板",
                icon: manifest.icon,
                keywords: ["clipboard history", "paste"],
                kind: .command,
                actions: [
                    ItemAction("打开剪贴板历史", systemImage: "list.bullet.rectangle") { _ in
                        .push(.list(ClipboardHistoryDataSource(history: history)))
                    },
                ]
            ),
        ]
        if let hit = bestMatch(for: query, in: history) {
            items.append(hitItem(for: hit, query: query.text, history: history))
        }
        return items
    }

    private static let minimumQueryLength = 2

    /// The most recent entry containing the query.
    private func bestMatch(for query: SearchQuery, in history: ClipboardHistory) -> ClipboardEntry? {
        guard query.text.count >= Self.minimumQueryLength else { return nil }
        return history.entries.first { $0.text.localizedCaseInsensitiveContains(query.text) }
    }

    private func hitItem(for entry: ClipboardEntry, query: String, history: ClipboardHistory) -> ResultItem {
        ResultItem(
            id: "hit",
            title: entry.text,
            subtitle: "剪贴板",
            icon: manifest.icon,
            kind: .instant(score: 50),
            actions: [
                .copy(entry.text, title: "复制", shortcut: nil),
                .paste(entry.text),
                ItemAction("在剪贴板历史中查看", systemImage: "list.bullet.rectangle") { _ in
                    .push(.list(ClipboardHistoryDataSource(history: history)))
                },
            ],
            card: AnyView(ClipboardHitCard(entry: entry, query: query))
        )
    }

    func makeSettingsView() -> AnyView? {
        AnyView(ClipboardSettingsView(ext: self))
    }
}

private struct ClipboardSettingsView: View {
    let ext: ClipboardExtension

    var body: some View {
        @Bindable var preferences = ext.preferences

        Section("记录") {
            Picker("最多保留", selection: $preferences.historyLimit) {
                ForEach(ClipboardPreferences.limitOptions, id: \.self) { limit in
                    Text("\(limit) 条").tag(limit)
                }
            }
            Toggle("忽略密码等敏感内容", isOn: $preferences.ignoresSensitiveContent)
        }

        Section {
            LabeledContent("当前记录", value: "\(ext.history?.entries.count ?? 0) 条")
            HStack {
                Spacer()
                TwoStepButton("清空历史…", confirmTitle: "再次点击以清空") { ext.history?.removeAll() }
                    .disabled(ext.history?.entries.isEmpty ?? true)
            }
        } footer: {
            Text("历史只保存在本机，不会上传。清空后无法恢复。")
                .foregroundStyle(.secondary)
        }
    }
}

final class ClipboardHistoryDataSource: ListDataSource {
    let title = "剪贴板历史"
    let icon = ItemIcon.symbol("doc.on.clipboard.fill")
    let searchPlaceholder = "搜索剪贴板历史…"
    let emptyText = "剪贴板历史为空"

    private let history: ClipboardHistory
    private let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    init(history: ClipboardHistory) {
        self.history = history
    }

    func sections(for query: SearchQuery) async -> [ResultSection] {
        let entries = query.isEmpty
            ? history.entries
            : history.entries.filter { $0.text.localizedCaseInsensitiveContains(query.text) }
        guard !entries.isEmpty else { return [] }
        return [ResultSection(id: "entries", title: "\(entries.count) 条记录", items: entries.map(makeItem))]
    }

    private func makeItem(for entry: ClipboardEntry) -> ResultItem {
        ResultItem(
            id: entry.id.uuidString,
            title: preview(of: entry.text),
            subtitle: entry.sourceApp,
            icon: .symbol("text.alignleft"),
            accessory: dateFormatter.localizedString(for: entry.date, relativeTo: .now),
            actions: [
                .paste(entry.text),
                .copy(entry.text, title: "复制到剪贴板"),
                ItemAction("查看全文", systemImage: "eye", shortcut: .init(.character("y"), modifiers: [.command])) { [weak self] _ in
                    guard let self else { return .keepOpen }
                    return .push(.detail(detailPage(for: entry)))
                },
                ItemAction("删除此记录", systemImage: "trash", shortcut: .init(.character("x"), modifiers: [.control]), style: .destructive) { [history] _ in
                    history.remove(entry.id)
                    return .refresh
                },
                ItemAction(
                    "清空全部记录",
                    systemImage: "trash.slash",
                    shortcut: .init(.character("x"), modifiers: [.control, .shift]),
                    style: .destructive,
                    confirmation: .init(title: "清空剪贴板历史？", message: "所有记录将被删除，此操作无法撤销。", confirmTitle: "清空")
                ) { [history] _ in
                    history.removeAll()
                    return .refresh
                },
            ]
        )
    }

    private func detailPage(for entry: ClipboardEntry) -> DetailPage {
        DetailPage(
            title: "剪贴板内容",
            icon: icon,
            actions: [.paste(entry.text), .copy(entry.text, title: "复制到剪贴板")]
        ) {
            Text(entry.text)
                .font(Theme.Typography.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    private func preview(of text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ⏎ ")
        return String(collapsed.prefix(120))
    }
}

/// A clipboard entry matching the search, with the match emphasized.
private struct ClipboardHitCard: View {
    let entry: ClipboardEntry
    let query: String

    private static let excerptLead = 60

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(symbol: "doc.on.clipboard", title: entry.sourceApp.map { "剪贴板 · \($0)" } ?? "剪贴板") {
                Text(entry.date, format: .relative(presentation: .named))
            }

            Text(highlightedExcerpt)
                .font(Theme.Typography.body)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Starts shortly before the first match so it's visible even deep inside long text.
    private var highlightedExcerpt: AttributedString {
        var text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
           text.distance(from: text.startIndex, to: first.lowerBound) > Self.excerptLead {
            let start = text.index(first.lowerBound, offsetBy: -Self.excerptLead)
            text = "…" + text[start...]
        }

        var attributed = AttributedString(text)
        attributed.foregroundColor = .secondary
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let match = attributed[searchRange].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[match].foregroundColor = .primary
            attributed[match].font = Theme.Typography.bodySemibold
            searchRange = match.upperBound..<attributed.endIndex
        }
        return attributed
    }
}

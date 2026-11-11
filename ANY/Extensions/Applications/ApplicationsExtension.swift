import AppKit
import Observation
import SwiftUI

@Observable
final class ApplicationsExtension: ANYExtension {
    let manifest = ExtensionManifest(
        id: "applications",
        title: "应用程序",
        subtitle: "搜索并打开已安装的应用",
        icon: .symbol("square.grid.2x2.fill")
    )

    private(set) var indexedCount = 0
    private(set) var lastIndexed: Date?
    private(set) var isIndexing = false

    @ObservationIgnored private var items: [ResultItem] = []
    @ObservationIgnored private var indexTask: Task<Void, Never>?

    private static let reindexInterval: TimeInterval = 60

    func activate(context: ExtensionContext) {
        reindex()
    }

    func deactivate() {
        indexTask?.cancel()
        indexTask = nil
        isIndexing = false
        items = []
    }

    func launcherWillAppear() {
        if let lastIndexed, Date.now.timeIntervalSince(lastIndexed) < Self.reindexInterval { return }
        reindex()
    }

    func results(for query: SearchQuery) async -> [ResultItem] {
        items
    }

    func reindex() {
        guard indexTask == nil else { return }
        isIndexing = true
        indexTask = Task {
            let apps = await Task.detached(priority: .utility) { ApplicationIndexer.scan() }.value
            guard !Task.isCancelled else { return }
            items = apps.map(Self.makeItem)
            indexedCount = apps.count
            lastIndexed = .now
            isIndexing = false
            indexTask = nil
        }
    }

    func makeSettingsView() -> AnyView? {
        AnyView(ApplicationsSettingsView(ext: self))
    }

    private static func makeItem(for app: InstalledApp) -> ResultItem {
        let url = URL(filePath: app.path)
        return ResultItem(
            id: app.path,
            title: app.name,
            icon: .file(app.path),
            keywords: app.fileName == app.name ? [] : [app.fileName],
            kind: .application,
            actions: [
                ItemAction("打开应用", systemImage: "arrow.up.forward.app") { _ in
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    return .dismiss
                },
                .showInFinder(app.path),
                .copy(app.path, title: "复制路径"),
            ]
        )
    }
}

private struct ApplicationsSettingsView: View {
    let ext: ApplicationsExtension

    var body: some View {
        Section("索引") {
            LabeledContent("已索引应用", value: "\(ext.indexedCount) 个")
            LabeledContent("上次更新") {
                if let lastIndexed = ext.lastIndexed {
                    Text(lastIndexed, format: .relative(presentation: .named))
                } else {
                    Text("尚未索引")
                }
            }
            HStack {
                Spacer()
                if ext.isIndexing {
                    ProgressView().controlSize(.small)
                }
                Button("重新索引", action: ext.reindex)
                    .disabled(ext.isIndexing)
            }
        }

        Section {
            ForEach(ApplicationIndexer.searchRoots, id: \.self) { url in
                Label(url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
            }
        } header: {
            Text("搜索范围")
        } footer: {
            Text("每次打开 ANY 时，若距上次索引超过 1 分钟会自动刷新。")
                .foregroundStyle(.secondary)
        }
    }
}

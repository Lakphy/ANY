import SwiftUI

/// Commands for ANY itself.
final class CoreExtension: ANYExtension {
    let manifest = ExtensionManifest(
        id: "any",
        title: "ANY",
        subtitle: "ANY 自身的设置与管理命令",
        icon: .symbol("sparkle.magnifyingglass"),
        canBeDisabled: false
    )

    private(set) lazy var commands: [ResultItem] = [
        ResultItem(
            id: "settings",
            title: "ANY 设置",
            subtitle: "ANY",
            icon: .symbol("gearshape.fill"),
            keywords: ["settings", "preferences"],
            actions: [
                ItemAction("打开设置", systemImage: "gearshape") { context in
                    context.host.openSettings()
                    return .keepOpen
                },
            ]
        ),
        ResultItem(
            id: "about",
            title: "关于 ANY",
            subtitle: "ANY",
            icon: .symbol("info.circle.fill"),
            keywords: ["about", "version"],
            actions: [
                ItemAction("查看", systemImage: "info.circle") { [manifest] _ in
                    .push(.detail(DetailPage(title: "关于 ANY", icon: manifest.icon) { AboutView() }))
                },
            ]
        ),
        ResultItem(
            id: "quit",
            title: "退出 ANY",
            subtitle: "ANY",
            icon: .symbol("power"),
            keywords: ["quit", "exit"],
            actions: [
                ItemAction("退出", systemImage: "power", style: .destructive) { _ in
                    NSApp.terminate(nil)
                    return .dismiss
                },
            ]
        ),
    ]

    func results(for query: SearchQuery) async -> [ResultItem] {
        commands
    }

    func makeSettingsView() -> AnyView? {
        AnyView(CoreSettingsView(commands: commands))
    }
}

private struct CoreSettingsView: View {
    let commands: [ResultItem]

    var body: some View {
        Section {
            ForEach(commands) { command in
                Label {
                    Text(command.title)
                } icon: {
                    ItemIconView(icon: command.icon, size: Theme.IconSize.small)
                }
            }
        } header: {
            Text("命令")
        } footer: {
            Text("唤起快捷键与登录启动可在「通用」中修改。")
                .foregroundStyle(.secondary)
        }
    }
}

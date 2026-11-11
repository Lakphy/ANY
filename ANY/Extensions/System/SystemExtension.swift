import Observation
import SwiftUI

@Observable
final class SystemExtension: ANYExtension {
    let manifest = ExtensionManifest(
        id: "system",
        title: "系统",
        subtitle: "锁屏、睡眠、深色模式等系统命令",
        icon: .symbol("gearshape.2.fill")
    )

    /// Commands the user turned off in Settings.
    private(set) var hiddenCommandIDs: Set<String> {
        didSet { storage.set(hiddenCommandIDs, forKey: "hiddenCommandIDs") }
    }

    @ObservationIgnored private let storage = ExtensionStorage(extensionID: "system")

    init() {
        hiddenCommandIDs = storage.value(Set<String>.self, forKey: "hiddenCommandIDs") ?? []
    }

    @ObservationIgnored private(set) lazy var commands: [ResultItem] = [
        command("lock-screen", "锁定屏幕", symbol: "lock.fill", keywords: ["lock screen"]) {
            SystemActions.lockScreen()
        },
        command("sleep", "睡眠", symbol: "moon.zzz.fill", keywords: ["sleep"]) {
            SystemActions.sleep()
        },
        command("toggle-appearance", "切换深色模式", symbol: "circle.lefthalf.filled", keywords: ["dark mode", "appearance", "theme"]) {
            try SystemActions.toggleDarkMode()
        },
        command("screen-saver", "启动屏幕保护程序", symbol: "sparkles.tv.fill", keywords: ["screen saver"]) {
            SystemActions.startScreenSaver()
        },
        command(
            "empty-trash", "清空废纸篓", symbol: "trash.fill", keywords: ["empty trash"],
            confirmation: .init(title: "清空废纸篓？", message: "废纸篓中的项目将被永久删除，此操作无法撤销。", confirmTitle: "清空")
        ) {
            try SystemActions.emptyTrash()
        },
        command(
            "restart", "重新启动", symbol: "arrow.clockwise.circle.fill", keywords: ["restart", "reboot"],
            confirmation: .init(title: "确定要重新启动吗？", message: nil, confirmTitle: "重新启动")
        ) {
            try SystemActions.restart()
        },
        command(
            "shut-down", "关机", symbol: "power.circle.fill", keywords: ["shut down", "power off"],
            confirmation: .init(title: "确定要关机吗？", message: nil, confirmTitle: "关机")
        ) {
            try SystemActions.shutDown()
        },
    ]

    func results(for query: SearchQuery) async -> [ResultItem] {
        commands.filter { !hiddenCommandIDs.contains($0.id) }
    }

    func isCommandVisible(_ id: String) -> Bool {
        !hiddenCommandIDs.contains(id)
    }

    func setCommand(_ id: String, visible: Bool) {
        if visible {
            hiddenCommandIDs.remove(id)
        } else {
            hiddenCommandIDs.insert(id)
        }
    }

    func makeSettingsView() -> AnyView? {
        AnyView(SystemSettingsView(ext: self))
    }

    private func command(
        _ id: String,
        _ title: String,
        symbol: String,
        keywords: [String],
        confirmation: ItemAction.Confirmation? = nil,
        run: @escaping () throws -> Void
    ) -> ResultItem {
        ResultItem(
            id: id,
            title: title,
            subtitle: manifest.title,
            icon: .symbol(symbol),
            keywords: keywords,
            kind: .command,
            actions: [
                ItemAction(
                    title,
                    systemImage: "play.fill",
                    style: confirmation == nil ? .regular : .destructive,
                    confirmation: confirmation
                ) { context in
                    do {
                        try run()
                    } catch {
                        context.host.showToast("执行失败：\(error.localizedDescription)", style: .failure)
                    }
                    return .dismiss
                },
            ]
        )
    }
}

private struct SystemSettingsView: View {
    let ext: SystemExtension

    var body: some View {
        Section {
            ForEach(ext.commands) { command in
                Toggle(isOn: Binding(
                    get: { ext.isCommandVisible(command.id) },
                    set: { ext.setCommand(command.id, visible: $0) }
                )) {
                    Label {
                        Text(command.title)
                    } icon: {
                        ItemIconView(icon: command.icon, size: Theme.IconSize.small)
                    }
                }
            }
        } header: {
            Text("命令")
        } footer: {
            Text("关闭的命令不会出现在搜索结果中。清空废纸篓、重新启动和关机执行前会先确认。")
                .foregroundStyle(.secondary)
        }
    }
}

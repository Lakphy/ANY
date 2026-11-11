import AppKit

extension ItemAction {
    static func copy(
        _ text: String,
        title: String = "复制",
        shortcut: KeyShortcut? = .init(.character("c"), modifiers: [.command, .shift])
    ) -> ItemAction {
        ItemAction(title, systemImage: "doc.on.doc", shortcut: shortcut) { context in
            Pasteboard.copy(text)
            context.host.showToast("已复制到剪贴板")
            return .dismiss
        }
    }

    /// Copies `text`, closes the launcher and pastes into the app underneath.
    static func paste(_ text: String) -> ItemAction {
        ItemAction("粘贴到当前应用", systemImage: "doc.on.clipboard") { context in
            Pasteboard.copy(text)
            context.host.hideLauncher()
            if Pasteboard.canSimulatePaste(prompt: true) {
                await Pasteboard.simulatePaste()
            } else {
                context.host.showToast("已复制。授予辅助功能权限后可直接粘贴", style: .info)
            }
            return .dismiss
        }
    }

    static func open(_ url: URL, title: String, systemImage: String = "arrow.up.forward.square") -> ItemAction {
        ItemAction(title, systemImage: systemImage) { _ in
            NSWorkspace.shared.open(url)
            return .dismiss
        }
    }

    static func showInFinder(_ path: String) -> ItemAction {
        ItemAction("在访达中显示", systemImage: "folder", shortcut: .init(.return, modifiers: [.command])) { _ in
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
            return .dismiss
        }
    }
}

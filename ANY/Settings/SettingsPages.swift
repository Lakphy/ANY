import SwiftUI

/// Grouped form that sits directly on the launcher's glass.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }
}

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsForm {
            Section {
                Picker("唤起快捷键", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.hotKey.displayText).tag(preset)
                    }
                }
            } footer: {
                Text("在任意位置按下快捷键即可打开 ANY。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("有选中文字时在选区旁显示", isOn: $settings.hotKeyUsesSelection)
                AccessibilityAccessRow()
            } header: {
                Text("划词")
            } footer: {
                Text("在任意应用中选中文字后按下 \(settings.hotKey.hotKey.displayText)，翻译等结果会直接显示在选区旁边；没有选中文字时照常打开 ANY。读取选中的文字需要辅助功能权限。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
            }
        }
    }
}

/// System Settings doesn't announce changes to the permission, so it's checked while the row is visible.
private struct AccessibilityAccessRow: View {
    @State private var isTrusted = SelectionReader.hasAccess(prompt: false)

    var body: some View {
        LabeledContent("辅助功能权限") {
            if isTrusted {
                Label("已允许", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Button("前往允许…") { SelectionReader.requestAccess() }
            }
        }
        .task {
            while !Task.isCancelled {
                isTrusted = SelectionReader.hasAccess(prompt: false)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Standard page for one extension: enable switch, then the extension's own sections.
struct ExtensionSettingsPage: View {
    let ext: any ANYExtension
    let registry: ExtensionRegistry

    var body: some View {
        let manifest = ext.manifest

        SettingsForm {
            Section {
                Toggle("启用", isOn: Binding(
                    get: { registry.isEnabled(manifest.id) },
                    set: { registry.setEnabled($0, for: manifest.id) }
                ))
                .disabled(!manifest.canBeDisabled)
            } footer: {
                Text(manifest.canBeDisabled ? manifest.subtitle : "\(manifest.subtitle)。这是 ANY 的核心扩展，无法关闭。")
                    .foregroundStyle(.secondary)
            }

            if let settings = ext.makeSettingsView() {
                settings
                    .disabled(!registry.isEnabled(manifest.id))
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ItemIconView(icon: .symbol("sparkle.magnifyingglass"), size: Theme.IconSize.hero)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("ANY")
                    .font(Theme.Typography.title.weight(.semibold))
                Text("版本 \(AppInfo.versionString)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Text("随时按下快捷键，搜索应用、执行命令、计算、查看剪贴板历史。")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
        }
    }
}

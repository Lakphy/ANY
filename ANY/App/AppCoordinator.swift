import AppKit

/// Owns the app's long-lived services and wires them together.
final class AppCoordinator {
    let settings = AppSettings()
    let registry = ExtensionRegistry()

    private let usage = UsageStore()
    private let toasts = ToastController()
    private lazy var launcher = makeLauncher()
    private lazy var settingsPage = SettingsDataSource(settings: settings, registry: registry)
    private lazy var hotKeys = HotKeyManager { [weak self] in self?.handleHotKey() }
    private lazy var selection = SelectionController(settings: settings, registry: registry, host: self)

    init() {
        BuiltinExtensions.all.forEach(registry.register)
    }

    func start() {
        registry.activateEnabled(host: self)
        registerHotKey()
        settings.onHotKeyChange = { [weak self] in self?.registerHotKey() }
    }

    func stop() {
        hotKeys.unregister()
        selection.stop()
        registry.deactivateAll()
    }

    private func registerHotKey() {
        let hotKey = settings.hotKey.hotKey
        if !hotKeys.register(hotKey) {
            toasts.show(Toast(message: "快捷键 \(hotKey.displayText) 注册失败，可能已被占用", style: .warning))
        }
    }

    /// Closes an open launcher; otherwise text selected in the frontmost app gets the selection
    /// popup, and anything else opens the launcher.
    private func handleHotKey() {
        guard !launcher.isVisible else {
            launcher.hide()
            return
        }
        selection.handleHotKey { [weak self] in self?.launcher.show() }
    }

    private func makeLauncher() -> LauncherWindowController {
        let model = LauncherViewModel(root: SearchEngine(registry: registry, usage: usage), usage: usage)
        model.host = self
        let controller = LauncherWindowController(model: model, registry: registry)
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        return controller
    }
}

extension AppCoordinator: ExtensionHost {
    func showLauncher() {
        launcher.show()
    }

    func hideLauncher() {
        launcher.hide()
    }

    func open(_ source: any ListDataSource) {
        launcher.open(source)
    }

    func openSettings(extensionID: String?) {
        launcher.open(settingsPage, selecting: extensionID.map(SettingsDataSource.itemID(forExtension:)))
    }

    func showToast(_ toast: Toast) {
        toasts.show(toast)
    }
}

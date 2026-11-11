import Foundation
import Observation
import ServiceManagement

@Observable
final class AppSettings {
    var hotKey: HotKeyPreset {
        didSet {
            UserDefaults.standard.set(hotKey.rawValue, forKey: Keys.hotKey)
            onHotKeyChange?()
        }
    }

    /// With text selected in the frontmost app, the hotkey opens the selection popup beside it
    /// instead of the launcher.
    var hotKeyUsesSelection: Bool {
        didSet { UserDefaults.standard.set(hotKeyUsesSelection, forKey: Keys.hotKeyUsesSelection) }
    }

    private(set) var launchAtLogin: Bool

    @ObservationIgnored var onHotKeyChange: (() -> Void)?

    private enum Keys {
        static let hotKey = "settings.hotKey"
        static let hotKeyUsesSelection = "settings.hotKeyUsesSelection"
    }

    init() {
        let defaults = UserDefaults.standard
        hotKey = defaults.string(forKey: Keys.hotKey).flatMap(HotKeyPreset.init) ?? .optionSpace
        hotKeyUsesSelection = defaults.object(forKey: Keys.hotKeyUsesSelection) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("ANY: failed to update login item: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

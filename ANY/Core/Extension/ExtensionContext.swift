import Foundation

/// App-level capabilities exposed to extensions and actions.
protocol ExtensionHost: AnyObject {
    func showLauncher()
    func hideLauncher()
    /// Shows the launcher on `source`.
    func open(_ source: any ListDataSource)
    /// Opens settings inside the launcher, optionally on one extension's page.
    func openSettings(extensionID: String?)
    func showToast(_ toast: Toast)
}

extension ExtensionHost {
    func openSettings() {
        openSettings(extensionID: nil)
    }

    func showToast(_ message: String, style: Toast.Style = .success) {
        showToast(Toast(message: message, style: style))
    }
}

/// Per-extension handle given in `activate(context:)`.
final class ExtensionContext {
    let extensionID: String
    let storage: ExtensionStorage
    private(set) weak var host: (any ExtensionHost)?

    init(extensionID: String, host: any ExtensionHost) {
        self.extensionID = extensionID
        self.storage = ExtensionStorage(extensionID: extensionID)
        self.host = host
    }
}

/// Namespaced persistence for an extension: small values in UserDefaults, secrets in the
/// keychain, larger data as files.
struct ExtensionStorage {
    let extensionID: String
    private let defaults = UserDefaults.standard

    init(extensionID: String) {
        self.extensionID = extensionID
    }

    var dataDirectory: URL {
        let base = URL.applicationSupportDirectory
            .appending(path: "ANY", directoryHint: .isDirectory)
            .appending(path: "Extensions", directoryHint: .isDirectory)
            .appending(path: extensionID, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func value<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: namespaced(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func set<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: namespaced(key))
            return
        }
        defaults.set(data, forKey: namespaced(key))
    }

    func secret(forKey key: String) -> String? {
        Keychain.string(forAccount: namespaced(key))
    }

    /// Stores a secret such as an API key; nil or empty removes it.
    func setSecret(_ value: String?, forKey key: String) {
        Keychain.set(value, forAccount: namespaced(key))
    }

    private func namespaced(_ key: String) -> String {
        "extension.\(extensionID).\(key)"
    }
}

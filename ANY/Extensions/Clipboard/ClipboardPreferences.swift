import Observation

@Observable
final class ClipboardPreferences {
    static let limitOptions = [50, 100, 200, 500, 1000]

    var historyLimit: Int {
        didSet {
            storage.set(historyLimit, forKey: Keys.historyLimit)
            onLimitChange?()
        }
    }

    /// Skip content flagged as concealed or transient, e.g. passwords copied from a password manager.
    var ignoresSensitiveContent: Bool {
        didSet { storage.set(ignoresSensitiveContent, forKey: Keys.ignoresSensitiveContent) }
    }

    @ObservationIgnored var onLimitChange: (() -> Void)?
    @ObservationIgnored private let storage: ExtensionStorage

    private enum Keys {
        static let historyLimit = "historyLimit"
        static let ignoresSensitiveContent = "ignoresSensitiveContent"
    }

    init(storage: ExtensionStorage) {
        self.storage = storage
        historyLimit = storage.value(Int.self, forKey: Keys.historyLimit) ?? 200
        ignoresSensitiveContent = storage.value(Bool.self, forKey: Keys.ignoresSensitiveContent) ?? true
    }
}

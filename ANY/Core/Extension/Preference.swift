import Foundation
import Observation

/// An observable value persisted in an extension's storage. Bind settings controls to
/// `Bindable(preference).value`; extensions read `.value` directly.
@Observable
final class Preference<Value: Codable & Equatable> {
    var value: Value {
        didSet {
            guard value != oldValue else { return }
            storage.set(value, forKey: key)
        }
    }

    @ObservationIgnored private let storage: ExtensionStorage
    @ObservationIgnored private let key: String

    init(_ key: String, default defaultValue: Value, storage: ExtensionStorage) {
        self.key = key
        self.storage = storage
        self.value = storage.value(Value.self, forKey: key) ?? defaultValue
    }
}

extension ExtensionStorage {
    func preference<Value: Codable & Equatable>(_ key: String, default defaultValue: Value) -> Preference<Value> {
        Preference(key, default: defaultValue, storage: self)
    }
}

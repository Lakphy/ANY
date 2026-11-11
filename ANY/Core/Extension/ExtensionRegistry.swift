import Foundation
import Observation

@Observable
final class ExtensionRegistry {
    private(set) var extensions: [any ANYExtension] = []
    private var enabledOverrides: [String: Bool]

    @ObservationIgnored private var contexts: [String: ExtensionContext] = [:]
    @ObservationIgnored private weak var host: (any ExtensionHost)?

    private static let overridesKey = "registry.enabledOverrides"

    init() {
        enabledOverrides = UserDefaults.standard.dictionary(forKey: Self.overridesKey) as? [String: Bool] ?? [:]
    }

    func register(_ ext: any ANYExtension) {
        precondition(
            !extensions.contains { $0.manifest.id == ext.manifest.id },
            "Duplicate extension id: \(ext.manifest.id)"
        )
        extensions.append(ext)
    }

    var enabledExtensions: [any ANYExtension] {
        extensions.filter { isEnabled($0.manifest.id) }
    }

    func isEnabled(_ id: String) -> Bool {
        guard let ext = extensions.first(where: { $0.manifest.id == id }) else { return false }
        guard ext.manifest.canBeDisabled else { return true }
        return enabledOverrides[id] ?? ext.manifest.isEnabledByDefault
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let ext = extensions.first(where: { $0.manifest.id == id }),
              ext.manifest.canBeDisabled,
              isEnabled(id) != enabled
        else { return }

        enabledOverrides[id] = enabled
        UserDefaults.standard.set(enabledOverrides, forKey: Self.overridesKey)
        enabled ? activate(ext) : deactivate(ext)
    }

    func activateEnabled(host: any ExtensionHost) {
        self.host = host
        enabledExtensions.forEach(activate)
    }

    func deactivateAll() {
        extensions.forEach(deactivate)
    }

    private func activate(_ ext: any ANYExtension) {
        let id = ext.manifest.id
        guard contexts[id] == nil, let host else { return }
        let context = ExtensionContext(extensionID: id, host: host)
        contexts[id] = context
        ext.activate(context: context)
    }

    private func deactivate(_ ext: any ANYExtension) {
        guard contexts.removeValue(forKey: ext.manifest.id) != nil else { return }
        ext.deactivate()
    }
}

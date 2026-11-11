import Foundation
import Observation

@Observable
final class TranslatePreferences {
    /// DeepL only translates when this is set. Kept in the keychain.
    var deepLAPIKey: String {
        didSet { storage.setSecret(deepLAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.deepLAPIKey) }
    }

    /// Optional; without it Google's free endpoint is used. Kept in the keychain.
    var googleAPIKey: String {
        didSet { storage.setSecret(googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.googleAPIKey) }
    }

    /// Nil detects the language of the text.
    var sourceLanguage: TranslationLanguage? {
        didSet {
            storage.set(sourceLanguage, forKey: Keys.sourceLanguage)
            invalidateResolvedTarget()
        }
    }

    /// Nil picks between the primary and secondary languages.
    var targetLanguage: TranslationLanguage? {
        didSet {
            storage.set(targetLanguage, forKey: Keys.targetLanguage)
            invalidateResolvedTarget()
        }
    }

    var aiAPI: LanguageModelAPI {
        didSet { storage.set(aiAPI, forKey: Keys.aiAPI) }
    }

    var aiBaseURL: String {
        didSet { storage.set(aiBaseURL, forKey: Keys.aiBaseURL) }
    }

    /// Kept in the keychain.
    var aiAPIKey: String {
        didSet { storage.setSecret(aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.aiAPIKey) }
    }

    var aiModel: String {
        didSet { storage.set(aiModel, forKey: Keys.aiModel) }
    }

    var primaryLanguage: TranslationLanguage {
        didSet {
            storage.set(primaryLanguage, forKey: Keys.primaryLanguage)
            invalidateResolvedTarget()
        }
    }

    /// Used instead of the primary language when the text is already in it.
    var secondaryLanguage: TranslationLanguage {
        didSet {
            storage.set(secondaryLanguage, forKey: Keys.secondaryLanguage)
            invalidateResolvedTarget()
        }
    }

    /// Translate straight from the main search with a prefix such as "tr hello".
    var usesSearchPrefix: Bool {
        didSet { storage.set(usesSearchPrefix, forKey: Keys.usesSearchPrefix) }
    }

    var recordsHistory: Bool {
        didSet { storage.set(recordsHistory, forKey: Keys.recordsHistory) }
    }

    /// The target an automatic translation actually used for `resolvedQuery`.
    private(set) var resolvedQuery = ""
    private(set) var resolvedTarget: TranslationLanguage?

    @ObservationIgnored private let storage: ExtensionStorage

    private enum Keys {
        static let deepLAPIKey = "deepLAPIKey"
        static let googleAPIKey = "googleAPIKey"
        static let aiAPI = "aiAPI"
        static let aiBaseURL = "aiBaseURL"
        static let aiAPIKey = "aiAPIKey"
        static let aiModel = "aiModel"
        static let sourceLanguage = "sourceLanguage"
        static let targetLanguage = "targetLanguage"
        static let primaryLanguage = "primaryLanguage"
        static let secondaryLanguage = "secondaryLanguage"
        static let usesSearchPrefix = "usesSearchPrefix"
        static let recordsHistory = "recordsHistory"
    }

    init(storage: ExtensionStorage) {
        self.storage = storage
        deepLAPIKey = storage.secret(forKey: Keys.deepLAPIKey) ?? ""
        googleAPIKey = storage.secret(forKey: Keys.googleAPIKey) ?? ""
        aiAPI = storage.value(LanguageModelAPI.self, forKey: Keys.aiAPI) ?? .chatCompletions
        aiBaseURL = storage.value(String.self, forKey: Keys.aiBaseURL) ?? ""
        aiAPIKey = storage.secret(forKey: Keys.aiAPIKey) ?? ""
        aiModel = storage.value(String.self, forKey: Keys.aiModel) ?? ""
        sourceLanguage = storage.value(TranslationLanguage.self, forKey: Keys.sourceLanguage)
        targetLanguage = storage.value(TranslationLanguage.self, forKey: Keys.targetLanguage)
        primaryLanguage = storage.value(TranslationLanguage.self, forKey: Keys.primaryLanguage) ?? .chinese
        secondaryLanguage = storage.value(TranslationLanguage.self, forKey: Keys.secondaryLanguage) ?? .english
        usesSearchPrefix = storage.value(Bool.self, forKey: Keys.usesSearchPrefix) ?? true
        recordsHistory = storage.value(Bool.self, forKey: Keys.recordsHistory) ?? true
    }

    func apiKey(for service: TranslationService) -> String {
        let key = switch service {
        case .deepL: deepLAPIKey
        case .google: googleAPIKey
        case .ai: aiAPIKey
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The services that answer through `TranslationClient`: Google always, DeepL once it has an API key.
    var availableServices: [TranslationService] {
        [TranslationService.deepL, .google].filter { !$0.requiresAPIKey || !apiKey(for: $0).isEmpty }
    }

    /// Nil until a key and a model are filled in.
    var aiConfiguration: LanguageModelConfiguration? {
        let configuration = LanguageModelConfiguration(
            api: aiAPI,
            baseURL: aiBaseURL,
            apiKey: apiKey(for: .ai),
            model: aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return configuration.isComplete ? configuration : nil
    }

    /// Both sides are still automatic, so a detected source may move the target.
    var correctsAutomatically: Bool {
        sourceLanguage == nil && targetLanguage == nil
    }

    /// The other language of the automatic pair.
    func alternate(to language: TranslationLanguage) -> TranslationLanguage {
        language == primaryLanguage ? secondaryLanguage : primaryLanguage
    }

    func target(for text: String) -> TranslationLanguage {
        if let targetLanguage { return targetLanguage }
        return automaticTarget(for: text, source: sourceLanguage)
    }

    /// The primary language, or the secondary one when the text is already in the primary.
    func automaticTarget(for text: String, source: TranslationLanguage? = nil) -> TranslationLanguage {
        let source = source ?? TranslationLanguage.detect(in: text)
        return source == primaryLanguage ? secondaryLanguage : primaryLanguage
    }

    /// The target a finished automatic translation used for this exact text.
    func resolvedTarget(for text: String) -> TranslationLanguage? {
        resolvedQuery == text ? resolvedTarget : nil
    }

    func resolveTarget(_ target: TranslationLanguage, for text: String) {
        guard !text.isEmpty, resolvedQuery != text || resolvedTarget != target else { return }
        resolvedQuery = text
        resolvedTarget = target
    }

    private func invalidateResolvedTarget() {
        resolvedQuery = ""
        resolvedTarget = nil
    }

    /// Choosing the language on the other side swaps the two, so they never match.
    func setSource(_ language: TranslationLanguage?) {
        if let language, language == targetLanguage { targetLanguage = sourceLanguage }
        sourceLanguage = language
    }

    func setTarget(_ language: TranslationLanguage?) {
        if let language, language == sourceLanguage { sourceLanguage = targetLanguage }
        targetLanguage = language
    }

    /// Flips the direction for `text`, turning detected or automatic sides into concrete languages.
    func swapLanguages(for text: String) {
        let currentTarget = target(for: text)
        let currentSource = sourceLanguage
            ?? TranslationLanguage.detect(in: text).flatMap { $0 == currentTarget ? nil : $0 }
            ?? (currentTarget == primaryLanguage ? secondaryLanguage : primaryLanguage)
        sourceLanguage = currentTarget
        targetLanguage = currentSource
    }
}

import Foundation
import NaturalLanguage

nonisolated enum TranslationLanguage: String, CaseIterable, Identifiable, Codable {
    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chinese: "简体中文"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        case .german: "德语"
        case .spanish: "西班牙语"
        case .russian: "俄语"
        }
    }

    /// DeepL takes target variants ("EN-US") but only base codes ("EN") as the source.
    var deepLSourceCode: String {
        String(rawValue.split(separator: "-").first ?? "").uppercased()
    }

    var deepLCode: String {
        switch self {
        case .chinese: "ZH-HANS"
        case .english: "EN-US"
        default: rawValue.uppercased()
        }
    }

    var googleCode: String {
        self == .chinese ? "zh-CN" : rawValue
    }

    /// Matches language codes as returned by either service ("ZH", "EN", "zh-CN", "en").
    init?(code: String) {
        let base = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
        guard let match = Self.allCases.first(where: { $0.rawValue.hasPrefix(base) }) else { return nil }
        self = match
    }

    /// Shared kanji counts as Japanese only above this. Below it, words such as "大学"
    /// were read as Japanese and therefore translated into Chinese.
    private static let japaneseHanConfidence = 0.85

    /// The dominant language of `text`, detected on device.
    /// Kana, hangul and Cyrillic name their language directly. Han characters are Chinese
    /// unless the recognizer is sure they are Japanese, since the two languages share them.
    static func detect(in text: String) -> TranslationLanguage? {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        let scripts = ScriptCounts(sample)
        if let language = scripts.unambiguousLanguage { return language }
        if scripts.isMostlyHan {
            if let guess = hypothesis(in: sample), guess.language == .japanese, guess.confidence >= japaneseHanConfidence {
                return .japanese
            }
            return .chinese
        }
        return hypothesis(in: sample)?.language
    }

    private static func hypothesis(in text: String) -> (language: TranslationLanguage, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }) else {
            return nil
        }
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return (.chinese, confidence)
        default:
            guard let mapped = TranslationLanguage(code: language.rawValue) else { return nil }
            return (mapped, confidence)
        }
    }

    /// Letter counts for the writing systems this app can tell apart without a model.
    private struct ScriptCounts {
        var han = 0
        var kana = 0
        var hangul = 0
        var cyrillic = 0
        var latin = 0

        init(_ text: String) {
            for scalar in text.unicodeScalars {
                switch scalar.value {
                case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
                    kana += 1
                case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
                    hangul += 1
                case 0x3400...0x4DBF, 0x4E00...0x9FFF:
                    han += 1
                case 0x0400...0x04FF:
                    cyrillic += 1
                case 0x0041...0x005A, 0x0061...0x007A:
                    latin += 1
                default:
                    break
                }
            }
        }

        var unambiguousLanguage: TranslationLanguage? {
            let japanese = kana + han
            if kana > 0, japanese >= hangul, japanese >= cyrillic, japanese > latin { return .japanese }
            if hangul > 0, hangul >= japanese, hangul >= cyrillic, hangul > latin { return .korean }
            if cyrillic > 0, cyrillic >= japanese, cyrillic >= hangul, cyrillic > latin { return .russian }
            return nil
        }

        var isMostlyHan: Bool {
            han > 0 && kana == 0 && hangul == 0 && cyrillic == 0 && han >= latin
        }
    }
}

nonisolated enum TranslationService: String, CaseIterable, Identifiable, Codable {
    case deepL
    case google
    /// A language model writing a TSX document; see `AITranslationSession`.
    case ai

    var id: String { rawValue }

    var requiresAPIKey: Bool { self != .google }

    var name: String {
        switch self {
        case .deepL: "DeepL"
        case .google: "Google 翻译"
        case .ai: "AI 翻译"
        }
    }

    func webURL(for text: String, from source: TranslationLanguage?, to target: TranslationLanguage) -> URL? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#/"))) ?? ""
        switch self {
        case .deepL:
            return URL(string: "https://www.deepl.com/translator#\(source?.rawValue ?? "auto")/\(target.rawValue)/\(encoded)")
        case .google:
            return URL(string: "https://translate.google.com/?sl=\(source?.googleCode ?? "auto")&tl=\(target.googleCode)&text=\(encoded)&op=translate")
        case .ai:
            return nil
        }
    }
}

nonisolated struct Translation: Sendable, Codable, Equatable {
    let text: String
    let source: TranslationLanguage?
    let target: TranslationLanguage
    let service: TranslationService
    /// The TSX source of an AI translation.
    var document: String?
}

nonisolated enum TranslationError: LocalizedError {
    case rejected(TranslationService, status: Int, message: String?, usedAPIKey: Bool)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .rejected(let service, let status, let message, let usedAPIKey):
            switch (service, status, usedAPIKey) {
            case (.deepL, 403, true): return "DeepL API Key 无效"
            case (.google, 400, true), (.google, 403, true): return message ?? "Google API Key 无效"
            case (.deepL, 456, true): return "DeepL 本月额度已用完"
            case (_, 429, false): return "免费接口请求过于频繁，稍后再试或填写 API Key"
            case (_, 429, true): return "请求过于频繁，请稍后再试"
            default: return message ?? "\(service.name) 返回错误（\(status)）"
            }
        case .invalidResponse:
            return "无法解析翻译结果"
        }
    }

    /// The API key itself is the problem, so the settings page is the place to fix it.
    var isAPIKeyProblem: Bool {
        guard case .rejected(_, let status, _, true) = self else { return false }
        return status == 400 || status == 403
    }
}

/// Uses the official APIs when an API key is set (DeepL API v2, Google Cloud Translation v2).
/// Google also works without a key through the free endpoint behind translate.google.com, which
/// may be rate limited. DeepL has no keyless endpoint, so it needs a key.
enum TranslationClient {
    /// A nil source lets the service detect it.
    static func translate(
        _ text: String,
        from source: TranslationLanguage? = nil,
        to target: TranslationLanguage,
        using service: TranslationService,
        apiKey: String
    ) async throws -> Translation {
        switch (service, apiKey.isEmpty) {
        case (.deepL, _): try await deepL(text, from: source, to: target, apiKey: apiKey)
        case (.google, false): try await google(text, from: source, to: target, apiKey: apiKey)
        case (.google, true): try await googleWeb(text, from: source, to: target)
        case (.ai, _): throw TranslationError.invalidResponse
        }
    }

    private static func googleWeb(_ text: String, from source: TranslationLanguage?, to target: TranslationLanguage) async throws -> Translation {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source?.googleCode ?? "auto"),
            URLQueryItem(name: "tl", value: target.googleCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TranslationError.rejected(.google, status: status, message: nil, usedAPIKey: false)
        }
        // [[["译文", "原文", …], …], null, "en", …]
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [[Any]]
        else { throw TranslationError.invalidResponse }
        let translated = segments.compactMap { $0.first as? String }.joined()
        guard !translated.isEmpty else { throw TranslationError.invalidResponse }
        let detected = (root.count > 2 ? root[2] as? String : nil).flatMap(TranslationLanguage.init(code:))
        return Translation(text: translated, source: source ?? detected, target: target, service: .google)
    }

    private static func deepL(_ text: String, from source: TranslationLanguage?, to target: TranslationLanguage, apiKey: String) async throws -> Translation {
        // Free-plan keys end in ":fx" and use a separate host.
        let host = apiKey.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        var request = URLRequest(url: URL(string: "https://\(host)/v2/translate")!)
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["text": [text], "target_lang": target.deepLCode]
        if let source { body["source_lang"] = source.deepLSourceCode }

        let json = try await send(&request, body: body, service: .deepL) { $0["message"] as? String }
        guard let first = (json["translations"] as? [[String: Any]])?.first,
              let translated = first["text"] as? String
        else { throw TranslationError.invalidResponse }
        let detected = (first["detected_source_language"] as? String).flatMap(TranslationLanguage.init(code:))
        return Translation(text: translated, source: source ?? detected, target: target, service: .deepL)
    }

    private static func google(_ text: String, from source: TranslationLanguage?, to target: TranslationLanguage, apiKey: String) async throws -> Translation {
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        var body: [String: Any] = ["q": text, "target": target.googleCode, "format": "text"]
        if let source { body["source"] = source.googleCode }

        let json = try await send(&request, body: body, service: .google) {
            ($0["error"] as? [String: Any])?["message"] as? String
        }
        guard let first = ((json["data"] as? [String: Any])?["translations"] as? [[String: Any]])?.first,
              let translated = first["translatedText"] as? String
        else { throw TranslationError.invalidResponse }
        let detected = (first["detectedSourceLanguage"] as? String).flatMap(TranslationLanguage.init(code:))
        return Translation(text: translated, source: source ?? detected, target: target, service: .google)
    }

    private static func send(
        _ request: inout URLRequest,
        body: [String: Any],
        service: TranslationService,
        errorMessage: ([String: Any]) -> String?
    ) async throws -> [String: Any] {
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TranslationError.rejected(service, status: status, message: errorMessage(json), usedAPIKey: true)
        }
        return json
    }
}

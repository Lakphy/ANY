import Foundation

/// Scores how well a query matches an item, from 0 (weak) to 1 (exact).
/// Chinese titles are also matched by full pinyin and pinyin initials ("weixin", "wx" → 微信).
final class FuzzyMatcher {
    private var pinyinCache: [String: [String]] = [:]

    func score(query: String, item: ResultItem) -> Double? {
        let query = query.lowercased()
        var best: Double?

        func consider(_ candidate: String, weight: Double) {
            guard let score = Self.score(query: query, candidate: candidate) else { return }
            best = max(best ?? 0, score * weight)
        }

        consider(item.title, weight: 1)
        for variant in pinyinVariants(of: item.title) {
            consider(variant, weight: 0.95)
        }
        for keyword in item.keywords {
            consider(keyword, weight: 0.9)
        }
        return best
    }

    static func score(query: String, candidate: String) -> Double? {
        guard !query.isEmpty else { return nil }
        let text = candidate.lowercased()

        if text == query { return 1 }
        if text.hasPrefix(query) {
            return 0.9 + 0.09 * Double(query.count) / Double(text.count)
        }

        let words = tokenize(candidate)
        if words.contains(where: { $0.hasPrefix(query) }) { return 0.8 }

        if query.count >= 2 {
            let initials = String(words.compactMap(\.first))
            if initials.hasPrefix(query) { return 0.75 }
        }

        if text.contains(query) { return 0.6 }

        if query.count >= 2, let density = subsequenceDensity(query: query, text: text) {
            return 0.2 + 0.3 * density
        }
        return nil
    }

    private func pinyinVariants(of title: String) -> [String] {
        if let cached = pinyinCache[title] { return cached }

        var variants: [String] = []
        if title.unicodeScalars.contains(where: { !$0.isASCII }),
           let latin = title.applyingTransform(.mandarinToLatin, reverse: false)?
               .applyingTransform(.stripDiacritics, reverse: false)?
               .lowercased() {
            let syllables = latin.split(whereSeparator: \.isWhitespace).map(String.init)
            variants = [latin, syllables.joined(), String(syllables.compactMap(\.first))]
        }
        pinyinCache[title] = variants
        return variants
    }

    /// Splits on separators and camelCase boundaries, lowercased.
    private static func tokenize(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLowercase = false

        for character in text {
            if !(character.isLetter || character.isNumber) {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousWasLowercase = false
                continue
            }
            if character.isUppercase && previousWasLowercase && !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
            previousWasLowercase = character.isLowercase
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    /// Returns how tightly the query's characters cluster in the text, or nil if they don't all appear in order.
    private static func subsequenceDensity(query: String, text: String) -> Double? {
        var queryIndex = query.startIndex
        var firstMatch: Int?
        var lastMatch = 0

        for (offset, character) in text.enumerated() where queryIndex < query.endIndex {
            if character == query[queryIndex] {
                if firstMatch == nil { firstMatch = offset }
                lastMatch = offset
                queryIndex = query.index(after: queryIndex)
            }
        }
        guard queryIndex == query.endIndex, let firstMatch else { return nil }
        return Double(query.count) / Double(lastMatch - firstMatch + 1)
    }
}

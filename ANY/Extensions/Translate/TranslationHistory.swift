import Foundation
import Observation

struct TranslationHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    /// One per service that succeeded, in service order.
    let translations: [Translation]

    var primaryTranslation: String { translations.first?.text ?? "" }
}

/// Persisted list of recent translations. Text typed in quick succession ("hel", "hello") collapses
/// into one entry, so the history holds what was meant rather than every keystroke.
@Observable
final class TranslationHistory {
    static let limit = 100
    /// A new text that extends or trims the latest one within this window replaces it.
    private static let mergeWindow: TimeInterval = 60

    private(set) var entries: [TranslationHistoryEntry] = []

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func record(_ text: String, translations: [Translation]) {
        guard !translations.isEmpty else { return }
        if let latest = entries.first, latest.text == text, latest.translations == translations { return }

        if let latest = entries.first,
           Date.now.timeIntervalSince(latest.date) < Self.mergeWindow,
           text.hasPrefix(latest.text) || latest.text.hasPrefix(text) {
            entries.removeFirst()
        }
        entries.removeAll { $0.text == text }
        entries.insert(TranslationHistoryEntry(id: UUID(), text: text, date: .now, translations: translations), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    /// Adds a result that arrived later, such as an AI translation, to the entry for `text`.
    func attach(_ translation: Translation, to text: String) {
        guard let index = entries.firstIndex(where: { $0.text == text }) else {
            record(text, translations: [translation])
            return
        }
        let entry = entries[index]
        let translations = entry.translations.filter { $0.service != translation.service } + [translation]
        entries[index] = TranslationHistoryEntry(id: entry.id, text: entry.text, date: entry.date, translations: translations)
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranslationHistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

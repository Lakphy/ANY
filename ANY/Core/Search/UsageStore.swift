import Foundation

/// Remembers which root items the user runs, to boost them in ranking and list them as recents.
final class UsageStore {
    private struct Record: Codable {
        var count: Int
        var lastUsed: Date
    }

    private var records: [String: Record]
    private let defaults = UserDefaults.standard
    private static let key = "usage.records"
    private static let maxRecords = 500

    init() {
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func recordUse(of id: String) {
        var record = records[id] ?? Record(count: 0, lastUsed: .now)
        record.count += 1
        record.lastUsed = .now
        records[id] = record

        if records.count > Self.maxRecords {
            let stale = records.sorted { $0.value.lastUsed < $1.value.lastUsed }.prefix(records.count - Self.maxRecords)
            stale.forEach { records.removeValue(forKey: $0.key) }
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Ranking bonus in 0...30, decaying over roughly a month of disuse.
    func boost(for id: String) -> Double {
        guard let record = records[id] else { return 0 }
        let days = Date.now.timeIntervalSince(record.lastUsed) / 86_400
        return min(Double(record.count), 20) * 1.5 * exp(-days / 30)
    }

    func recentIDs(limit: Int) -> [String] {
        records.sorted { $0.value.lastUsed > $1.value.lastUsed }
            .prefix(limit)
            .map(\.key)
    }
}

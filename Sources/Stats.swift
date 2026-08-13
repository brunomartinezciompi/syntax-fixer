import Foundation

/// Rolling latency stats per model, measured from the app's own real calls.
/// Persisted in UserDefaults so they survive restarts.
struct ModelStats: Codable {
    /// Most recent samples last, in seconds.
    var samples: [Double] = []

    var average: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
}

enum Stats {
    private static let key = "modelStats"
    /// Only the last N calls count, so a slow afternoon ages out.
    private static let maxSamples = 10
    /// Below this we don't claim a fastest model — one sample is noise, and the
    /// spread between runs is wider than the gap between models.
    private static let minSamplesToRank = 3

    static func load() -> [String: ModelStats] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ModelStats].self, from: data)
        else { return [:] }
        return decoded
    }

    static func save(_ stats: [String: ModelStats]) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func record(model: Model, seconds: Double) -> [String: ModelStats] {
        var stats = load()
        var entry = stats[model.rawValue] ?? ModelStats()
        entry.samples.append(seconds)
        if entry.samples.count > maxSamples {
            entry.samples.removeFirst(entry.samples.count - maxSamples)
        }
        stats[model.rawValue] = entry
        save(stats)
        return stats
    }

    /// The fastest model by measured average — only once at least two models
    /// have enough samples to be worth comparing.
    static func fastest(in stats: [String: ModelStats]) -> Model? {
        let ranked = Model.allCases.compactMap { model -> (Model, Double)? in
            guard let entry = stats[model.rawValue],
                  entry.samples.count >= minSamplesToRank,
                  let average = entry.average
            else { return nil }
            return (model, average)
        }
        guard ranked.count >= 2 else { return nil }
        return ranked.min { $0.1 < $1.1 }?.0
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

import Foundation
import os

/// File-based JSON cache for companion mode data.
///
/// Stores last-fetched responses so views can show cached data immediately
/// then refresh in background. Uses category-based eviction: transient data
/// (today, article list) expires quickly; saved articles persist until unsaved.
actor CompanionCache {
    static let shared = CompanionCache()

    private let logger = Logger(subsystem: "com.nebularnews", category: "CompanionCache")
    private let cacheDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    enum Category: String {
        case today
        case articleList
        case articleDetail
        case savedArticles
        case feeds

        /// Maximum age before data is considered stale and eligible for eviction.
        var maxAge: TimeInterval {
            switch self {
            case .today: 60 * 60           // 1 hour
            case .articleList: 2 * 60 * 60 // 2 hours
            case .articleDetail: 4 * 60 * 60
            case .savedArticles: 7 * 24 * 60 * 60 // 7 days
            case .feeds: 4 * 60 * 60
            }
        }
    }

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = base.appendingPathComponent("CompanionCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func store<T: Encodable>(_ value: T, category: Category, key: String = "default") {
        let wrapper = CacheEntry(
            storedAt: Date(),
            category: category.rawValue,
            data: (try? encoder.encode(value)) ?? Data()
        )
        let url = fileURL(category: category, key: key)
        try? encoder.encode(wrapper).write(to: url, options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, category: Category, key: String = "default") -> T? {
        let url = fileURL(category: category, key: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? decoder.decode(CacheEntry.self, from: data) else {
            return nil
        }
        // Check staleness
        let maxAge = Category(rawValue: entry.category)?.maxAge ?? category.maxAge
        guard Date().timeIntervalSince(entry.storedAt) < maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return try? decoder.decode(type, from: entry.data)
    }

    func invalidate(category: Category, key: String = "default") {
        let url = fileURL(category: category, key: key)
        try? FileManager.default.removeItem(at: url)
    }

    func evictStale() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var evicted = 0
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(CacheEntry.self, from: data) else {
                // Corrupt entry, remove
                try? FileManager.default.removeItem(at: file)
                evicted += 1
                continue
            }

            let category = Category(rawValue: entry.category)
            let maxAge = category?.maxAge ?? (2 * 60 * 60)
            if Date().timeIntervalSince(entry.storedAt) > maxAge {
                try? FileManager.default.removeItem(at: file)
                evicted += 1
            }
        }

        if evicted > 0 {
            logger.info("Evicted \(evicted) stale cache entries")
        }
    }

    // MARK: - Private

    private func fileURL(category: Category, key: String) -> URL {
        let sanitized = key.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("\(category.rawValue)_\(sanitized).json")
    }
}

private struct CacheEntry: Codable {
    let storedAt: Date
    let category: String
    let data: Data
}

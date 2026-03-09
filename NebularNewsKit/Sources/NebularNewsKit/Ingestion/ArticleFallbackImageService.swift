import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

public actor ArticleFallbackImageService {
    private let articleRepo: LocalArticleRepository

    // TODO: Replace the curated preset catalog with live Unsplash search once we add
    // a production-safe integration, caching, attribution, and request budgeting.
    public init(modelContainer: ModelContainer) {
        self.articleRepo = LocalArticleRepository(modelContainer: modelContainer)
    }

    public func ensureFallbackImage(articleID: String) async -> String? {
        guard let snapshot = await articleRepo.fallbackImageSnapshot(id: articleID) else {
            return nil
        }

        if let resolvedImageUrl = snapshot.resolvedImageUrl {
            return resolvedImageUrl
        }

        let selection = await selectPreset(for: snapshot)
        guard let selection else {
            return nil
        }

        try? await articleRepo.updateFallbackImage(
            id: articleID,
            url: selection.preset.url,
            provider: selection.provider,
            themeKey: selection.preset.key
        )

        return selection.preset.url
    }

    private func selectPreset(
        for snapshot: ArticleFallbackImageSnapshot
    ) async -> ImagePresetSelection? {
        if let themeKey = await selectThemeWithFoundationModels(for: snapshot),
           let preset = unsplashFallbackPreset(named: themeKey) {
            return ImagePresetSelection(
                preset: preset,
                provider: AIGenerationProvider.foundationModels.rawValue
            )
        }

        return ImagePresetSelection(
            preset: deterministicPreset(for: snapshot),
            provider: "deterministic"
        )
    }

    private func selectThemeWithFoundationModels(
        for snapshot: ArticleFallbackImageSnapshot
    ) async -> String? {
        guard FoundationModelsEngine.runtimeAvailable else {
            return nil
        }

        let prompt = """
        Choose the best Unsplash image theme for this article.

        Title: \(snapshot.title ?? "Untitled")
        Feed: \(snapshot.feedTitle ?? "Unknown")
        Tags: \(snapshot.tags.joined(separator: ", "))
        URL: \(snapshot.canonicalUrl ?? "Unknown")

        Allowed theme keys:
        \(unsplashFallbackPresets.map { "- \($0.key): \($0.description)" }.joined(separator: "\n"))

        Requirements:
        - Return JSON only.
        - JSON keys:
          - "theme_key": one of the allowed theme keys.
        - Pick the most visually representative theme.
        - Prefer the article's topic over the publication name.

        Article:
        \(snapshot.contentText.truncated(to: 3_500))
        """

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(
                instructions: "You select a single image theme key from an allowed list. Return only compact JSON."
            )

            guard let data = try? await session
                .respond(to: prompt, options: GenerationOptions(sampling: .greedy))
                .content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .data(using: .utf8),
                  let response = try? JSONDecoder().decode(ImageThemeResponse.self, from: data)
            else {
                return nil
            }

            return response.themeKey
        }
        #endif

        return nil
    }

    private func deterministicPreset(for snapshot: ArticleFallbackImageSnapshot) -> UnsplashFallbackPreset {
        let queryTokens = fallbackQuery(for: snapshot)
        var bestPreset = unsplashFallbackPresets[0]
        var bestScore = -1

        for preset in unsplashFallbackPresets {
            let score = preset.tokens.reduce(into: 0) { count, token in
                if queryTokens.contains(token) {
                    count += 1
                }
            }

            if score > bestScore {
                bestScore = score
                bestPreset = preset
            }
        }

        if bestScore <= 0 {
            let seed = stableHash("\(snapshot.id)|\(queryTokens.joined(separator: ","))")
            return unsplashFallbackPresets[Int(seed % UInt64(unsplashFallbackPresets.count))]
        }

        return bestPreset
    }

    private func fallbackQuery(for snapshot: ArticleFallbackImageSnapshot) -> [String] {
        var keywords = OrderedKeywordSet()

        for token in keywordTokens(snapshot.title) {
            keywords.insert(token)
            if keywords.count >= 4 { return keywords.values }
        }

        for tag in snapshot.tags {
            for token in keywordTokens(tag) {
                keywords.insert(token)
                if keywords.count >= 4 { return keywords.values }
            }
        }

        for token in keywordTokens(snapshot.feedTitle) {
            keywords.insert(token)
            if keywords.count >= 4 { return keywords.values }
        }

        for token in keywordTokens(snapshot.contentText) {
            keywords.insert(token)
            if keywords.count >= 4 { return keywords.values }
        }

        return keywords.values.isEmpty ? ["general"] : keywords.values
    }
}

private struct ImagePresetSelection {
    let preset: UnsplashFallbackPreset
    let provider: String
}

private struct UnsplashFallbackPreset {
    let key: String
    let description: String
    let url: String
    let tokens: [String]
}

private struct ImageThemeResponse: Decodable {
    let themeKey: String

    private enum CodingKeys: String, CodingKey {
        case themeKey = "theme_key"
    }
}

private struct OrderedKeywordSet {
    private(set) var values: [String] = []

    var count: Int {
        values.count
    }

    mutating func insert(_ value: String) {
        guard !values.contains(value) else { return }
        values.append(value)
    }
}

private let unsplashFallbackPresets: [UnsplashFallbackPreset] = [
    .init(
        key: "space",
        description: "Space, astronomy, rockets, satellites, and scientific exploration.",
        url: "https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=1200&q=80",
        tokens: ["space", "astronomy", "nasa", "orbit", "satellite", "rocket", "galaxy", "planet"]
    ),
    .init(
        key: "ai",
        description: "Artificial intelligence, robots, language models, and automation.",
        url: "https://images.unsplash.com/photo-1485827404703-89b55fcc595e?auto=format&fit=crop&w=1200&q=80",
        tokens: ["ai", "artificial", "intelligence", "robot", "machine", "llm", "automation", "model"]
    ),
    .init(
        key: "hardware",
        description: "Chips, semiconductors, GPUs, CPUs, and electronics.",
        url: "https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=1200&q=80",
        tokens: ["chip", "semiconductor", "hardware", "gpu", "cpu", "electronics", "datacenter", "server"]
    ),
    .init(
        key: "software",
        description: "Software engineering, programming, cloud infrastructure, and developer tools.",
        url: "https://images.unsplash.com/photo-1461749280684-dccba630e2f6?auto=format&fit=crop&w=1200&q=80",
        tokens: ["software", "code", "developer", "programming", "engineering", "app", "api", "kubernetes", "cloud"]
    ),
    .init(
        key: "product",
        description: "Startups, product teams, design, and modern digital work.",
        url: "https://images.unsplash.com/photo-1498050108023-c5249f4df085?auto=format&fit=crop&w=1200&q=80",
        tokens: ["startup", "product", "web", "saas", "design"]
    ),
    .init(
        key: "finance",
        description: "Markets, economics, banking, and business.",
        url: "https://images.unsplash.com/photo-1526304640581-d334cdbbf45e?auto=format&fit=crop&w=1200&q=80",
        tokens: ["finance", "market", "economy", "stock", "bank", "business", "trade", "inflation"]
    ),
    .init(
        key: "health",
        description: "Health, medicine, hospitals, and biotech research.",
        url: "https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=1200&q=80",
        tokens: ["health", "medical", "hospital", "science", "biotech", "research"]
    ),
    .init(
        key: "nature",
        description: "Climate, environment, wildlife, conservation, and nature.",
        url: "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?auto=format&fit=crop&w=1200&q=80",
        tokens: ["climate", "environment", "weather", "earth", "nature", "energy", "wildlife", "birding"]
    ),
    .init(
        key: "news",
        description: "General journalism, media, and publication imagery.",
        url: "https://images.unsplash.com/photo-1432821596592-e2c18b78144f?auto=format&fit=crop&w=1200&q=80",
        tokens: ["media", "news", "journalism", "press", "publication"]
    ),
    .init(
        key: "security",
        description: "Cybersecurity, privacy, and digital risk.",
        url: "https://images.unsplash.com/photo-1516321497487-e288fb19713f?auto=format&fit=crop&w=1200&q=80",
        tokens: ["security", "cyber", "privacy", "breach", "encryption", "cryptography"]
    ),
    .init(
        key: "city",
        description: "Cities, transportation, local news, policy, and civic infrastructure.",
        url: "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80",
        tokens: ["city", "transport", "infrastructure", "policy", "urban", "housing", "transit"]
    ),
    .init(
        key: "sports",
        description: "Sports, games, and competition.",
        url: "https://images.unsplash.com/photo-1517649763962-0c623066013b?auto=format&fit=crop&w=1200&q=80",
        tokens: ["sports", "game", "league", "football", "basketball"]
    ),
    .init(
        key: "education",
        description: "Education, books, analysis, and learning.",
        url: "https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=1200&q=80",
        tokens: ["education", "learning", "books", "analysis", "standards"]
    ),
    .init(
        key: "general",
        description: "A broad, neutral world or landscape image.",
        url: "https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=1200&q=80",
        tokens: ["general", "world", "default"]
    )
]

private let fallbackStopwords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
    "how", "in", "is", "it", "its", "new", "of", "on", "or", "that",
    "the", "this", "to", "was", "what", "when", "where", "who", "will", "with"
]

private func unsplashFallbackPreset(named key: String) -> UnsplashFallbackPreset? {
    unsplashFallbackPresets.first { $0.key == key }
}

private func keywordTokens(_ value: String?) -> [String] {
    guard let value else { return [] }

    return value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
        .filter { $0.count > 2 && !fallbackStopwords.contains($0) }
}

private func stableHash(_ value: String) -> UInt64 {
    var hasher = Hasher()
    hasher.combine(value)
    return UInt64(bitPattern: Int64(hasher.finalize()))
}

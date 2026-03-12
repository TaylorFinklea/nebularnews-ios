import Foundation

public struct StarterFeedDefinition: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let feedURL: String
    public let aliases: [String]

    public init(
        id: String,
        title: String,
        feedURL: String,
        aliases: [String] = []
    ) {
        self.id = id
        self.title = title
        self.feedURL = normalizeOnboardingFeedURL(feedURL) ?? feedURL
        self.aliases = aliases.compactMap(normalizeOnboardingFeedURL)
    }

    public static func custom(title: String, feedURL: String) -> StarterFeedDefinition? {
        guard let canonicalURL = canonicalStarterFeedURL(feedURL) else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = URL(string: canonicalURL)?.host?
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            ?? canonicalURL

        return StarterFeedDefinition(
            id: "custom:\(normalizedFeedKey(from: canonicalURL) ?? canonicalURL)",
            title: trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle,
            feedURL: canonicalURL
        )
    }

    public var allKnownURLs: [String] {
        [feedURL] + aliases
    }
}

public struct StarterInterest: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let description: String
    public let systemImage: String
    public let seedTagSlugs: [String]
    public let defaultFeedIDs: [String]
    public let optionalFeedIDs: [String]

    public init(
        id: String,
        title: String,
        description: String,
        systemImage: String,
        seedTagSlugs: [String],
        defaultFeedIDs: [String],
        optionalFeedIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.seedTagSlugs = seedTagSlugs
        self.defaultFeedIDs = defaultFeedIDs
        self.optionalFeedIDs = optionalFeedIDs
    }

    public var starterFeedCount: Int {
        defaultFeedIDs.count + optionalFeedIDs.count
    }
}

public struct StarterFeedChoice: Sendable, Hashable, Identifiable {
    public let feed: StarterFeedDefinition
    public let interestIDs: [String]
    public let interestTitles: [String]
    public let isInitiallySelected: Bool
    public let isCustom: Bool

    public var id: String { feed.id }
}

public struct OnboardingSeedRequest: Sendable, Hashable {
    public let selectedInterestIDs: [String]
    public let avoidedInterestIDs: [String]
    public let selectedFeeds: [StarterFeedDefinition]

    public init(
        selectedInterestIDs: [String],
        avoidedInterestIDs: [String],
        selectedFeeds: [StarterFeedDefinition]
    ) {
        self.selectedInterestIDs = selectedInterestIDs
        self.avoidedInterestIDs = avoidedInterestIDs
        self.selectedFeeds = selectedFeeds
    }
}

public struct OnboardingSeedResult: Sendable, Hashable {
    public let feedIDs: [String]
    public let selectedFeeds: [StarterFeedDefinition]

    public init(feedIDs: [String], selectedFeeds: [StarterFeedDefinition]) {
        self.feedIDs = feedIDs
        self.selectedFeeds = selectedFeeds
    }
}

public let starterFeedCatalog: [StarterFeedDefinition] = [
    .init(
        id: "pbs-newshour-headlines",
        title: "PBS NewsHour Headlines",
        feedURL: "https://www.pbs.org/newshour/feeds/rss/headlines",
        aliases: ["https://feeds.pbs.org/newshour/rss/headlines"]
    ),
    .init(
        id: "bbc-world-news",
        title: "BBC World News",
        feedURL: "https://feeds.bbci.co.uk/news/world/rss.xml"
    ),
    .init(
        id: "pbs-newshour-politics",
        title: "PBS NewsHour Politics",
        feedURL: "https://www.pbs.org/newshour/feeds/rss/politics",
        aliases: ["https://feeds.pbs.org/newshour/rss/politics"]
    ),
    .init(
        id: "bbc-politics",
        title: "BBC Politics",
        feedURL: "https://feeds.bbci.co.uk/news/politics/rss.xml"
    ),
    .init(
        id: "ars-technica",
        title: "Ars Technica",
        feedURL: "https://feeds.arstechnica.com/arstechnica/index"
    ),
    .init(
        id: "techcrunch",
        title: "TechCrunch",
        feedURL: "https://techcrunch.com/feed/"
    ),
    .init(
        id: "medlineplus-health-news",
        title: "MedlinePlus Health News",
        feedURL: "https://medlineplus.gov/feeds/news_en.xml"
    ),
    .init(
        id: "medlineplus-health-topics",
        title: "MedlinePlus Health Topics",
        feedURL: "https://medlineplus.gov/feeds/healthtopics.xml"
    ),
    .init(
        id: "espn-top-headlines",
        title: "ESPN Top Headlines",
        feedURL: "https://www.espn.com/espn/rss/news"
    ),
    .init(
        id: "smitten-kitchen",
        title: "Smitten Kitchen",
        feedURL: "https://smittenkitchen.com/feed/"
    ),
    .init(
        id: "openai-news",
        title: "OpenAI News",
        feedURL: "https://openai.com/news/rss.xml",
        aliases: ["https://openai.com/blog/rss.xml"]
    ),
    .init(
        id: "deepmind-news",
        title: "Google DeepMind News",
        feedURL: "https://deepmind.google/blog/rss.xml"
    ),
    .init(
        id: "hugging-face-blog",
        title: "Hugging Face - Blog",
        feedURL: "https://huggingface.co/blog/feed.xml"
    ),
    .init(
        id: "mit-technology-review-ai",
        title: "MIT Technology Review AI",
        feedURL: "https://www.technologyreview.com/topic/artificial-intelligence/feed"
    ),
    .init(
        id: "berkeley-ai-research",
        title: "Berkeley AI Research",
        feedURL: "https://bair.berkeley.edu/blog/feed.xml"
    ),
    .init(
        id: "distill",
        title: "Distill",
        feedURL: "https://distill.pub/rss.xml"
    ),
    .init(
        id: "google-research",
        title: "The latest research from Google",
        feedURL: "https://research.google/blog/rss/"
    ),
    .init(
        id: "microsoft-research-blog",
        title: "Microsoft Research Blog",
        feedURL: "https://www.microsoft.com/en-us/research/blog/feed/"
    ),
    .init(
        id: "jmlr",
        title: "JMLR",
        feedURL: "https://www.jmlr.org/jmlr.xml",
        aliases: ["http://www.jmlr.org/jmlr.xml"]
    ),
    .init(
        id: "cncf",
        title: "Cloud Native Computing Foundation",
        feedURL: "https://www.cncf.io/feed/",
        aliases: ["https://www.cncf.io/rss"]
    ),
    .init(
        id: "kubernetes-blog",
        title: "Kubernetes Blog",
        feedURL: "https://kubernetes.io/feed.xml"
    ),
    .init(
        id: "grafana-blog",
        title: "Grafana Labs Blog",
        feedURL: "https://grafana.com/blog/index.xml"
    ),
    .init(
        id: "infoq-devops",
        title: "InfoQ - DevOps",
        feedURL: "https://feed.infoq.com/Devops/"
    ),
    .init(
        id: "krebs-on-security",
        title: "KrebsOnSecurity",
        feedURL: "https://krebsonsecurity.com/feed/"
    ),
    .init(
        id: "grafana-security",
        title: "Security on Grafana Labs",
        feedURL: "https://grafana.com/tags/security/index.xml"
    ),
    .init(
        id: "nist-it-news",
        title: "NIST IT News",
        feedURL: "https://www.nist.gov/news-events/information%20technology/rss.xml"
    ),
    .init(
        id: "nasa-jpl-news",
        title: "NASA JPL News",
        feedURL: "https://www.jpl.nasa.gov/feeds/news/"
    ),
    .init(
        id: "nasa-news-releases",
        title: "NASA News Releases",
        feedURL: "https://www.nasa.gov/news-release/feed/"
    ),
    .init(
        id: "all-about-birds-video",
        title: "All About Birds Video",
        feedURL: "https://www.allaboutbirds.org/news/category/video-1/feed"
    ),
    .init(
        id: "nature-boost",
        title: "Nature Boost",
        feedURL: "https://rss.art19.com/nature-boost"
    ),
    .init(
        id: "american-birding-podcast",
        title: "The American Birding Podcast",
        feedURL: "https://rss.libsyn.com/shows/91087/destinations/454200.xml",
        aliases: ["https://birding.libsyn.com/rss"]
    ),
    .init(
        id: "admiring-light",
        title: "Admiring Light",
        feedURL: "https://admiringlight.com/blog/feed/"
    ),
    .init(
        id: "petapixel",
        title: "PetaPixel",
        feedURL: "https://petapixel.com/feed/"
    ),
    .init(
        id: "dpreview-news",
        title: "DPReview News",
        feedURL: "https://www.dpreview.com/feeds/news.xml"
    ),
    .init(
        id: "frb-kansas-city",
        title: "Federal Reserve Bank of Kansas City publications",
        feedURL: "https://www.fedinprint.org/rss/kansascity.rss"
    ),
    .init(
        id: "frbsf-research-insights",
        title: "FRBSF Research & Insights",
        feedURL: "https://www.frbsf.org/research-and-insights/blog/feed/"
    )
]

public let starterInterestCatalog: [StarterInterest] = [
    .init(
        id: "world-us-news",
        title: "World & U.S. News",
        description: "Major headlines, global context, and reliable general-news coverage.",
        systemImage: "globe.americas",
        seedTagSlugs: ["world-news", "us-news"],
        defaultFeedIDs: ["pbs-newshour-headlines", "bbc-world-news"]
    ),
    .init(
        id: "consumer-tech",
        title: "Consumer Tech",
        description: "Devices, platforms, apps, and the tech stories regular people actually follow.",
        systemImage: "laptopcomputer.and.iphone",
        seedTagSlugs: ["consumer-tech", "consumer-hardware", "software-engineering"],
        defaultFeedIDs: ["ars-technica", "techcrunch"]
    ),
    .init(
        id: "ai-ml",
        title: "AI & ML",
        description: "Model launches, practical ML tools, and fast-moving AI product news.",
        systemImage: "brain",
        seedTagSlugs: ["artificial-intelligence", "generative-ai", "large-language-models"],
        defaultFeedIDs: ["openai-news", "deepmind-news", "hugging-face-blog"],
        optionalFeedIDs: ["mit-technology-review-ai", "berkeley-ai-research"]
    ),
    .init(
        id: "health-wellness",
        title: "Health & Wellness",
        description: "Medical developments, public-health guidance, and practical health news.",
        systemImage: "cross.case",
        seedTagSlugs: ["health", "medicine", "wellness"],
        defaultFeedIDs: ["medlineplus-health-news", "medlineplus-health-topics"]
    ),
    .init(
        id: "sports",
        title: "Sports",
        description: "Big games, seasons, and major sports headlines without digging for them.",
        systemImage: "sportscourt",
        seedTagSlugs: ["sports"],
        defaultFeedIDs: ["espn-top-headlines"]
    ),
    .init(
        id: "food-cooking",
        title: "Food & Cooking",
        description: "Recipes, kitchen ideas, and approachable cooking inspiration.",
        systemImage: "fork.knife",
        seedTagSlugs: ["food", "cooking", "recipes"],
        defaultFeedIDs: ["smitten-kitchen"]
    ),
    .init(
        id: "politics-policy",
        title: "Politics & Policy",
        description: "Government, elections, and policy coverage with signal over noise.",
        systemImage: "building.columns",
        seedTagSlugs: ["politics", "policy", "government"],
        defaultFeedIDs: ["pbs-newshour-politics"],
        optionalFeedIDs: ["bbc-politics"]
    ),
    .init(
        id: "research-deep-dives",
        title: "Research & Deep Dives",
        description: "Longer-form technical thinking, papers, and thoughtful research blogs.",
        systemImage: "atom",
        seedTagSlugs: ["research", "deep-learning"],
        defaultFeedIDs: ["distill", "google-research"],
        optionalFeedIDs: ["microsoft-research-blog", "jmlr"]
    ),
    .init(
        id: "cloud-devops",
        title: "Cloud & DevOps",
        description: "Infrastructure, Kubernetes, platforms, and observability work that ships.",
        systemImage: "cloud",
        seedTagSlugs: ["cloud-infrastructure", "kubernetes", "open-source", "developer-tools", "observability"],
        defaultFeedIDs: ["cncf", "kubernetes-blog", "grafana-blog"],
        optionalFeedIDs: ["infoq-devops"]
    ),
    .init(
        id: "security-privacy",
        title: "Security & Privacy",
        description: "Security incidents, defensive practices, privacy, and standards.",
        systemImage: "lock.shield",
        seedTagSlugs: ["cybersecurity", "privacy", "standards"],
        defaultFeedIDs: ["krebs-on-security", "grafana-security"],
        optionalFeedIDs: ["nist-it-news"]
    ),
    .init(
        id: "space-science",
        title: "Space & Science",
        description: "Space missions, astronomy, and science stories with real signal.",
        systemImage: "sparkles",
        seedTagSlugs: ["space", "research"],
        defaultFeedIDs: ["nasa-jpl-news", "nasa-news-releases"]
    ),
    .init(
        id: "nature-wildlife",
        title: "Nature & Wildlife",
        description: "Birding, conservation, and nature stories that feel restorative.",
        systemImage: "leaf",
        seedTagSlugs: ["nature", "wildlife", "conservation", "birding"],
        defaultFeedIDs: ["all-about-birds-video"],
        optionalFeedIDs: ["nature-boost", "american-birding-podcast"]
    ),
    .init(
        id: "photography",
        title: "Photography",
        description: "Cameras, gear, technique, and strong visual storytelling.",
        systemImage: "camera",
        seedTagSlugs: ["photography"],
        defaultFeedIDs: ["admiring-light", "petapixel"],
        optionalFeedIDs: ["dpreview-news"]
    ),
    .init(
        id: "economics-policy",
        title: "Economics & Policy",
        description: "Macro trends, monetary policy, and practical economic research.",
        systemImage: "chart.line.uptrend.xyaxis",
        seedTagSlugs: ["economics", "monetary-policy", "inflation", "banking"],
        defaultFeedIDs: ["frb-kansas-city", "frbsf-research-insights"]
    )
]

public let popularStarterInterestIDs: [String] = [
    "world-us-news",
    "consumer-tech",
    "ai-ml",
    "health-wellness",
    "sports",
    "food-cooking"
]

public let moreStarterInterestIDs: [String] = [
    "politics-policy",
    "research-deep-dives",
    "cloud-devops",
    "security-privacy",
    "space-science",
    "nature-wildlife",
    "photography",
    "economics-policy"
]

public func starterInterest(id: String) -> StarterInterest? {
    starterInterestCatalog.first(where: { $0.id == id })
}

public func starterFeed(id: String) -> StarterFeedDefinition? {
    starterFeedCatalog.first(where: { $0.id == id })
}

public func buildStarterFeedChoices(
    selectedInterestIDs: Set<String>,
    avoidedInterestIDs: Set<String>,
    customFeeds: [StarterFeedDefinition] = [],
    maximumDefaultsPerInterest: Int = 2,
    maximumSelectedFeeds: Int = 12
) -> [StarterFeedChoice] {
    struct Accumulator {
        var feed: StarterFeedDefinition
        var interestIDs: [String]
        var interestTitles: [String]
        var isInitiallySelected: Bool
        var isCustom: Bool
    }

    let catalogByID = Dictionary(uniqueKeysWithValues: starterFeedCatalog.map { ($0.id, $0) })
    let selectedInterests = starterInterestCatalog.filter { selectedInterestIDs.contains($0.id) && !avoidedInterestIDs.contains($0.id) }
    var byCanonicalURL: [String: Accumulator] = [:]
    var orderedKeys: [String] = []
    var selectedDefaultCount = 0

    for interest in selectedInterests {
        var defaultsChosenForInterest = 0
        let orderedFeedIDs = interest.defaultFeedIDs + interest.optionalFeedIDs

        for feedID in orderedFeedIDs {
            guard let feed = catalogByID[feedID],
                  let canonicalURL = canonicalStarterFeedURL(feed.feedURL)
            else {
                continue
            }

            let isDefaultFeed = interest.defaultFeedIDs.contains(feedID)
            let shouldSelectByDefault =
                isDefaultFeed &&
                defaultsChosenForInterest < maximumDefaultsPerInterest &&
                selectedDefaultCount < maximumSelectedFeeds

            if shouldSelectByDefault {
                defaultsChosenForInterest += 1
                selectedDefaultCount += 1
            }

            if var existing = byCanonicalURL[canonicalURL] {
                if !existing.interestIDs.contains(interest.id) {
                    existing.interestIDs.append(interest.id)
                    existing.interestTitles.append(interest.title)
                }
                existing.isInitiallySelected = existing.isInitiallySelected || shouldSelectByDefault
                byCanonicalURL[canonicalURL] = existing
                continue
            }

            byCanonicalURL[canonicalURL] = Accumulator(
                feed: feed,
                interestIDs: [interest.id],
                interestTitles: [interest.title],
                isInitiallySelected: shouldSelectByDefault,
                isCustom: false
            )
            orderedKeys.append(canonicalURL)
        }
    }

    for customFeed in customFeeds {
        guard let canonicalURL = canonicalStarterFeedURL(customFeed.feedURL) else { continue }

        if let existing = byCanonicalURL[canonicalURL] {
            var merged = existing
            merged.isInitiallySelected = true
            byCanonicalURL[canonicalURL] = merged
            continue
        }

        byCanonicalURL[canonicalURL] = Accumulator(
            feed: StarterFeedDefinition(
                id: customFeed.id,
                title: customFeed.title,
                feedURL: canonicalURL,
                aliases: customFeed.aliases
            ),
            interestIDs: [],
            interestTitles: ["Custom"],
            isInitiallySelected: true,
            isCustom: true
        )
        orderedKeys.append(canonicalURL)
    }

    return orderedKeys.compactMap { key in
        guard let entry = byCanonicalURL[key] else { return nil }
        return StarterFeedChoice(
            feed: entry.feed,
            interestIDs: entry.interestIDs,
            interestTitles: entry.interestTitles,
            isInitiallySelected: entry.isInitiallySelected,
            isCustom: entry.isCustom
        )
    }
}

public func canonicalStarterFeedURL(_ rawValue: String) -> String? {
    guard let normalized = normalizeOnboardingFeedURL(rawValue) else { return nil }
    return starterFeedCanonicalURLMap[normalized] ?? normalized
}

private func normalizeOnboardingFeedURL(_ rawValue: String) -> String? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard var components = URLComponents(string: candidate),
          let host = components.host?.lowercased()
    else {
        return nil
    }

    components.scheme = (components.scheme ?? "https").lowercased()
    components.host = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    components.query = nil
    components.fragment = nil

    var path = components.percentEncodedPath
    if path.isEmpty {
        path = "/"
    }
    if path != "/" {
        path = path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }
    components.percentEncodedPath = path

    return components.string
}

private let starterFeedCanonicalURLMap: [String: String] = {
    var mapping: [String: String] = [:]

    for feed in starterFeedCatalog {
        guard let canonicalURL = normalizeOnboardingFeedURL(feed.feedURL) else { continue }
        mapping[canonicalURL] = canonicalURL

        for alias in feed.aliases {
            guard let normalizedAlias = normalizeOnboardingFeedURL(alias) else { continue }
            mapping[normalizedAlias] = canonicalURL
        }
    }

    return mapping
}()

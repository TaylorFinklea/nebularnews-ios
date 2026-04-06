import Foundation
import NebularNewsKit
import Supabase

struct FeedService: Sendable {
    let client: SupabaseClient

    private var currentUserId: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }

    func fetchFeeds() async throws -> [CompanionFeed] {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let rows: [SupabaseFeedRow] = try await client.from("user_feed_subscriptions")
            .select("""
                feed_id, paused, max_articles_per_day, min_score,
                feeds(id, url, title, site_url, last_polled_at, next_poll_at, error_count, disabled, scrape_mode, scrape_provider, feed_type, avg_extraction_quality, scrape_article_count, scrape_error_count, last_scrape_error, article_sources(count))
            """)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        return rows.compactMap { $0.toCompanionFeed() }
    }

    func addFeed(url: String) async throws -> String {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let existingFeeds: [SupabaseBasicFeedRow] = try await client.from("feeds")
            .select("id")
            .eq("url", value: url)
            .execute()
            .value

        let feedId: String
        if let existing = existingFeeds.first {
            feedId = existing.id
        } else {
            let newFeed: SupabaseBasicFeedRow = try await client.from("feeds")
                .insert(FeedInsert(url: url))
                .select("id")
                .single()
                .execute()
                .value
            feedId = newFeed.id
        }

        try await client.from("user_feed_subscriptions")
            .upsert(FeedSubscriptionInsert(userId: userId.uuidString, feedId: feedId), onConflict: "user_id,feed_id")
            .execute()

        return feedId
    }

    func deleteFeed(id: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        try await client.from("user_feed_subscriptions")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("feed_id", value: id)
            .execute()
    }

    func updateFeedSettings(feedId: String, paused: Bool? = nil, maxArticlesPerDay: Int? = nil, minScore: Int? = nil) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        var updates: [String: AnyJSON] = [
            "updated_at": AnyJSON.string(Date().ISO8601Format())
        ]
        if let paused {
            updates["paused"] = AnyJSON.bool(paused)
            updates["paused_at"] = paused ? AnyJSON.string(Date().ISO8601Format()) : AnyJSON.null
        }
        if let maxArticlesPerDay {
            updates["max_articles_per_day"] = maxArticlesPerDay > 0 ? AnyJSON.integer(maxArticlesPerDay) : AnyJSON.null
        }
        if let minScore {
            updates["min_score"] = minScore > 0 ? AnyJSON.integer(minScore) : AnyJSON.null
        }

        try await client.from("user_feed_subscriptions")
            .update(updates)
            .eq("user_id", value: userId.uuidString)
            .eq("feed_id", value: feedId)
            .execute()
    }

    func updateFeedScrapeConfig(feedId: String, scrapeMode: String, scrapeProvider: String?, feedType: String) async throws {
        var updates: [String: AnyJSON] = [
            "scrape_mode": AnyJSON.string(scrapeMode),
            "feed_type": AnyJSON.string(feedType),
            "updated_at": AnyJSON.string(Date().ISO8601Format())
        ]
        if let provider = scrapeProvider, !provider.isEmpty {
            updates["scrape_provider"] = AnyJSON.string(provider)
        } else {
            updates["scrape_provider"] = AnyJSON.null
        }
        try await client.from("feeds")
            .update(updates)
            .eq("id", value: feedId)
            .execute()
    }

    func importOPML(xml: String) async throws -> Int {
        let response: OPMLImportResponse = try await client.functions.invoke(
            "import-opml",
            options: FunctionInvokeOptions(
                body: ["opml": xml]
            )
        )
        return response.added
    }

    func exportOPML() async throws -> String {
        let response: OPMLExportResponse = try await client.functions.invoke(
            "export-opml",
            options: FunctionInvokeOptions(body: [:] as [String: String])
        )
        return response.opml
    }

    @discardableResult
    func triggerPull(cycles: Int = 1) async throws -> Void {
        _ = try await client.functions.invoke(
            "poll-feeds",
            options: FunctionInvokeOptions(
                body: ["cycles": cycles]
            )
        )
    }

    func fetchOnboardingSuggestions() async throws -> OnboardingCatalog {
        OnboardingCatalog(categories: [
            OnboardingCategory(id: "tech", name: "Technology", icon: "desktopcomputer", feeds: [
                OnboardingFeed(url: "https://hnrss.org/frontpage", title: "Hacker News", description: "Tech news and discussion", siteUrl: "https://news.ycombinator.com"),
                OnboardingFeed(url: "https://www.theverge.com/rss/index.xml", title: "The Verge", description: "Technology, science, art, and culture", siteUrl: "https://www.theverge.com"),
                OnboardingFeed(url: "https://feeds.arstechnica.com/arstechnica/index", title: "Ars Technica", description: "Technology news and analysis", siteUrl: "https://arstechnica.com"),
                OnboardingFeed(url: "https://www.techmeme.com/feed.xml", title: "Techmeme", description: "The essential tech news of the moment", siteUrl: "https://www.techmeme.com")
            ]),
            OnboardingCategory(id: "ai", name: "AI & Machine Learning", icon: "brain", feeds: [
                OnboardingFeed(url: "https://openai.com/blog/rss.xml", title: "OpenAI Blog", description: "Research and announcements from OpenAI", siteUrl: "https://openai.com/blog"),
                OnboardingFeed(url: "https://blog.google/technology/ai/rss/", title: "Google AI Blog", description: "AI research from Google", siteUrl: "https://blog.google/technology/ai/"),
                OnboardingFeed(url: "https://machinelearningmastery.com/feed/", title: "Machine Learning Mastery", description: "Practical ML tutorials and guides", siteUrl: "https://machinelearningmastery.com")
            ]),
            OnboardingCategory(id: "science", name: "Science", icon: "atom", feeds: [
                OnboardingFeed(url: "https://www.quantamagazine.org/feed/", title: "Quanta Magazine", description: "Mathematics, physics, and biology", siteUrl: "https://www.quantamagazine.org"),
                OnboardingFeed(url: "https://www.nature.com/nature.rss", title: "Nature", description: "International scientific journal", siteUrl: "https://www.nature.com"),
                OnboardingFeed(url: "https://www.newscientist.com/feed/home/", title: "New Scientist", description: "Science and technology news", siteUrl: "https://www.newscientist.com")
            ]),
            OnboardingCategory(id: "news", name: "World News", icon: "globe", feeds: [
                OnboardingFeed(url: "https://feeds.bbci.co.uk/news/rss.xml", title: "BBC News", description: "World news from the BBC", siteUrl: "https://www.bbc.com/news"),
                OnboardingFeed(url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", title: "New York Times", description: "Top stories", siteUrl: "https://www.nytimes.com"),
                OnboardingFeed(url: "https://feeds.reuters.com/reuters/topNews", title: "Reuters", description: "International news wire", siteUrl: "https://www.reuters.com")
            ]),
            OnboardingCategory(id: "dev", name: "Software Development", icon: "chevron.left.forwardslash.chevron.right", feeds: [
                OnboardingFeed(url: "https://blog.pragmaticengineer.com/rss/", title: "The Pragmatic Engineer", description: "Software engineering and tech industry", siteUrl: "https://blog.pragmaticengineer.com"),
                OnboardingFeed(url: "https://css-tricks.com/feed/", title: "CSS-Tricks", description: "Web development tips and techniques", siteUrl: "https://css-tricks.com"),
                OnboardingFeed(url: "https://martinfowler.com/feed.atom", title: "Martin Fowler", description: "Software design and architecture", siteUrl: "https://martinfowler.com")
            ])
        ])
    }

    func bulkSubscribe(feedUrls: [String]) async throws -> Int {
        guard await currentUserId != nil else { throw SupabaseManagerError.notAuthenticated }

        var subscribed = 0
        for url in feedUrls {
            do {
                _ = try await addFeed(url: url)
                subscribed += 1
            } catch {
                continue
            }
        }

        try? await triggerPull()

        return subscribed
    }
}

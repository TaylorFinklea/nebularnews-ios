import SwiftUI

struct AdminScrapingStats: Codable {
    let fetched1h: Int
    let fetched24h: Int
    let onCooldown: Int
    let totalWithErrors: Int
    let avgExtractionQuality24h: Double?
    let byScrapeMode: [AdminScrapeModeCount]
    let recentErrors: [AdminFetchError]

    enum CodingKeys: String, CodingKey {
        case fetched1h = "fetched_1h"
        case fetched24h = "fetched_24h"
        case onCooldown = "on_cooldown"
        case totalWithErrors = "total_with_errors"
        case avgExtractionQuality24h = "avg_extraction_quality_24h"
        case byScrapeMode = "by_scrape_mode"
        case recentErrors = "recent_errors"
    }
}

struct AdminScrapeModeCount: Codable, Identifiable {
    let scrapeMode: String
    let fetchCount: Int
    var id: String { scrapeMode }
}

struct AdminFetchError: Codable, Identifiable {
    let articleId: String
    let title: String?
    let error: String
    let attemptedAt: Int?
    let feedTitle: String?
    var id: String { articleId }
}

struct AdminScrapingStatsView: View {
    @State private var stats: AdminScrapingStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            if let stats {
                Section("Last Hour") {
                    LabeledContent("Fetched", value: "\(stats.fetched1h)")
                    LabeledContent("On Cooldown", value: "\(stats.onCooldown)")
                        .foregroundStyle(stats.onCooldown > 0 ? .orange : .primary)
                }

                Section("Last 24 Hours") {
                    LabeledContent("Fetched", value: "\(stats.fetched24h)")
                    LabeledContent("Total With Errors", value: "\(stats.totalWithErrors)")
                        .foregroundStyle(stats.totalWithErrors > 0 ? .red : .primary)
                    if let quality = stats.avgExtractionQuality24h {
                        LabeledContent("Avg Quality", value: String(format: "%.0f%%", quality * 100))
                            .foregroundStyle(quality < 0.4 ? .red : quality < 0.7 ? .orange : .green)
                    }
                }

                if !stats.byScrapeMode.isEmpty {
                    Section("By Scrape Mode (24h)") {
                        ForEach(stats.byScrapeMode) { mode in
                            LabeledContent(mode.scrapeMode, value: "\(mode.fetchCount) articles")
                        }
                    }
                }

                if stats.recentErrors.isEmpty {
                    Section("Recent Errors") {
                        Text("No fetch errors").foregroundStyle(.secondary)
                    }
                } else {
                    Section("Recent Errors (\(stats.recentErrors.count))") {
                        ForEach(stats.recentErrors) { fetchError in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fetchError.title ?? fetchError.articleId)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let feedTitle = fetchError.feedTitle {
                                    Text(feedTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(fetchError.error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                                if let at = fetchError.attemptedAt {
                                    Text(formatDate(at))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Scraping Stats")
        .overlay { if isLoading { ProgressView() } }
        .task {
            isLoading = true
            do {
                stats = try await APIClient.shared.request(path: "api/admin/scraping-stats")
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

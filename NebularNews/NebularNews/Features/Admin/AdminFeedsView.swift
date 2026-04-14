import SwiftUI

struct AdminFeed: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let feedType: String
    let errorCount: Int
    let lastPolledAt: Int?
    let scrapeMode: String
    let scrapeErrorCount: Int
    let avgExtractionQuality: Double?
    let subscriberCount: Int
}

struct AdminFeedsView: View {
    @State private var feeds: [AdminFeed] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            ForEach(feeds) { feed in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(feed.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        if feed.errorCount > 0 {
                            Text("\(feed.errorCount) errors")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }

                    Text(feed.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label("\(feed.subscriberCount) subs", systemImage: "person.2")
                        Label(feed.scrapeMode, systemImage: "doc.text.magnifyingglass")
                        if let quality = feed.avgExtractionQuality {
                            Label(String(format: "%.0f%% quality", quality * 100), systemImage: "checkmark.seal")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let polled = feed.lastPolledAt {
                        Text("Last polled: \(formatDate(polled))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing) {
                    Button("Re-poll") {
                        Task { await repoll(feed.id) }
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Feeds")
        .overlay { if isLoading { ProgressView() } }
        .task {
            isLoading = true
            do {
                feeds = try await APIClient.shared.request(path: "api/admin/feeds")
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func repoll(_ feedId: String) async {
        try? await APIClient.shared.requestVoid(method: "POST", path: "api/admin/feeds/\(feedId)/repoll")
    }

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

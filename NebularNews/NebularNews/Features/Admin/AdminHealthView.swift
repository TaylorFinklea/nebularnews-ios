import SwiftUI

struct AdminHealth: Codable {
    let recentPulls: [AdminPullRun]
    let feedsWithErrors: Int
    let totalUsers: Int
    let totalArticles: Int
    let articlesScoredLastHour: Int
}

struct AdminPullRun: Codable, Identifiable {
    let id: String
    let status: String
    let completedAt: Int?
    let stats: AdminPullStats?
}

struct AdminPullStats: Codable {
    let feedsPolled: Int?
    let articlesNew: Int?
    let articlesSkipped: Int?
    let errors: Int?
}

struct AdminHealthView: View {
    @State private var health: AdminHealth?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            if let health {
                Section("Overview") {
                    LabeledContent("Total Users", value: "\(health.totalUsers)")
                    LabeledContent("Total Articles", value: "\(health.totalArticles)")
                    LabeledContent("Feeds with Errors", value: "\(health.feedsWithErrors)")
                    LabeledContent("Scored (last hour)", value: "\(health.articlesScoredLastHour)")
                }

                Section("Recent Poll Runs") {
                    ForEach(health.recentPulls) { pull in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pull.status)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(pull.status == "done" ? Color.green.opacity(0.15) : Color.red.opacity(0.15), in: Capsule())
                                    .foregroundStyle(pull.status == "done" ? .green : .red)
                                Spacer()
                                if let completed = pull.completedAt {
                                    Text(formatDate(completed))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            if let stats = pull.stats {
                                HStack(spacing: 12) {
                                    if let polled = stats.feedsPolled { Text("\(polled) feeds") }
                                    if let newCount = stats.articlesNew { Text("\(newCount) new") }
                                    if let errors = stats.errors, errors > 0 {
                                        Text("\(errors) errors").foregroundStyle(.red)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("System Health")
        .overlay { if isLoading { ProgressView() } }
        .task {
            isLoading = true
            do {
                health = try await APIClient.shared.request(path: "api/admin/health")
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

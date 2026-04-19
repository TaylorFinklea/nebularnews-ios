import SwiftUI

struct AdminAIStats: Codable {
    let daily: AdminTokenBucket
    let weekly: AdminTokenBucket
    let byProvider: [AdminProviderStat]
    let byEndpoint: [AdminEndpointStat]
    let possibleErrors7d: Int
    // No explicit CodingKeys: the APIClient decoder uses .convertFromSnakeCase,
    // which applies the snake→camel transformation before lookup. Explicit
    // CodingKeys with snake_case rawValues would fight that strategy and fail.
}

struct AdminTokenBucket: Codable {
    let tokens: Int
    let calls: Int
}

struct AdminProviderStat: Codable, Identifiable {
    let provider: String
    let totalTokens: Int
    let callCount: Int
    var id: String { provider }
}

struct AdminEndpointStat: Codable, Identifiable {
    let endpoint: String
    let callCount: Int
    var id: String { endpoint }
}

struct AdminAIStatsView: View {
    @State private var stats: AdminAIStats?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            if let stats {
                Section("Last 24 Hours") {
                    LabeledContent("API Calls", value: "\(stats.daily.calls)")
                    LabeledContent("Tokens Used", value: formatTokens(stats.daily.tokens))
                }

                Section("Last 7 Days") {
                    LabeledContent("API Calls", value: "\(stats.weekly.calls)")
                    LabeledContent("Tokens Used", value: formatTokens(stats.weekly.tokens))
                    LabeledContent("Possible Errors", value: "\(stats.possibleErrors7d)")
                }

                if !stats.byProvider.isEmpty {
                    Section("By Provider") {
                        ForEach(stats.byProvider) { p in
                            HStack {
                                Text(p.provider.capitalized)
                                Spacer()
                                Text("\(p.callCount) calls, \(formatTokens(p.totalTokens)) tokens")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                if !stats.byEndpoint.isEmpty {
                    Section("By Feature") {
                        ForEach(stats.byEndpoint) { e in
                            HStack {
                                Text(e.endpoint)
                                Spacer()
                                Text("\(e.callCount) calls")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Usage")
        .overlay { if isLoading { ProgressView() } }
        .task {
            isLoading = true
            do {
                stats = try await APIClient.shared.request(path: "api/admin/ai-stats")
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.0fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

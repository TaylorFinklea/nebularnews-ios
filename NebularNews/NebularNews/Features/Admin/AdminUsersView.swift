import SwiftUI

struct AdminUser: Codable, Identifiable {
    let id: String
    let name: String?
    let email: String?
    let isAdmin: Bool
    let createdAt: String?
    let tier: String?
    let subscriptionExpires: Int?
    let tokens7d: Int
    let feedCount: Int
    let articlesRead: Int
    let lastActive: Int?
}

struct AdminUsersView: View {
    @State private var users: [AdminUser] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            ForEach(users) { user in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.email ?? user.name ?? user.id.prefix(8).description)
                            .font(.headline)
                        Spacer()
                        if user.isAdmin {
                            Text("Admin")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                        if let tier = user.tier {
                            Text(tier.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }

                    HStack(spacing: 12) {
                        Label("\(user.feedCount) feeds", systemImage: "antenna.radiowaves.left.and.right")
                        Label("\(user.articlesRead) read", systemImage: "book")
                        Label(formatTokens(user.tokens7d) + " tokens/7d", systemImage: "cpu")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let lastActive = user.lastActive {
                        Text("Last active: \(formatDate(lastActive))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Users")
        .overlay { if isLoading { ProgressView() } }
        .task {
            isLoading = true
            do {
                users = try await APIClient.shared.request(path: "api/admin/users")
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

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

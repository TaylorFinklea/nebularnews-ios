import SwiftUI

/// Admin dashboard — role-gated section for managing users, feeds, AI, and system health.
struct AdminDashboardView: View {
    @State private var isAdmin = false
    @State private var isChecking = true

    var body: some View {
        Group {
            if isChecking {
                ProgressView("Checking access...")
            } else if !isAdmin {
                ContentUnavailableView(
                    "Admin Access Required",
                    systemImage: "lock.shield",
                    description: Text("This section is restricted to administrators.")
                )
            } else {
                List {
                    NavigationLink {
                        AdminUsersView()
                    } label: {
                        Label("Users", systemImage: "person.2")
                    }

                    NavigationLink {
                        AdminFeedsView()
                    } label: {
                        Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    NavigationLink {
                        AdminAIStatsView()
                    } label: {
                        Label("AI Usage", systemImage: "chart.bar")
                    }

                    NavigationLink {
                        AdminHealthView()
                    } label: {
                        Label("System Health", systemImage: "heart.text.square")
                    }

                    NavigationLink {
                        AdminScrapingStatsView()
                    } label: {
                        Label("Scraping Stats", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
        .navigationTitle("Admin")
        .task {
            isChecking = true
            do {
                struct AdminCheck: Decodable { let isAdmin: Bool }
                let _: AdminCheck = try await APIClient.shared.request(path: "api/admin/me")
                isAdmin = true
            } catch {
                isAdmin = false
            }
            isChecking = false
        }
    }
}

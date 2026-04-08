import SwiftUI

struct FeedDiscoveryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var catalog: OnboardingCatalog?
    @State private var subscribedUrls: Set<String> = []
    @State private var isLoading = false
    @State private var subscribingUrl: String?
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && catalog == nil {
                    ProgressView()
                } else if let catalog {
                    catalogList(catalog)
                } else {
                    ContentUnavailableView(
                        "Couldn't Load Feeds",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text(errorMessage)
                    )
                }
            }
            .navigationTitle("Discover Feeds")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadCatalog() }
        }
    }

    @ViewBuilder
    private func catalogList(_ catalog: OnboardingCatalog) -> some View {
        List {
            ForEach(catalog.categories) { category in
                Section {
                    ForEach(category.feeds) { feed in
                        feedRow(feed)
                    }
                } header: {
                    Label(category.name, systemImage: category.icon)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
    }

    @ViewBuilder
    private func feedRow(_ feed: OnboardingFeed) -> some View {
        let isSubscribed = subscribedUrls.contains(feed.url)
        let isSubscribing = subscribingUrl == feed.url

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.subheadline.weight(.medium))
                if let description = feed.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isSubscribed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isSubscribing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await subscribe(feed) }
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func loadCatalog() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await appState.supabase.fetchOnboardingSuggestions()

            // Get currently subscribed feed URLs to filter the catalog.
            let feeds = try await appState.supabase.fetchFeeds()
            subscribedUrls = Set(feeds.map(\.url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subscribe(_ feed: OnboardingFeed) async {
        subscribingUrl = feed.url
        defer { subscribingUrl = nil }
        do {
            _ = try await appState.supabase.bulkSubscribe(feedUrls: [feed.url])
            subscribedUrls.insert(feed.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

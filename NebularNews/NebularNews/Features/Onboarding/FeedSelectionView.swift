import SwiftUI

struct FeedSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var catalog: OnboardingCatalog?
    @State private var selectedUrls: Set<String> = []
    @State private var loading = true
    @State private var subscribing = false
    @State private var error = ""

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        NebularScreen(emphasis: .hero) {
            if loading {
                ProgressView("Loading feeds...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let catalog {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 20) {
                            header
                            ForEach(catalog.categories) { category in
                                categoryCard(category)
                            }
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    }
                    bottomBar
                }
            }
        }
        .task { await loadCatalog() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "newspaper")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(palette.primary)

            Text("Choose Your Feeds")
                .font(.title.bold())
                .tracking(-0.5)

            Text("Pick categories and feeds you're interested in. You can always change these later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func categoryCard(_ category: OnboardingCategory) -> some View {
        let allSelected = category.feeds.allSatisfy { selectedUrls.contains($0.url) }

        return GlassCard(cornerRadius: 20, style: .raised, tintColor: palette.primary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(category.name)
                        .font(.headline)
                    Spacer()
                    Button(allSelected ? "Deselect all" : "Select all") {
                        for feed in category.feeds {
                            if allSelected {
                                selectedUrls.remove(feed.url)
                            } else {
                                selectedUrls.insert(feed.url)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(palette.primary)
                }

                ForEach(category.feeds) { feed in
                    feedRow(feed)
                }
            }
        }
    }

    private func feedRow(_ feed: OnboardingFeed) -> some View {
        let isSelected = selectedUrls.contains(feed.url)

        return Button {
            if isSelected {
                selectedUrls.remove(feed.url)
            } else {
                selectedUrls.insert(feed.url)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let desc = feed.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? palette.primary : .secondary)
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Skip") {
                    appState.completeFeedSelection()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await subscribe() }
                } label: {
                    if subscribing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Subscribe (\(selectedUrls.count))")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedUrls.isEmpty || subscribing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func loadCatalog() async {
        do {
            catalog = try await appState.mobileAPI.fetchOnboardingSuggestions()
        } catch {
            self.error = "Failed to load feed suggestions."
        }
        loading = false
    }

    private func subscribe() async {
        subscribing = true
        error = ""
        defer { subscribing = false }

        do {
            _ = try await appState.mobileAPI.bulkSubscribe(feedUrls: Array(selectedUrls))
            appState.completeFeedSelection()
        } catch {
            self.error = "Failed to subscribe. Please try again."
        }
    }
}

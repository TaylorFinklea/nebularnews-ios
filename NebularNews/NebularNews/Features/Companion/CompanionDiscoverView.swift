import SwiftUI

struct CompanionDiscoverView: View {
    @Environment(AppState.self) private var appState

    @Binding var showSettings: Bool

    @State private var tags: [CompanionTagWithCount] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && tags.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 12) {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await loadTags() } }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Feeds row
                            NavigationLink(destination: CompanionFeedsView()) {
                                HStack {
                                    Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)

                            // Tag chip grid
                            if tags.isEmpty {
                                ContentUnavailableView(
                                    "No Tags",
                                    systemImage: "tag",
                                    description: Text("Tags will appear here once articles are tagged.")
                                )
                                .padding(.top, 40)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Topics")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    FlowLayout(spacing: 8) {
                                        ForEach(tags) { tag in
                                            NavigationLink(destination: TagArticlesView(tag: tag)) {
                                                TagChip(tag: tag)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
            }
            .refreshable { await loadTags() }
            .task { await loadTags() }
        }
    }

    private func loadTags() async {
        isLoading = true
        error = nil
        do {
            tags = try await appState.supabase.fetchTags()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct TagChip: View {
    let tag: CompanionTagWithCount

    var body: some View {
        HStack(spacing: 6) {
            if let colorHex = tag.color {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 8, height: 8)
            }
            Text(tag.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if tag.articleCount > 0 {
                Text("\(tag.articleCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 1))
    }
}

// MARK: - Tag-filtered articles

private struct TagArticlesView: View {
    let tag: CompanionTagWithCount
    @Environment(AppState.self) private var appState

    @State private var articles: [CompanionArticleListItem] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var error: String?

    private var hasMore: Bool { articles.count < total }

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            Section {
                ForEach(articles) { article in
                    NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                        TagArticleRow(article: article)
                    }
                }
                if hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { Task { await loadMore() } }
                }
            }
        }
        .overlay {
            if isLoading && articles.isEmpty {
                ProgressView("Loading…")
            } else if articles.isEmpty && error == nil && !isLoading {
                ContentUnavailableView(
                    "No Articles",
                    systemImage: "doc.text",
                    description: Text("No articles found for this tag.")
                )
            }
        }
        .navigationTitle(tag.name)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let payload = try await appState.supabase.fetchArticles(tag: tag.id)
            articles = payload.articles
            total = payload.total
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore else { return }
        do {
            let payload = try await appState.supabase.fetchArticles(offset: articles.count, tag: tag.id)
            articles.append(contentsOf: payload.articles)
            total = payload.total
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TagArticleRow: View {
    let article: CompanionArticleListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title ?? "Untitled")
                .font(.headline)
                .lineLimit(2)
            if let sourceName = article.sourceName, !sourceName.isEmpty {
                Text(sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

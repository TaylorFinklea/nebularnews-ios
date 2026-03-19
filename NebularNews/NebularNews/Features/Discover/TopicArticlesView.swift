import SwiftUI
import SwiftData
import Observation
import NebularNewsKit

/// Articles filtered by a specific tag, displayed in the magazine grid layout.
struct TopicArticlesView: View {
    let tagId: String
    let tagName: String

    @Environment(\.modelContext) private var modelContext
    @State private var articles: [Article] = []
    @State private var reloadTask: Task<Void, Never>?

    var body: some View {
        NebularScreen(emphasis: .discover) {
            ScrollView {
                VStack(spacing: 16) {
                    if articles.isEmpty {
                        ContentUnavailableView(
                            "No Articles",
                            systemImage: "doc.text",
                            description: Text("No articles tagged with \(tagName) yet.")
                        )
                        .padding(.top, 60)
                    } else {
                        MagazineGrid(articles: articles)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(tagName)
        .navigationDestination(for: String.self) { articleId in
            ArticleDetailView(articleId: articleId)
        }
        .task(id: tagId) {
            await loadArticles()
        }
        .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.feedPageMightChange)) { _ in
            scheduleDebouncedReload()
        }
    }

    private func loadArticles() async {
        let repo = LocalArticleRepository(modelContainer: modelContext.container)
        var filter = ArticleFilter()
        filter.tagIds = [tagId]
        filter.storageScope = .active
        articles = await repo.list(filter: filter, sort: .newest, limit: 200, offset: 0)
    }

    private func scheduleDebouncedReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await loadArticles()
        }
    }
}

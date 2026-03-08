import SwiftUI
import SwiftData
import NebularNewsKit

/// Articles filtered by a specific tag, displayed in the magazine grid layout.
struct TopicArticlesView: View {
    let tagId: String
    let tagName: String

    @Query(sort: [SortDescriptor(\Article.publishedAt, order: .reverse)])
    private var allArticles: [Article]

    var body: some View {
        NebularScreen(emphasis: .discover) {
            ScrollView {
                VStack(spacing: 16) {
                    if filteredArticles.isEmpty {
                        ContentUnavailableView(
                            "No Articles",
                            systemImage: "doc.text",
                            description: Text("No articles tagged with \(tagName) yet.")
                        )
                        .padding(.top, 60)
                    } else {
                        MagazineGrid(articles: filteredArticles)
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
    }

    private var filteredArticles: [Article] {
        allArticles.filter { article in
            article.tags?.contains(where: { $0.id == tagId }) ?? false
        }
    }
}

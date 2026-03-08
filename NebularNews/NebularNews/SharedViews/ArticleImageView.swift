import SwiftUI
import SwiftData
import NebularNewsKit

/// Reusable article image with automatic fallback chain:
/// RSS imageUrl -> cached OG image -> space-themed placeholder.
///
/// Triggers OG image fetching lazily when no image is available.
struct ArticleImageView: View {
    let article: Article
    var size: ImageSize = .hero
    var showGradientOverlay: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var ogFetchAttempted = false

    enum ImageSize {
        case hero       // full width, 220pt tall
        case medium     // 130pt tall
        case thumbnail  // 60pt square
    }

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)

        Group {
            if let urlString = article.resolvedImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        SpacePlaceholder(seed: article.id)
                    case .empty:
                        Rectangle()
                            .fill(palette.surfaceSoft)
                            .overlay {
                                ProgressView()
                                    .tint(palette.primary)
                            }
                    @unknown default:
                        SpacePlaceholder(seed: article.id)
                    }
                }
            } else {
                SpacePlaceholder(seed: article.id)
                    .task {
                        await fetchOGImageIfNeeded()
                    }
            }
        }
        .overlay {
            if showGradientOverlay {
                LinearGradient(
                    colors: [.clear, palette.cardImageOverlay],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - OG Image Fetching

    private func fetchOGImageIfNeeded() async {
        guard !ogFetchAttempted,
              article.resolvedImageUrl == nil,
              let canonicalUrl = article.canonicalUrl
        else { return }

        ogFetchAttempted = true

        let fetcher = OGImageFetcher(modelContainer: modelContext.container)
        _ = await fetcher.fetchOGImage(articleId: article.id, canonicalUrl: canonicalUrl)
    }
}

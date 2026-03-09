import SwiftUI
import SwiftData
import UIKit
import NebularNewsKit

/// Reusable article image with automatic fallback chain:
/// RSS imageUrl -> cached OG image -> persisted Unsplash fallback -> placeholder.
///
/// Triggers OG image fetching and fallback-image selection lazily when no image is available.
struct ArticleImageView: View {
    let article: Article
    var size: ImageSize = .hero
    var showGradientOverlay: Bool = false
    var dimmingOpacity: Double = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var ogFetchAttempted = false
    @State private var fallbackFetchAttempted = false
    @State private var remoteImage: UIImage?
    @State private var loadedURLString: String?
    @State private var isLoadingRemoteImage = false
    @State private var failedURLString: String?

    enum ImageSize {
        case hero       // full width, 220pt tall
        case medium     // 130pt tall
        case thumbnail  // 60pt square
    }

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)

        GeometryReader { proxy in
            Group {
                if let remoteImage {
                    Image(uiImage: remoteImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if article.resolvedImageUrl != nil {
                    Rectangle()
                        .fill(palette.surfaceSoft)
                        .overlay {
                            if isLoadingRemoteImage {
                                ProgressView()
                                    .tint(palette.primary)
                            } else {
                                Image(systemName: "photo")
                                    .font(.title3)
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }
                        }
                } else {
                    SpacePlaceholder(seed: article.id)
                        .task {
                            await fetchOGImageIfNeeded()
                        }
                        .task {
                            await fetchFallbackImageIfNeeded()
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: article.resolvedImageUrl) {
            await loadRemoteImageIfNeeded()
        }
        .overlay {
            if dimmingOpacity > 0 {
                Color.black.opacity(dimmingOpacity)
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

    private func fetchFallbackImageIfNeeded() async {
        guard !fallbackFetchAttempted,
              article.resolvedImageUrl == nil
        else { return }

        fallbackFetchAttempted = true

        let service = ArticleFallbackImageService(modelContainer: modelContext.container)
        _ = await service.ensureFallbackImage(articleID: article.id)
    }

    private func loadRemoteImageIfNeeded() async {
        guard let urlString = article.resolvedImageUrl,
              let url = URL(string: urlString)
        else {
            return
        }

        if loadedURLString == urlString, remoteImage != nil {
            return
        }

        if failedURLString == urlString {
            return
        }

        if let cachedImage = await ArticleRemoteImageCache.shared.image(for: urlString) {
            remoteImage = cachedImage
            loadedURLString = urlString
            failedURLString = nil
            isLoadingRemoteImage = false
            return
        }

        isLoadingRemoteImage = true

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, let image = UIImage(data: data) else {
                isLoadingRemoteImage = false
                failedURLString = urlString
                return
            }

            await ArticleRemoteImageCache.shared.insert(image, for: urlString)
            remoteImage = image
            loadedURLString = urlString
            failedURLString = nil
            isLoadingRemoteImage = false
        } catch {
            isLoadingRemoteImage = false
            failedURLString = urlString
        }
    }
}

private actor ArticleRemoteImageCache {
    static let shared = ArticleRemoteImageCache()

    private let cache = NSCache<NSString, UIImage>()

    func image(for urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    func insert(_ image: UIImage, for urlString: String) {
        cache.setObject(image, forKey: urlString as NSString)
    }
}

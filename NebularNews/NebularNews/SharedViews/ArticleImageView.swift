import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import NebularNewsKit

#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif

/// Reusable article image with automatic fallback chain:
/// RSS imageUrl -> cached OG image -> persisted fallback -> placeholder.
struct ArticleImageView: View {
    let article: Article
    var size: ImageSize = .hero
    var showGradientOverlay: Bool = false
    var dimmingOpacity: Double = 0

    @State private var remoteImage: PlatformImage?
    @State private var loadedURLString: String?
    @State private var isLoadingRemoteImage = false
    @State private var failedURLString: String?

    enum ImageSize {
        case hero       // full width, 220pt tall
        case medium     // 130pt tall
        case thumbnail  // 60pt square
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let remoteImage {
                    #if os(iOS)
                    Image(uiImage: remoteImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #else
                    Image(nsImage: remoteImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    #endif
                } else if article.resolvedImageUrl != nil {
                    Rectangle()
                        .fill(Color.platformTertiaryFill)
                        .overlay {
                            if isLoadingRemoteImage {
                                ProgressView()
                            } else {
                                Image(systemName: "photo")
                                    .font(.title3)
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }
                        }
                } else {
                    SpacePlaceholder(seed: article.id)
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
                    colors: [.clear, Color.platformSystemBackground.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
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
            guard !Task.isCancelled, let raw = PlatformImage(data: data) else {
                isLoadingRemoteImage = false
                failedURLString = urlString
                return
            }
            // Downscale to a max of 1200x1200 before caching to reduce memory and GPU cost.
            #if os(iOS)
            let maxSide: CGFloat = 1200
            let targetSize = CGSize(width: maxSide, height: maxSide)
            let image = await raw.byPreparingThumbnail(ofSize: targetSize) ?? raw
            #else
            let image = raw
            #endif

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

    private let cache: NSCache<NSString, PlatformImage> = {
        let c = NSCache<NSString, PlatformImage>()
        c.countLimit = 100          // max 100 images in memory
        c.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        return c
    }()

    func image(for urlString: String) -> PlatformImage? {
        cache.object(forKey: urlString as NSString)
    }

    func insert(_ image: PlatformImage, for urlString: String) {
        // Approximate byte cost: width * height * 4 bytes per pixel
        #if os(iOS)
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        #else
        let cost = Int(image.size.width * image.size.height * 4)
        #endif
        cache.setObject(image, forKey: urlString as NSString, cost: cost)
    }
}

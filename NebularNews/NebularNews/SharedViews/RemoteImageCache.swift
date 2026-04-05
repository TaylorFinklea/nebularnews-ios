import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// In-memory image cache backed by NSCache. Thread-safe via actor isolation.
/// Shared across ArticleImageView, CachedAsyncImage, and any view that loads remote images.
actor RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache: NSCache<NSString, PlatformImage> = {
        let c = NSCache<NSString, PlatformImage>()
        c.countLimit = 100
        c.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        return c
    }()

    func image(for urlString: String) -> PlatformImage? {
        cache.object(forKey: urlString as NSString)
    }

    func insert(_ image: PlatformImage, for urlString: String) {
        #if os(iOS)
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        #else
        let cost = Int(image.size.width * image.size.height * 4)
        #endif
        cache.setObject(image, forKey: urlString as NSString, cost: cost)
    }
}

/// Async image view with in-memory caching. Drop-in replacement for AsyncImage
/// that avoids re-fetching images on every view appearance.
struct CachedAsyncImage: View {
    let url: URL
    var contentMode: ContentMode = .fit

    @State private var image: PlatformImage?
    @State private var isLoading = false
    @State private var hasFailed = false

    var body: some View {
        Group {
            if let image {
                #if os(iOS)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                #else
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                #endif
            } else if isLoading {
                Rectangle()
                    .fill(Color.platformTertiaryFill)
                    .overlay { ProgressView() }
            } else if hasFailed {
                Rectangle()
                    .fill(Color.platformTertiaryFill)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            } else {
                Rectangle()
                    .fill(Color.platformTertiaryFill)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let urlString = url.absoluteString

        if let cached = await RemoteImageCache.shared.image(for: urlString) {
            image = cached
            return
        }

        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, let raw = PlatformImage(data: data) else {
                isLoading = false
                hasFailed = true
                return
            }

            #if os(iOS)
            let downscaled = await raw.byPreparingThumbnail(ofSize: CGSize(width: 1200, height: 1200)) ?? raw
            #else
            let downscaled = raw
            #endif

            await RemoteImageCache.shared.insert(downscaled, for: urlString)
            image = downscaled
            isLoading = false
        } catch {
            isLoading = false
            hasFailed = true
        }
    }
}

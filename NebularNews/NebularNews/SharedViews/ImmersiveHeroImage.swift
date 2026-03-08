import SwiftUI
import NebularNewsKit

/// Full-bleed parallax hero image for the article detail immersive reader.
///
/// Stretches on overscroll and compresses with parallax on scroll-up.
/// A gradient at the bottom fades the image into the space backdrop.
struct ImmersiveHeroImage: View {
    let article: Article
    let scrollOffset: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private let baseHeight: CGFloat = 320

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)

        GeometryReader { geo in
            let overscroll = max(0, -scrollOffset)
            let parallax = scrollOffset > 0 ? -scrollOffset * 0.5 : 0

            ArticleImageView(article: article, size: .hero)
                .frame(
                    width: geo.size.width,
                    height: baseHeight + overscroll
                )
                .offset(y: parallax)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            .clear,
                            palette.heroGradientEnd.opacity(0.6),
                            palette.heroGradientEnd
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }
        }
        .frame(height: baseHeight)
    }
}

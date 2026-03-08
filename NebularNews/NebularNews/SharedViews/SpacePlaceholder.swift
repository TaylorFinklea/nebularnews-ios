import SwiftUI

/// Space-themed generated placeholder for articles without images.
///
/// Uses a hash of the seed string (typically `article.id`) to generate
/// a unique mini-nebula scene per article, keeping visuals consistent
/// across redraws and on-brand with the cosmic identity.
struct SpacePlaceholder: View {
    let seed: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)
        let hash = seedHash

        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [palette.backgroundStart, palette.backgroundEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    // Primary nebula blob
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    palette.nebulaA.opacity(0.5),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: geo.size.width * 0.6
                            )
                        )
                        .frame(
                            width: geo.size.width * 0.8,
                            height: geo.size.height * 0.8
                        )
                        .offset(
                            x: hashFloat(hash, offset: 0) * geo.size.width * 0.4 - geo.size.width * 0.2,
                            y: hashFloat(hash, offset: 1) * geo.size.height * 0.4 - geo.size.height * 0.2
                        )
                        .blur(radius: 20)
                }
                .overlay {
                    // Secondary accent blob
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    palette.nebulaB.opacity(0.4),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: geo.size.width * 0.5
                            )
                        )
                        .frame(
                            width: geo.size.width * 0.6,
                            height: geo.size.height * 0.6
                        )
                        .offset(
                            x: hashFloat(hash, offset: 2) * geo.size.width * 0.5 - geo.size.width * 0.25,
                            y: hashFloat(hash, offset: 3) * geo.size.height * 0.5 - geo.size.height * 0.25
                        )
                        .blur(radius: 16)
                }
                .overlay {
                    // Star dots
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(0.15 + hashFloat(hash, offset: 4 + i) * 0.2))
                            .frame(width: 1.5 + hashFloat(hash, offset: 12 + i) * 2)
                            .position(
                                x: hashFloat(hash, offset: 20 + i) * geo.size.width,
                                y: hashFloat(hash, offset: 28 + i) * geo.size.height
                            )
                    }
                }
                .overlay {
                    // Center icon
                    Image(systemName: placeholderIcon)
                        .font(.title)
                        .foregroundStyle(palette.primary.opacity(0.25))
                }
        }
    }

    // MARK: - Private

    private var seedHash: UInt64 {
        var hasher = Hasher()
        hasher.combine(seed)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private func hashFloat(_ hash: UInt64, offset: Int) -> CGFloat {
        let shifted = hash &>> (offset % 8 * 8)
        return CGFloat(shifted & 0xFF) / 255.0
    }

    private var placeholderIcon: String {
        let icons = ["sparkles", "star", "moon.stars", "sun.max", "cloud"]
        let index = Int(seedHash % UInt64(icons.count))
        return icons[index]
    }
}

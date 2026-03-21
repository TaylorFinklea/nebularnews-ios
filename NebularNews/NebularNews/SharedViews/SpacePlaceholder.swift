import SwiftUI

/// Generated placeholder for articles without images.
///
/// Uses a hash of the seed string (typically `article.id`) to pick a
/// deterministic icon and tint, keeping visuals varied and consistent
/// across redraws without requiring theme colors.
struct SpacePlaceholder: View {
    let seed: String

    private static let tints: [Color] = [
        .blue, .indigo, .purple, .teal, .green, .orange
    ]

    private static let icons = [
        "sparkles", "star", "moon.stars", "sun.max", "cloud", "bolt"
    ]

    var body: some View {
        let tint = Self.tints[Int(seedHash % UInt64(Self.tints.count))]
        let icon = Self.icons[Int(seedHash % UInt64(Self.icons.count))]
        ZStack {
            tint.opacity(0.12)
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(tint.opacity(0.5))
        }
    }

    private var seedHash: UInt64 {
        var hasher = Hasher()
        hasher.combine(seed)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}

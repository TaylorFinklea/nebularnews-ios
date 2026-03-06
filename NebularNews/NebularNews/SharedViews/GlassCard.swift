import SwiftUI

/// Reusable card with iOS 26 Liquid Glass material.
///
/// Uses `.glassEffect(.regular)` for the standard translucent look
/// that adapts to the content behind it. Pass a `tint` color for
/// semantic coloring (e.g., score-colored cards).
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var tintColor: Color?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .tint(tintColor)
    }
}

/// Score badge pill with glass effect.
struct ScoreBadge: View {
    let score: Int?

    var body: some View {
        if let score {
            Text("\(score)")
                .font(.caption.bold())
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .tint(Color.forScore(score))
        }
    }
}

/// Colored tag pill with glass effect.
struct TagPill: View {
    let name: String
    var colorHex: String?

    var body: some View {
        Text(name)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .tint(tagColor)
    }

    private var tagColor: Color? {
        guard let hex = colorHex else { return nil }
        return Color(hex: hex)
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)

        let r, g, b: Double
        switch sanitized.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

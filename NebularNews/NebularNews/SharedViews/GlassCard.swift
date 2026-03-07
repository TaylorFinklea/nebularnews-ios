import SwiftUI
import NebularNewsKit

enum GlassSurfaceStyle {
    case standard
    case raised
    case accented
}

/// Reusable card with iOS 26 Liquid Glass material.
///
/// Uses `.glassEffect(.regular)` for the standard translucent look
/// that adapts to the content behind it. Pass a `tint` color for
/// semantic coloring (e.g., score-colored cards).
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var style: GlassSurfaceStyle = .standard
    var tintColor: Color?
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding()
            .modifier(GlassCardBackground(shape: shape, style: style, tintColor: tintColor))
    }
}

/// Score badge pill with glass effect.
struct ScoreBadge: View {
    let score: Int?

    var body: some View {
        if let score {
            Text("\(score)/5")
                .font(.caption.bold())
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .modifier(GlassCapsuleBackground(style: .accented, tintColor: Color.forScore(score)))
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
            .modifier(GlassCapsuleBackground(style: .accented, tintColor: tagColor))
    }

    private var tagColor: Color? {
        guard let hex = colorHex else { return nil }
        return Color(hex: hex)
    }
}

/// Applies glass or material background to any rounded rectangle.
/// Use this for dashboard cards, stat pills, or any element that
/// should get Liquid Glass on iOS 26+ without the full GlassCard padding.
struct GlassRoundedBackground: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        glassContent(content, shape: shape)
    }

    @ViewBuilder
    private func glassContent(_ content: Content, shape: RoundedRectangle) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            fallbackContent(content, shape: shape)
        }
#else
        fallbackContent(content, shape: shape)
#endif
    }

    private func fallbackContent(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
    }
}

private struct GlassCardBackground<ShapeType: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let shape: ShapeType
    let style: GlassSurfaceStyle
    let tintColor: Color?

    func body(content: Content) -> some View {
        glassContent(content)
            .overlay(shape.strokeBorder(borderColor))
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
    }

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    private var effectiveTintColor: Color? {
        switch style {
        case .standard:
            return tintColor
        case .raised:
            return tintColor ?? palette.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
        case .accented:
            return tintColor ?? palette.primary
        }
    }

    private var tintFill: Color {
        switch style {
        case .standard:
            return palette.surface
        case .raised:
            return palette.surfaceStrong
        case .accented:
            return (tintColor ?? palette.primary).opacity(colorScheme == .dark ? 0.18 : 0.12)
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard:
            return palette.surfaceBorder.opacity(colorScheme == .dark ? 0.95 : 0.82)
        case .raised:
            return palette.surfaceBorder.opacity(colorScheme == .dark ? 1.0 : 0.9)
        case .accented:
            return (tintColor ?? palette.primary).opacity(colorScheme == .dark ? 0.26 : 0.18)
        }
    }

    private var shadowColor: Color {
        palette.shadow.opacity(style == .raised ? 0.42 : 0.18)
    }

    private var shadowRadius: CGFloat {
        style == .raised ? 20 : 12
    }

    private var shadowYOffset: CGFloat {
        style == .raised ? 10 : 6
    }

    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .tint(effectiveTintColor)
        } else {
            fallbackContent(content)
        }
#else
        fallbackContent(content)
#endif
    }

    private func fallbackContent(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(tintFill, in: shape)
    }
}

private struct GlassCapsuleBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let style: GlassSurfaceStyle
    let tintColor: Color?

    func body(content: Content) -> some View {
        glassContent(content)
            .overlay(Capsule().strokeBorder(borderColor))
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
    }

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    private var effectiveTintColor: Color? {
        switch style {
        case .standard:
            return tintColor
        case .raised:
            return tintColor ?? palette.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
        case .accented:
            return tintColor ?? palette.primary
        }
    }

    private var tintFill: Color {
        switch style {
        case .standard:
            return palette.surface
        case .raised:
            return palette.surfaceStrong
        case .accented:
            return (tintColor ?? palette.primary).opacity(colorScheme == .dark ? 0.16 : 0.11)
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard:
            return palette.surfaceBorder.opacity(colorScheme == .dark ? 0.9 : 0.78)
        case .raised:
            return palette.surfaceBorder.opacity(colorScheme == .dark ? 1.0 : 0.85)
        case .accented:
            return (tintColor ?? palette.primary).opacity(colorScheme == .dark ? 0.22 : 0.16)
        }
    }

    private var shadowColor: Color {
        palette.shadow.opacity(style == .raised ? 0.26 : 0.12)
    }

    private var shadowRadius: CGFloat {
        style == .raised ? 14 : 8
    }

    private var shadowYOffset: CGFloat {
        style == .raised ? 8 : 4
    }

    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
                .tint(effectiveTintColor)
        } else {
            fallbackContent(content)
        }
#else
        fallbackContent(content)
#endif
    }

    private func fallbackContent(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .background(tintFill, in: Capsule())
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

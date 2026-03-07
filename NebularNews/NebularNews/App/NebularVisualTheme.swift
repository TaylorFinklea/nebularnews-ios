import SwiftUI

struct NebularPalette {
    let backgroundStart: Color
    let backgroundMid: Color
    let backgroundEnd: Color
    let nebulaA: Color
    let nebulaB: Color
    let textPrimary: Color
    let textSecondary: Color
    let surface: Color
    let surfaceStrong: Color
    let surfaceSoft: Color
    let surfaceBorder: Color
    let primary: Color
    let primaryStrong: Color
    let primarySoft: Color
    let danger: Color
    let shadow: Color

    static func forColorScheme(_ colorScheme: ColorScheme) -> NebularPalette {
        switch colorScheme {
        case .dark:
            return NebularPalette(
                backgroundStart: rgb(0x030711),
                backgroundMid: rgb(0x080E24),
                backgroundEnd: rgb(0x110D2E),
                nebulaA: rgba(99, 72, 255, 0.18),
                nebulaB: rgba(40, 100, 200, 0.12),
                textPrimary: rgb(0xE8ECF4),
                textSecondary: rgba(200, 210, 235, 0.58),
                surface: rgba(10, 14, 36, 0.72),
                surfaceStrong: rgba(8, 11, 28, 0.85),
                surfaceSoft: rgba(16, 20, 48, 0.55),
                surfaceBorder: rgba(120, 130, 200, 0.07),
                primary: rgb(0x7C6AEF),
                primaryStrong: rgb(0x6B57E8),
                primarySoft: rgba(124, 106, 239, 0.12),
                danger: rgb(0xF47A94),
                shadow: rgba(0, 2, 12, 0.50)
            )
        default:
            return NebularPalette(
                backgroundStart: rgb(0xF8F7FC),
                backgroundMid: rgb(0xEEE9F8),
                backgroundEnd: rgb(0xE4DDF5),
                nebulaA: rgba(110, 80, 220, 0.10),
                nebulaB: rgba(60, 140, 220, 0.08),
                textPrimary: rgb(0x1A1430),
                textSecondary: rgba(26, 20, 48, 0.52),
                surface: rgba(255, 255, 255, 0.88),
                surfaceStrong: rgba(255, 255, 255, 0.94),
                surfaceSoft: rgba(246, 242, 255, 0.85),
                surfaceBorder: rgba(80, 60, 150, 0.06),
                primary: rgb(0x5A3ED6),
                primaryStrong: rgb(0x4C30C4),
                primarySoft: rgba(90, 62, 214, 0.08),
                danger: rgb(0xB82850),
                shadow: rgba(40, 20, 100, 0.10)
            )
        }
    }

    private static func rgb(_ hex: Int) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    private static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255, opacity: opacity)
    }
}

enum NebularBackdropEmphasis {
    case standard
    case hero
    case reading
}

struct NebularBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var emphasis: NebularBackdropEmphasis = .standard

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)

        Rectangle()
            .fill(
                LinearGradient(
                    colors: [palette.backgroundStart, palette.backgroundMid, palette.backgroundEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.nebulaA.opacity(nebulaOpacityScale(primary: true)),
                                .clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 280
                        )
                    )
                    .frame(width: 520, height: 520)
                    .offset(x: -120, y: -160)
                    .blur(radius: 8)
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.nebulaB.opacity(nebulaOpacityScale(primary: false)),
                                .clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 240
                        )
                    )
                    .frame(width: 460, height: 460)
                    .offset(x: 120, y: -100)
                    .blur(radius: 12)
            }
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.primary.opacity(bottomGlowOpacity),
                                .clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 260
                        )
                    )
                    .frame(width: 540, height: 300)
                    .offset(y: 140)
                    .blur(radius: 20)
            }
            .overlay {
                LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.02 : 0.08), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
    }

    private func nebulaOpacityScale(primary: Bool) -> Double {
        switch emphasis {
        case .standard:
            return primary ? 1.0 : 0.95
        case .hero:
            return primary ? 1.18 : 1.12
        case .reading:
            return primary ? 0.72 : 0.60
        }
    }

    private var bottomGlowOpacity: Double {
        switch emphasis {
        case .standard: 0.05
        case .hero: 0.08
        case .reading: 0.03
        }
    }
}

struct NebularScreen<Content: View>: View {
    var emphasis: NebularBackdropEmphasis = .standard
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            NebularBackdrop(emphasis: emphasis)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct NebularHeaderHalo: View {
    @Environment(\.colorScheme) private var colorScheme

    var color: Color? = nil
    var alignment: Alignment = .topLeading

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)
        let haloColor = color ?? palette.primary

        Circle()
            .fill(
                RadialGradient(
                    colors: [haloColor.opacity(colorScheme == .dark ? 0.26 : 0.18), .clear],
                    center: .center,
                    startRadius: 12,
                    endRadius: 170
                )
            )
            .frame(width: 220, height: 220)
            .blur(radius: 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

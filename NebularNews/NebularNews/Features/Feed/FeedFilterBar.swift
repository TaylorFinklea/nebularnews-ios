import SwiftUI

enum FeedFilterMode: String, CaseIterable {
    case unread = "Unread"
    case all = "All"
    case scored = "Scored"
    case read = "Read"
}

/// Horizontal scrolling filter bar for the Feed tab.
struct FeedFilterBar: View {
    @Binding var filterMode: FeedFilterMode
    let count: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = NebularPalette.forColorScheme(colorScheme)

        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FeedFilterMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                filterMode = mode
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .modifier(GlassRoundedBackground(cornerRadius: 20))
                                .foregroundStyle(
                                    filterMode == mode ? palette.primary : palette.textSecondary
                                )
                                .overlay {
                                    if filterMode == mode {
                                        Capsule()
                                            .strokeBorder(palette.primary.opacity(0.3))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .modifier(GlassRoundedBackground(cornerRadius: 12))
        }
    }
}

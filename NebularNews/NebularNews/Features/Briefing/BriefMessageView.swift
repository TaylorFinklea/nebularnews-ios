import SwiftUI

/// Bullet-level action emitted by the Today brief surface. Dispatched
/// either by inline buttons (Save, Tell me more) or by native swipe
/// actions on each List row (Like, Dislike, Dismiss).
enum BriefBulletAction {
    case save(articleIds: [String])
    case reactUp(articleIds: [String])
    case reactDown(articleIds: [String])
    case dismiss(signature: String, articleIds: [String])
    case tellMeMore(prompt: String)
    case openArticle(articleId: String)
}

/// Compact section header for a brief seed. Renders the brief's display
/// title with a sparkle gradient accent and a subdued generation
/// timestamp. Designed to sit at the top of a List Section so the
/// bullets below feel grouped without a heavy outer card frame.
struct BriefSectionHeader: View {
    let brief: SeededBrief

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(brief.displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                if let generatedAt = brief.generatedAt {
                    Text(
                        Date(timeIntervalSince1970: TimeInterval(generatedAt) / 1000)
                            .formatted(date: .abbreviated, time: .shortened)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .textCase(nil)
    }
}

/// One bullet inside a brief: text, source pills, action chips. Tapping
/// a source navigates to article detail; tapping an action chip fires
/// `onAction` for the parent to dispatch. Reactions and dismiss live on
/// the parent List row's native swipe actions, so this view only renders
/// Save (high-frequency affirmative) and Tell me more (assistant
/// hand-off).
struct BriefBulletCard: View {
    let bullet: SeededBrief.Bullet
    let onAction: (BriefBulletAction) -> Void

    private var allArticleIds: [String] { bullet.sources.map(\.articleId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bullet.text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)

            if !bullet.sources.isEmpty {
                sourcePills
            }

            actionChips
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassRoundedBackground(cornerRadius: 14))
    }

    private var sourcePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bullet.sources) { source in
                    Button {
                        onAction(.openArticle(articleId: source.articleId))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text(source.title ?? "Source")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.platformTertiaryFill)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actionChips: some View {
        HStack(spacing: 6) {
            chip(systemImage: "bookmark", label: "Save") {
                onAction(.save(articleIds: allArticleIds))
            }
            Spacer(minLength: 4)
            chip(systemImage: "sparkles", label: "Tell me more", emphasized: true) {
                onAction(.tellMeMore(prompt: bullet.text))
            }
        }
    }

    /// First ~60 chars of the bullet, used as the initial topic signature
    /// in the dismiss sheet (user can edit before confirming). Static so
    /// the parent List section can build the swipe action without
    /// re-deriving the rule.
    static func signature(for bullet: SeededBrief.Bullet) -> String {
        let trimmed = bullet.text.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 60 { return trimmed }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 60)
        return String(trimmed[..<cutoff]) + "…"
    }

    @ViewBuilder
    private func chip(systemImage: String, label: String?, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption)
                if let label { Text(label).font(.caption) }
            }
            .padding(.horizontal, label == nil ? 8 : 10)
            .padding(.vertical, 6)
            .background(emphasized ? Color.accentColor.opacity(0.15) : Color.platformTertiaryFill)
            .foregroundStyle(emphasized ? Color.accentColor : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

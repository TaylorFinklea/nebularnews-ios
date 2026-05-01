import SwiftUI

/// Renders a `brief_seed` chat message as the centerpiece of the Today
/// tab. Sits in the chat thread above any text follow-ups; structured
/// data (bullets + sources + actions) replaces what would otherwise be
/// a plain text bubble.
struct BriefMessageView: View {
    let brief: SeededBrief
    /// Action callback. Args:
    ///   .save        — bullet's source article ids
    ///   .reactUp     — bullet's source article ids
    ///   .reactDown   — bullet's source article ids
    ///   .dismiss     — the bullet itself (need text + ids for the sheet)
    ///   .tellMeMore  — bullet's text becomes the user follow-up prompt
    let onAction: (BulletAction) -> Void

    enum BulletAction {
        case save(articleIds: [String])
        case reactUp(articleIds: [String])
        case reactDown(articleIds: [String])
        case dismiss(signature: String, articleIds: [String])
        case tellMeMore(prompt: String)
        case openArticle(articleId: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ForEach(brief.bullets) { bullet in
                BulletSwipeContainer(
                    leading: [
                        .init(
                            label: "Like",
                            systemImage: "hand.thumbsup.fill",
                            tint: .green,
                            perform: { onAction(.reactUp(articleIds: bullet.sources.map(\.articleId))) }
                        )
                    ],
                    trailing: [
                        .init(
                            label: "Dislike",
                            systemImage: "hand.thumbsdown.fill",
                            tint: .orange,
                            perform: { onAction(.reactDown(articleIds: bullet.sources.map(\.articleId))) }
                        ),
                        .init(
                            label: "Dismiss",
                            systemImage: "xmark",
                            tint: .red,
                            perform: { onAction(.dismiss(signature: BriefBulletCard.signature(for: bullet),
                                                          articleIds: bullet.sources.map(\.articleId))) }
                        )
                    ]
                ) {
                    BriefBulletCard(bullet: bullet, onAction: onAction)
                }
            }
        }
        .padding(16)
        .background(Color.platformSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(brief.displayTitle)
                .font(.title3.bold())
            if let generatedAt = brief.generatedAt {
                Text(Date(timeIntervalSince1970: TimeInterval(generatedAt) / 1000).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One bullet inside a brief message: text, source pills, action chips.
/// Tapping a source navigates to the article detail; tapping an action
/// chip fires `onAction` for the parent to dispatch.
struct BriefBulletCard: View {
    let bullet: SeededBrief.Bullet
    let onAction: (BriefMessageView.BulletAction) -> Void

    private var allArticleIds: [String] { bullet.sources.map(\.articleId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bullet.text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)

            if !bullet.sources.isEmpty {
                sourcePills
            }

            actionChips
        }
        .padding(12)
        .background(Color.platformSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    /// Reactions and dismiss live in the leading/trailing swipe actions
    /// on `BulletSwipeContainer`; this row keeps Save (high-frequency
    /// affirmative action) and Tell me more (the emphasized assistant
    /// hand-off).
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
    /// in the dismiss sheet (user can edit it there before confirming).
    /// Exposed at the type level so the parent swipe container can build
    /// the dismiss action without re-deriving the rule.
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

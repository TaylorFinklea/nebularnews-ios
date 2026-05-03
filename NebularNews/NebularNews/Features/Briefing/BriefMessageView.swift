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

/// One bullet inside a brief: text, metadata strip (source + score +
/// tags), and action chips. Tapping the bullet body fires `.openArticle`
/// for the primary source so the user can read the full article in
/// detail view; reactions and dismiss are surfaced via the parent List
/// row's native swipe actions.
struct BriefBulletCard: View {
    let bullet: SeededBrief.Bullet
    let onAction: (BriefBulletAction) -> Void

    private var allArticleIds: [String] { bullet.sources.map(\.articleId) }

    /// Source the user lands on when they tap the card. Highest scored
    /// among the bullet's sources, falling back to the first one (which
    /// preserves the AI's original ordering when no scores are present).
    private var primarySource: SeededBrief.Bullet.Source? {
        bullet.sources.max(by: { ($0.score ?? -1) < ($1.score ?? -1) })
            ?? bullet.sources.first
    }

    /// Aggregated user score across the bullet's sources. Max is more
    /// informative than average for "how relevant is this to me" — one
    /// strong source is what makes the whole bullet matter.
    private var aggregateScore: Int? {
        let scores = bullet.sources.compactMap(\.score)
        return scores.max()
    }

    /// Top tags across all sources, deduped, capped at 3 to keep the
    /// metadata strip compact. Order preserves the first-seen order
    /// across the source list (AI-picked sources come first).
    private var aggregateTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for source in bullet.sources {
            for tag in source.tags where !seen.contains(tag) {
                seen.insert(tag)
                result.append(tag)
                if result.count >= 3 { return result }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tappable region: bullet text + metadata strip. Save and
            // Tell me more sit outside this Button so their taps don't
            // also navigate to the article.
            Button {
                if let id = primarySource?.articleId {
                    onAction(.openArticle(articleId: id))
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(bullet.text)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    if !bullet.sources.isEmpty {
                        metadataStrip
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !aggregateTags.isEmpty {
                tagStrip
            }

            actionChips
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassRoundedBackground(cornerRadius: 14))
    }

    /// Source name + score badge. Multi-source bullets show the primary
    /// feed name with a "+N" indicator so the user knows how broadly
    /// the bullet is corroborated.
    @ViewBuilder
    private var metadataStrip: some View {
        HStack(spacing: 8) {
            if let score = aggregateScore {
                ScoreBadge(score: score)
            }
            if let primary = primarySource?.sourceName {
                let extras = max(bullet.sources.count - 1, 0)
                Label {
                    Text(extras > 0 ? "\(primary) +\(extras)" : primary)
                        .font(.caption)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "newspaper")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var tagStrip: some View {
        HStack(spacing: 6) {
            ForEach(aggregateTags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            Spacer()
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

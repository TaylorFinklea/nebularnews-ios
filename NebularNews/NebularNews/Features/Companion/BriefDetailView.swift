import SwiftUI

/// Pushed from BriefHistoryView rows and from deep links (nebularnews://brief/{id}).
/// Loads the full brief detail including source-article metadata.
struct BriefDetailView: View {
    let briefId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var detail: CompanionBriefDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && detail == nil {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if let detail {
                    header(detail: detail)
                    bulletsSection(detail: detail)
                    if !detail.sourceArticles.isEmpty {
                        sourcesSection(detail: detail)
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn't load brief",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                }
            }
            .padding()
        }
        .navigationTitle(titleString)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let detail {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: markdownExport(detail: detail)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: briefId) {
            await loadDetail()
        }
        .onAppear {
            SeenBriefStore.markSeen(briefId)
        }
    }

    // MARK: - Sections

    private func header(detail: CompanionBriefDetail) -> some View {
        HStack(alignment: .top) {
            Image(systemName: detail.editionKind == "morning" ? "sunrise.fill" : detail.editionKind == "evening" ? "moon.stars.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(detail.editionKind == "morning" ? .orange : detail.editionKind == "evening" ? .indigo : .purple)
            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel(detail.editionKind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(generatedLabel(detail.generatedAt))
                    .font(.headline)
                if let topic = detail.topicTagName {
                    Text("#\(topic)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                Text(windowLabel(detail: detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func bulletsSection(detail: CompanionBriefDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(detail.bullets) { bullet in
                BriefBulletRow(bullet: bullet)
            }
        }
    }

    private func sourcesSection(detail: CompanionBriefDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(detail.sourceArticles) { article in
                NavigationLink(destination: CompanionArticleDetailView(articleId: article.id)) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(article.title ?? "Untitled")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var titleString: String {
        guard let kind = detail?.editionKind else { return "Brief" }
        return kindLabel(kind)
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "morning": return "Morning Brief"
        case "evening": return "Evening Brief"
        default: return "News Brief"
        }
    }

    private func generatedLabel(_ generatedAt: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(generatedAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func windowLabel(detail: CompanionBriefDetail) -> String {
        let hours = max(1, (detail.windowEnd - detail.windowStart) / 3_600_000)
        return "Last \(hours)h • score ≥ \(detail.scoreCutoff)"
    }

    private func markdownExport(detail: CompanionBriefDetail) -> String {
        var lines: [String] = []
        lines.append("# \(kindLabel(detail.editionKind)) — \(generatedLabel(detail.generatedAt))")
        lines.append("")
        for bullet in detail.bullets {
            lines.append("- \(bullet.text)")
            for source in bullet.sources {
                lines.append("  - [\(source.title ?? "Source")](nebularnews://article/\(source.articleId))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Data

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await appState.supabase.fetchBrief(id: briefId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

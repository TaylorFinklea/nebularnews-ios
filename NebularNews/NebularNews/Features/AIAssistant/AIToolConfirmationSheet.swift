import SwiftUI

/// Confirmation sheet shown when the AI assistant proposes a destructive action
/// that requires user approval before executing.
struct AIToolConfirmationSheet: View {
    let proposal: PendingProposal
    let onConfirm: (_ edits: [String: AnyCodable]?, _ dontAskAgain: Bool) -> Void
    let onReject: () -> Void

    @State private var dontAskAgain = false
    @State private var decidedAction = false

    struct PendingProposal: Identifiable {
        let proposeId: String
        let toolName: String
        let summary: String
        let detail: ToolProposalDetail
        let contextHint: String?

        var id: String { proposeId }
    }

    var body: some View {
        NavigationStack {
            List {
                // Context hint
                if let hint = proposal.contextHint, !hint.isEmpty {
                    Section {
                        Label {
                            Text("You asked: \"\(hint)\"")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "bubble.left")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Tool-specific detail block
                Section {
                    detailBlock
                }

                // Don't ask again option
                Section {
                    Toggle(isOn: $dontAskAgain) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Don't ask again for this action")
                                .font(.body)
                            Text("Future requests will run immediately with a 7-second undo window")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(proposal.summary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        decidedAction = true
                        onReject()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionButtonLabel) {
                        decidedAction = true
                        onConfirm(nil, dontAskAgain)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            // If sheet was dismissed without a decision (e.g. swipe), treat as cancel.
            if !decidedAction {
                onReject()
            }
        }
    }

    // MARK: - Detail blocks

    @ViewBuilder
    private var detailBlock: some View {
        switch proposal.detail {
        case .markArticlesRead(let count, let previews, let remaining, let breakdown):
            markArticlesReadDetail(count: count, previews: previews, remaining: remaining, breakdown: breakdown)
        case .pauseFeed(_, let feedTitle, let count24h, let currentlyPaused):
            pauseFeedDetail(feedTitle: feedTitle, count24h: count24h, currentlyPaused: currentlyPaused)
        case .unsubscribeFromFeed(_, let feedTitle, let subscribedAt, let total, let paused):
            unsubscribeFeedDetail(feedTitle: feedTitle, subscribedAt: subscribedAt, total: total, paused: paused)
        case .setFeedMaxPerDay(_, let feedTitle, let current, let proposed, let avg):
            setMaxPerDayDetail(feedTitle: feedTitle, current: current, proposed: proposed, avg: avg)
        case .setFeedMinScore(_, let feedTitle, let currentScore, let proposed, let dist):
            setMinScoreDetail(feedTitle: feedTitle, current: currentScore, proposed: proposed, dist: dist)
        case .unknown:
            Text("No additional detail available.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func markArticlesReadDetail(
        count: Int,
        previews: [ToolProposalDetail.ArticlePreview],
        remaining: Int,
        breakdown: [ToolProposalDetail.FeedCount]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(count) article\(count == 1 ? "" : "s") across \(breakdown.count) feed\(breakdown.count == 1 ? "" : "s"):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(breakdown.prefix(5), id: \.feedTitle) { fc in
                HStack {
                    Text("• \(fc.feedTitle)")
                    Spacer()
                    Text("(\(fc.n))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if !previews.isEmpty {
                Divider()
                Text("First few:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(previews, id: \.id) { preview in
                    Text("· \"\(preview.title)\"")
                        .font(.caption)
                        .lineLimit(1)
                }
                if remaining > 0 {
                    Text("…and \(remaining) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func pauseFeedDetail(
        feedTitle: String?,
        count24h: Int,
        currentlyPaused: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = feedTitle {
                Text(title)
                    .font(.headline)
            }
            if currentlyPaused {
                Label("Already paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Text("Publishing \(count24h) article\(count24h == 1 ? "" : "s") in the last 24 hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("After pausing, no new articles until you resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func unsubscribeFeedDetail(
        feedTitle: String?,
        subscribedAt: Int?,
        total: Int,
        paused: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = feedTitle {
                Text(title)
                    .font(.headline)
            }
            if let ts = subscribedAt {
                let date = Date(timeIntervalSince1970: TimeInterval(ts / 1000))
                Text("Subscribed \(date, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(total) total article\(total == 1 ? "" : "s") fetched")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(
                "Existing read state and saved articles are kept. Re-subscribing later starts fresh — no automatic re-fetch.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func setMaxPerDayDetail(
        feedTitle: String?,
        current: Int?,
        proposed: Int,
        avg: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = feedTitle {
                Text(title)
                    .font(.headline)
            }
            HStack {
                Text("Currently:")
                    .foregroundStyle(.secondary)
                Text(current.map { "\($0)/day" } ?? "no cap")
            }
            .font(.caption)
            HStack {
                Text("After:")
                    .foregroundStyle(.secondary)
                Text(proposed > 0 ? "\(proposed)/day" : "no cap")
            }
            .font(.caption)
            Text("Feed averages \(avg) article\(avg == 1 ? "" : "s")/day")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func setMinScoreDetail(
        feedTitle: String?,
        current: Int?,
        proposed: Int,
        dist: ToolProposalDetail.ScoreDistribution
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = feedTitle {
                Text(title)
                    .font(.headline)
            }
            HStack {
                Text("Currently:")
                    .foregroundStyle(.secondary)
                Text(current.map { "score \($0)+" } ?? "no filter")
            }
            .font(.caption)
            HStack {
                Text("After:")
                    .foregroundStyle(.secondary)
                Text(proposed > 0 ? "score \(proposed)+" : "no filter")
            }
            .font(.caption)
            Text("Recent scores — 25th: \(dist.p25), median: \(dist.p50), 75th: \(dist.p75)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var actionButtonLabel: String {
        switch proposal.toolName {
        case "mark_articles_read": return "Mark as read"
        case "pause_feed": return "Pause feed"
        case "unsubscribe_from_feed": return "Unsubscribe"
        case "set_feed_max_per_day": return "Apply cap"
        case "set_feed_min_score": return "Apply score filter"
        default: return "Confirm"
        }
    }

    private var titleIcon: String {
        switch proposal.toolName {
        case "mark_articles_read": return "checkmark.circle"
        case "pause_feed": return "pause.circle"
        case "unsubscribe_from_feed": return "xmark.circle"
        case "set_feed_max_per_day": return "slider.horizontal.3"
        case "set_feed_min_score": return "chart.bar.xaxis"
        default: return "questionmark.circle"
        }
    }
}

#if DEBUG
import SwiftUI
import SwiftData
import NebularNewsKit

struct DeveloperJobInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var snapshot: ArticleProcessingDebugSnapshot?
    @State private var isRefreshing = false
    @State private var isKickingVisibility = false
    @State private var isKickingAll = false
    @State private var kickStatusMessage: String?

    var body: some View {
        List {
            Section("Queue Overview") {
                if let snapshot {
                    LabeledContent("Running", value: "\(snapshot.runningCount)")
                    LabeledContent("Queued", value: "\(snapshot.queuedCount)")
                    LabeledContent("Failed", value: "\(snapshot.failedCount)")
                    LabeledContent("Visible backlog", value: "\(snapshot.pendingVisibleCount)")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stage totals")
                            .font(.subheadline.weight(.semibold))

                        LabeledContent("Score & tag", value: "\(totalCount(for: .scoreAndTag, in: snapshot))")
                        LabeledContent("Fetch content", value: "\(totalCount(for: .fetchContent, in: snapshot))")
                        LabeledContent("Generate summary", value: "\(totalCount(for: .generateSummary, in: snapshot))")
                        LabeledContent("Resolve image", value: "\(totalCount(for: .resolveImage, in: snapshot))")
                    }
                    .padding(.vertical, 4)

                    if snapshot.queuedCount > 0 && snapshot.runningCount == 0 {
                        Label("Queued jobs exist, but nothing is actively running.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if let kickStatusMessage, !kickStatusMessage.isEmpty {
                        Text(kickStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task {
                            await kickVisibilityQueue()
                        }
                    } label: {
                        Label("Kick Visibility Queue", systemImage: "bolt.fill")
                    }
                    .disabled(isRefreshing || isKickingVisibility || isKickingAll)

                    Button {
                        Task {
                            await kickAllQueuedWork()
                        }
                    } label: {
                        Label("Run All Queued Work", systemImage: "play.fill")
                    }
                    .disabled(isRefreshing || isKickingVisibility || isKickingAll)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading job diagnostics…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Running") {
                if let snapshot, !snapshot.runningRows.isEmpty {
                    ForEach(snapshot.runningRows) { row in
                        jobRow(row)
                    }
                } else {
                    Text("No running jobs.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Queued") {
                if let snapshot, !snapshot.queuedRows.isEmpty {
                    ForEach(snapshot.queuedRows) { row in
                        jobRow(row)
                    }
                } else {
                    Text("No queued jobs.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recent Failures") {
                if let snapshot, !snapshot.failedRows.isEmpty {
                    ForEach(snapshot.failedRows) { row in
                        jobRow(row)
                    }
                } else {
                    Text("No recent failures.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Job Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshSnapshot()
        }
        .task {
            await refreshSnapshot()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isRefreshing || isKickingVisibility || isKickingAll {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func jobRow(_ row: ArticleProcessingDebugRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.articleTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? row.articleTitle! : row.articleID)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Label(stageLabel(for: row.stage), systemImage: iconName(for: row.stage))
                Spacer()
                Text(statusLabel(for: row.status))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text("Priority \(row.priority)")
                Text("Attempts \(row.attemptCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text("Updated \(row.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                if row.status == .queued {
                    Text("Available \(row.availableAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if let lastError = row.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshSnapshot() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let repo = LocalArticleRepository(modelContainer: modelContext.container)
        let snapshot = await repo.processingDebugSnapshot()
        await MainActor.run {
            self.snapshot = snapshot
            isRefreshing = false
        }
    }

    private func kickVisibilityQueue() async {
        guard !isKickingVisibility && !isKickingAll else { return }
        isKickingVisibility = true
        kickStatusMessage = "Running score-and-tag jobs for hidden articles…"

        let result = await RefreshCoordinator.shared.debugKickVisibilityQueue(
            modelContainer: modelContext.container,
            keychainService: appState.configuration.keychainService
        )

        await refreshSnapshot()
        await MainActor.run {
            kickStatusMessage = "Visibility queue: backfilled \(result.backfilled), processed \(result.processed), remaining \(result.remainingPending)."
            isKickingVisibility = false
        }
    }

    private func kickAllQueuedWork() async {
        guard !isKickingVisibility && !isKickingAll else { return }
        isKickingAll = true
        kickStatusMessage = "Running queued score, content, image, and summary jobs…"

        let result = await RefreshCoordinator.shared.debugKickAllQueuedWork(
            modelContainer: modelContext.container,
            keychainService: appState.configuration.keychainService
        )

        await refreshSnapshot()
        await MainActor.run {
            kickStatusMessage = "All work: backfilled \(result.backfilled), image backfilled \(result.imageBackfilled), processed \(result.processed), remaining visible backlog \(result.remainingPending)."
            isKickingAll = false
        }
    }

    private func totalCount(for stage: ArticleProcessingStage, in snapshot: ArticleProcessingDebugSnapshot) -> Int {
        count(for: stage, in: snapshot.runningStageCounts) +
        count(for: stage, in: snapshot.queuedStageCounts) +
        count(for: stage, in: snapshot.failedStageCounts)
    }

    private func count(for stage: ArticleProcessingStage, in counts: ArticleProcessingDebugStageCounts) -> Int {
        switch stage {
        case .scoreAndTag: counts.scoreAndTag
        case .fetchContent: counts.fetchContent
        case .generateSummary: counts.generateSummary
        case .resolveImage: counts.resolveImage
        }
    }

    private func stageLabel(for stage: ArticleProcessingStage) -> String {
        switch stage {
        case .scoreAndTag: "Score & Tag"
        case .fetchContent: "Fetch Content"
        case .generateSummary: "Generate Summary"
        case .resolveImage: "Resolve Image"
        }
    }

    private func statusLabel(for status: ArticleProcessingJobStatus) -> String {
        switch status {
        case .queued: "Queued"
        case .running: "Running"
        case .done: "Done"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }

    private func iconName(for stage: ArticleProcessingStage) -> String {
        switch stage {
        case .scoreAndTag: "dial.high"
        case .fetchContent: "doc.text.magnifyingglass"
        case .generateSummary: "text.alignleft"
        case .resolveImage: "photo"
        }
    }
}
#endif

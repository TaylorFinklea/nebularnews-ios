import SwiftUI
import SwiftData
import NebularNewsKit

struct FirstBriefingPreparationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var didStart = false
    @State private var statusMessage = "Adding your starter feeds."

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    var body: some View {
        NebularScreen(emphasis: .hero) {
            VStack(spacing: 28) {
                Spacer(minLength: 80)

                VStack(spacing: 16) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .frame(width: 108, height: 108)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(palette.primary.opacity(0.18))
                        )
                        .background {
                            NebularHeaderHalo(color: palette.primary)
                        }

                    Text("Building your first briefing")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text("We’re fetching your starter feeds first. Articles can appear before summaries and images finish in the background.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                GlassCard(cornerRadius: 28, style: .raised, tintColor: palette.primary) {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Preparing your first read", systemImage: "tray.full")
                            .font(.headline)

                        Text(statusMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .task {
            guard didStart == false else { return }
            didStart = true
            await runWarmup()
        }
    }

    private func runWarmup() async {
        let selectedFeedIDs = appState.firstBriefingFeedIDs
        guard selectedFeedIDs.isEmpty == false else {
            await MainActor.run {
                appState.finishStandaloneFirstBriefingWarmup()
            }
            return
        }

        let container = modelContext.container
        let feedRepo = LocalFeedRepository(modelContainer: container)
        let articleRepo = LocalArticleRepository(modelContainer: container)
        let settingsRepo = LocalSettingsRepository(modelContainer: container)
        let poller = FeedPoller(feedRepo: feedRepo, articleRepo: articleRepo)
        let preparation = ArticlePreparationService(
            modelContainer: container,
            keychainService: appState.configuration.keychainService
        )

        let deadline = Date().addingTimeInterval(5)

        await MainActor.run {
            statusMessage = "Fetching your selected feeds."
        }

        for feedID in selectedFeedIDs {
            let visibleCount = await articleRepo.countVisibleArticles(filter: ArticleFilter())
            if Date() >= deadline || visibleCount > 0 {
                break
            }
            _ = await poller.pollFeed(id: feedID)
        }

        let retentionDays = await settingsRepo.retentionDays()
        let maxArticlesPerFeed = await settingsRepo.maxArticlesPerFeed()
        _ = await poller.enforceArticleStoragePolicies(
            retentionDays: retentionDays,
            maxArticlesPerFeed: maxArticlesPerFeed
        )

        await MainActor.run {
            statusMessage = "Scoring articles for your first briefing."
        }

        while Date() < deadline {
            if await articleRepo.countVisibleArticles(filter: ArticleFilter()) > 0 {
                break
            }

            let backfilled = (try? await articleRepo.backfillMissingProcessingJobsForInvisibleArticles(limit: 200)) ?? 0
            let processed = await preparation.processPendingArticles(batchSize: 16, allowLowPriority: false)

            if backfilled == 0 && processed == 0 {
                break
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        await ProcessingQueueSupervisor.shared.kick(
            reason: "first_briefing_warmup",
            allowLowPriority: false
        )

        await MainActor.run {
            appState.finishStandaloneFirstBriefingWarmup()
        }
    }
}

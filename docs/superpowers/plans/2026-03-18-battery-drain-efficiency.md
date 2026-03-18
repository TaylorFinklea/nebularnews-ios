# Battery Drain & Efficiency Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the major CPU/battery drain hotspots that make the app overheat on-device, while noting crash issues found along the way.

**Architecture:** The fixes target three layers: (1) repository queries that load entire tables into memory, (2) personalization loops that run unbounded, and (3) a SwiftUI view that fetches all articles and filters client-side. Each fix is independent and can be committed separately.

**Tech Stack:** Swift, SwiftData, SwiftUI, Structured Concurrency

---

## Crash Issues Noted (Not Fixed Here)

These were found during the audit. Track separately:

1. **`fatalError` on ModelContainer init** — `NebularNewsApp.swift:25` — no recovery path if SwiftData fails
2. **`try!` in OGImageFetcher** — `OGImageFetcher.swift:48-56` — static regex init crashes on compile error
3. **`unsplashFallbackPresets[0]`** — `ArticleFallbackImageService.swift:111` — array index crash if empty
4. **Widespread silent `try?`** — errors vanish without logging across services and views
5. **Untracked `Task {}` blocks** — `ArticleListView.swift:165,181` — fire-and-forget with no cancellation

---

### Task 1: Replace `processingQueueHealth()` full-table scan with predicated fetch

**Files:**
- Modify: `NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift:416-439`

**Why:** `processingQueueHealth()` is called every 200ms during the visibility drain loop and every 5s by the watchdog. It fetches ALL articles with an empty `FetchDescriptor<Article>()`, filters in-memory for hidden+non-archived, then cross-references ALL processing jobs. This is the single hottest path in the app.

- [ ] **Step 1: Replace the full article fetch with a predicated fetch for hidden article IDs**

In `processingQueueHealth()`, replace:
```swift
let hiddenArticleIDs = Set(
    (((try? modelContext.fetch(FetchDescriptor<Article>())) ?? [])
        .filter { $0.queryIsVisible == false && $0.queryIsArchived == false }
        .map(\.id))
)
```

With a predicate-based fetch:
```swift
let hiddenDescriptor = FetchDescriptor<Article>(
    predicate: #Predicate<Article> {
        $0.queryIsVisible == false && $0.queryIsArchived == false
    }
)
let hiddenArticleIDs = Set(
    ((try? modelContext.fetch(hiddenDescriptor)) ?? []).map(\.id)
)
```

- [ ] **Step 2: Filter processing jobs with a predicate instead of fetching all**

Replace `allProcessingJobs()` call in `processingQueueHealth()` with targeted fetches:
```swift
let scoreJobDescriptor = FetchDescriptor<ArticleProcessingJob>(
    predicate: #Predicate<ArticleProcessingJob> {
        $0.stageRaw == "score_and_tag" &&
        ($0.statusRaw == "queued" || $0.statusRaw == "running")
    }
)
let scoreJobs = (try? modelContext.fetch(scoreJobDescriptor)) ?? []
let queuedScoreJobs = scoreJobs.filter { $0.status == .queued }
let runningScoreJobs = scoreJobs.filter { $0.status == .running }
```

Confirmed: `ArticleProcessingJob` stores `stageRaw` and `statusRaw` as `String` properties. Raw values: `score_and_tag`, `queued`, `running`.

- [ ] **Step 3: Build and verify the project compiles**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift
git commit -m "Optimize processingQueueHealth() to use predicated fetches instead of full-table scan"
```

---

### Task 2: Replace `activeArticleCountsByFeed()` full-table scan with predicated count

**Files:**
- Modify: `NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift:352-365`

**Why:** This method fetches every article to count how many belong to each feed. Called during feed reputation calculations. With hundreds of articles, it materializes the entire table into memory just to count.

- [ ] **Step 1: Rewrite to use a predicated fetch with minimal property loading**

Replace the full-table approach:
```swift
public func activeArticleCountsByFeed() async -> [String: Int] {
    let descriptor = FetchDescriptor<Article>(
        predicate: #Predicate<Article> { $0.queryIsArchived == false }
    )
    let articles = (try? modelContext.fetch(descriptor)) ?? []

    return articles.reduce(into: [String: Int]()) { counts, article in
        guard let feedID = article.queryFeedID else { return }
        counts[feedID, default: 0] += 1
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift
git commit -m "Optimize activeArticleCountsByFeed() to only fetch non-archived articles with minimal properties"
```

---

### Task 3: Replace `allProcessingJobs()` calls in cleanup methods with predicated fetches

**Files:**
- Modify: `NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift:1672-1734`

**Why:** `allProcessingJobs()` is called in 5 different places: `processingQueueHealth`, `removeProcessingJobs`, `cleanupOrphanedProcessingJobs`, `cleanupArchivedProcessingJobs`, and `reclaimStaleRunningProcessingJobs`. Each loads ALL jobs every time.

- [ ] **Step 1: Add a targeted `processingJobs(for:)` helper**

Add below `allProcessingJobs()`:
```swift
private func processingJobs(for articleID: String) -> [ArticleProcessingJob] {
    let descriptor = FetchDescriptor<ArticleProcessingJob>(
        predicate: #Predicate<ArticleProcessingJob> { $0.articleID == articleID }
    )
    return (try? modelContext.fetch(descriptor)) ?? []
}
```

- [ ] **Step 2: Replace `removeProcessingJobs` to use targeted fetch**

```swift
@discardableResult
private func removeProcessingJobs(for articleID: String) -> Bool {
    let jobs = processingJobs(for: articleID)
    guard !jobs.isEmpty else { return false }
    for job in jobs {
        modelContext.delete(job)
    }
    return true
}
```

- [ ] **Step 3: Replace `reclaimStaleRunningProcessingJobs` with predicated fetch**

```swift
private func reclaimStaleRunningProcessingJobs(
    timeout: TimeInterval = 120
) -> Bool {
    let cutoff = Date().addingTimeInterval(-timeout)
    let descriptor = FetchDescriptor<ArticleProcessingJob>(
        predicate: #Predicate<ArticleProcessingJob> {
            $0.statusRaw == "running" && $0.updatedAt < cutoff
        }
    )
    let staleJobs = (try? modelContext.fetch(descriptor)) ?? []
    var reclaimed = false

    for job in staleJobs {
        job.status = .queued
        job.updatedAt = Date()
        job.availableAt = Date()
        job.lastError = nil
        reclaimed = true
    }

    return reclaimed
}
```

Confirmed: `ArticleProcessingJobStatus.running` raw value is `"running"`.

- [ ] **Step 4: Replace `existingProcessingJob` to use key-based fetch**

```swift
private func existingProcessingJob(
    articleID: String,
    stage: ArticleProcessingStage
) throws -> ArticleProcessingJob? {
    let key = ArticleProcessingJob.makeKey(articleID: articleID, stage: stage)
    let descriptor = FetchDescriptor<ArticleProcessingJob>(
        predicate: #Predicate<ArticleProcessingJob> { $0.key == key }
    )
    return try modelContext.fetch(descriptor).first
}
```

- [ ] **Step 5: Replace `cleanupOrphanedProcessingJobs` to avoid full article table scan**

Use a more targeted approach — fetch all job article IDs first, then check which are orphaned:

```swift
private func cleanupOrphanedProcessingJobs() {
    let jobs = (try? modelContext.fetch(FetchDescriptor<ArticleProcessingJob>())) ?? []
    let jobArticleIDs = Set(jobs.map(\.articleID))

    guard !jobArticleIDs.isEmpty else { return }

    // Only check existence of articles referenced by jobs
    for articleID in jobArticleIDs {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { $0.id == articleID }
        )
        let exists = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
        if !exists {
            for job in jobs where job.articleID == articleID {
                modelContext.delete(job)
            }
        }
    }
}
```

- [ ] **Step 6: Replace `cleanupArchivedProcessingJobs` to avoid full article table scan**

```swift
private func cleanupArchivedProcessingJobs() -> Bool {
    let jobs = (try? modelContext.fetch(FetchDescriptor<ArticleProcessingJob>())) ?? []
    let jobArticleIDs = Set(jobs.map(\.articleID))
    guard !jobArticleIDs.isEmpty else { return false }

    // Find which job-referenced articles are archived
    let archivedDescriptor = FetchDescriptor<Article>(
        predicate: #Predicate<Article> { $0.queryIsArchived == true }
    )
    let archivedArticleIDs = Set(
        ((try? modelContext.fetch(archivedDescriptor)) ?? []).map(\.id)
    )
    let archivedJobArticleIDs = jobArticleIDs.intersection(archivedArticleIDs)
    guard !archivedJobArticleIDs.isEmpty else { return false }

    var removed = false
    for job in jobs where archivedJobArticleIDs.contains(job.articleID) {
        modelContext.delete(job)
        removed = true
    }
    return removed
}
```

- [ ] **Step 7: Build and verify**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 8: Commit**

```bash
git add NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift
git commit -m "Replace allProcessingJobs() calls with predicated fetches in cleanup methods"
```

---

### Task 4: Add iteration limits to personalization rebuild loops

**Files:**
- Modify: `NebularNewsKit/Sources/NebularNewsKit/Personalization/LocalStandalonePersonalization.swift:1467-1521`

**Why:** `rebuildHistoricalState()` processes ALL articles twice (retag+score, then rescore) in nested loops. With 500+ articles, this is thousands of sequential DB calls. The chunking via `stride` doesn't actually help because each chunk is processed sequentially and there's no cancellation check.

- [ ] **Step 1: Add Task cancellation checks to the rebuild loops**

In `rebuildHistoricalState(batchSize:)`, add cancellation checks inside both chunk loops:

```swift
private func rebuildHistoricalState(batchSize: Int) async -> Int {
    try? await repository.clearLearnedState()

    let articleIDs = await repository.listAllArticleIDs()
    var processed = 0

    for chunkStart in stride(from: 0, to: articleIDs.count, by: max(1, batchSize)) {
        guard !Task.isCancelled else { break }
        let chunk = articleIDs[chunkStart..<min(chunkStart + max(1, batchSize), articleIDs.count)]
        for articleID in chunk {
            guard !Task.isCancelled else { break }
            try? await retagAndScoreArticle(
                articleID: articleID,
                skipTagSuggestions: true,
                persistScoreAssist: false
            )
            processed += 1
        }
    }

    let events = await repository.listHistoricalLearningEvents()
    for event in events {
        guard !Task.isCancelled else { break }
        guard await refreshSnapshot(
            articleID: event.articleID,
            skipTagSuggestions: true,
            persistScoreAssist: false
        ) != nil else {
            continue
        }

        try? await rescoreArticle(articleID: event.articleID, persistScoreAssist: false)
        guard let rescoredSnapshot = await repository.storedArticleSnapshot(for: event.articleID) else {
            continue
        }

        switch event.kind {
        case .reaction:
            guard let finalValue = event.reactionValue else { continue }
            await applyReactionLearning(
                snapshot: rescoredSnapshot,
                finalValue: finalValue,
                reasonCodes: event.reasonCodes
            )
        case .dismiss:
            await applyDismissLearning(snapshot: rescoredSnapshot)
        }
    }

    for chunkStart in stride(from: 0, to: articleIDs.count, by: max(1, batchSize)) {
        guard !Task.isCancelled else { break }
        let chunk = articleIDs[chunkStart..<min(chunkStart + max(1, batchSize), articleIDs.count)]
        for articleID in chunk {
            guard !Task.isCancelled else { break }
            try? await rescoreArticle(articleID: articleID, persistScoreAssist: false)
        }
    }

    return processed
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add NebularNewsKit/Sources/NebularNewsKit/Personalization/LocalStandalonePersonalization.swift
git commit -m "Add Task cancellation checks to personalization rebuild loops"
```

---

### Task 5: Add cancellation checks to `rescoreRelatedArticles` and `rescoreSameFeedArticles`

**Files:**
- Modify: `NebularNewsKit/Sources/NebularNewsKit/Personalization/LocalStandalonePersonalization.swift:1410-1440`

**Why:** After a user reaction, `rescoreRelatedArticles` and `rescoreSameFeedArticles` each loop through up to 100 articles sequentially calling `retagAndScoreArticle` or `rescoreArticle`. These fire as unstructured tasks from user swipe actions and can pile up.

- [ ] **Step 1: Add cancellation checks to both loop methods**

```swift
private func rescoreRelatedArticles(for articleID: String) async {
    let impactedIDs = await repository.impactedArticleIDs(for: articleID, limit: impactedArticleRescoreLimit)

    for impactedID in impactedIDs {
        guard !Task.isCancelled else { break }
        if await repository.needsRetagging(articleID: impactedID) {
            try? await retagAndScoreArticle(articleID: impactedID)
        } else {
            try? await rescoreArticle(articleID: impactedID)
        }
    }
}

private func rescoreSameFeedArticles(for articleID: String) async {
    let impactedIDs = await repository.sameFeedArticleIDs(for: articleID, limit: impactedArticleRescoreLimit)

    for impactedID in impactedIDs {
        guard !Task.isCancelled else { break }
        if await repository.needsRetagging(articleID: impactedID) {
            try? await retagAndScoreArticle(articleID: impactedID)
        } else {
            try? await rescoreArticle(articleID: impactedID)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add NebularNewsKit/Sources/NebularNewsKit/Personalization/LocalStandalonePersonalization.swift
git commit -m "Add cancellation checks to rescore loop methods"
```

---

### Task 6: Replace ArticleListView in-memory filtering with repository-backed fetch

**Files:**
- Modify: `NebularNews/NebularNews/Features/Articles/ArticleListView.swift`

**Why:** `ArticleListView` uses `@Query` to fetch ALL articles sorted by date, then runs 4+ filter passes in a computed property on every view body evaluation. This is the most visible CPU drain because it runs on the main thread during scrolling. The `FeedTabView` already has a proper ViewModel pattern with `listFeedPage()` — `ArticleListView` should follow the same approach.

- [ ] **Step 1: Replace @Query with a ViewModel pattern**

Rewrite `ArticleListView` to use a ViewModel that calls the repository's existing `listFeedPage()` and `countFeed()` methods, similar to how `FeedTabView` does it:

```swift
import SwiftUI
import SwiftData
import NebularNewsKit

struct ArticleListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var viewModel = ArticleListViewModel()

    let feedId: String?
    let feedTitle: String?

    init(feedId: String? = nil, feedTitle: String? = nil) {
        self.feedId = feedId
        self.feedTitle = feedTitle
    }

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case read = "Read"
        case scored = "Scored"
        case learning = "Learning"
    }

    var body: some View {
        NavigationStack {
            NebularScreen(emphasis: .reading) {
                Group {
                    if viewModel.isLoading && viewModel.articles.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.articles.isEmpty && viewModel.totalCount == 0 && searchText.isEmpty {
                        ContentUnavailableView(
                            "No Articles Yet",
                            systemImage: "doc.text",
                            description: Text("Go to More → Feeds to add an RSS feed, then pull to refresh.")
                        )
                    } else if viewModel.articles.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List {
                            Section {
                                LabeledContent("Articles", value: "\(viewModel.totalCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                LabeledContent("Filter") {
                                    Picker("Filter", selection: $filterMode) {
                                        ForEach(FilterMode.allCases, id: \.self) { mode in
                                            Text(mode.rawValue)
                                                .tag(mode)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reading queue")
                                    Text(filterSummaryText)
                                        .textCase(nil)
                                }
                            }

                            Section {
                                ForEach(viewModel.articles, id: \.id) { article in
                                    NavigationLink(value: article.id) {
                                        StandaloneArticleRow(article: article)
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            handleLeadingSwipe(for: article)
                                        } label: {
                                            swipeActionLabel(for: article)
                                        }
                                        .tint(swipeTint(for: article))
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(feedTitle ?? "Articles")
            .navigationDestination(for: String.self) { articleId in
                ArticleDetailView(articleId: articleId)
            }
            .searchable(text: $searchText, prompt: "Search articles")
            .task(id: reloadKey) {
                await viewModel.reload(
                    container: modelContext.container,
                    feedId: feedId,
                    filterMode: filterMode,
                    searchText: searchText
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: ArticleChangeBus.feedPageMightChange)) { _ in
                viewModel.scheduleDebouncedReload(
                    container: modelContext.container,
                    feedId: feedId,
                    filterMode: filterMode,
                    searchText: searchText
                )
            }
        }
    }

    private var reloadKey: ArticleListReloadKey {
        ArticleListReloadKey(
            feedId: feedId,
            filterMode: filterMode,
            searchText: searchText
        )
    }

    // Keep existing helper methods: filterSummaryText, handleLeadingSwipe,
    // syncStandaloneState, swipeActionLabel, swipeActionTitle,
    // swipeActionSystemImage, swipeTint — unchanged from current implementation.
}
```

- [ ] **Step 2: Add the ViewModel and reload key**

```swift
private struct ArticleListReloadKey: Equatable {
    let feedId: String?
    let filterMode: ArticleListView.FilterMode
    let searchText: String
}

@Observable
@MainActor
private final class ArticleListViewModel {
    private var articleRepo: LocalArticleRepository?
    private var requestToken = 0
    private var reloadTask: Task<Void, Never>?

    var articles: [Article] = []
    var totalCount = 0
    var isLoading = false

    func reload(
        container: ModelContainer,
        feedId: String?,
        filterMode: ArticleListView.FilterMode,
        searchText: String
    ) async {
        let repo = repository(for: container)
        requestToken += 1
        let token = requestToken
        isLoading = true

        let filter = makeFilter(feedId: feedId, filterMode: filterMode, searchText: searchText)

        async let pageTask = repo.listFeedPage(
            filter: filter,
            sort: .newest,
            cursor: nil,
            limit: 100
        )
        async let countTask = repo.countFeed(filter: filter)

        let loadedArticles = await pageTask
        let loadedCount = await countTask

        guard token == requestToken else { return }

        articles = loadedArticles
        totalCount = loadedCount
        isLoading = false
    }

    func scheduleDebouncedReload(
        container: ModelContainer,
        feedId: String?,
        filterMode: ArticleListView.FilterMode,
        searchText: String
    ) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.reload(
                container: container,
                feedId: feedId,
                filterMode: filterMode,
                searchText: searchText
            )
        }
    }

    private func repository(for container: ModelContainer) -> LocalArticleRepository {
        if let articleRepo { return articleRepo }
        let repo = LocalArticleRepository(modelContainer: container)
        self.articleRepo = repo
        return repo
    }

    private func makeFilter(
        feedId: String?,
        filterMode: ArticleListView.FilterMode,
        searchText: String
    ) -> ArticleFilter {
        var filter = ArticleFilter()
        filter.storageScope = .active
        filter.presentationFilter = .readyOnly
        filter.feedId = feedId
        filter.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch filterMode {
        case .all:
            break
        case .unread:
            filter.readFilter = .unread
        case .read:
            filter.readFilter = .read
        case .scored:
            filter.minScore = 1
        case .learning:
            filter.maxScore = 0
        }

        return filter
    }
}
```

Note: The filter mapping needs verification against how `listFeedPage` handles these filters. The `.scored` and `.learning` modes may need adjustment based on how score values are stored. Check `ArticleRepository.listFeedPage()` to confirm the predicate behavior matches.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add NebularNews/NebularNews/Features/Articles/ArticleListView.swift
git commit -m "Replace ArticleListView @Query full-table scan with ViewModel + paginated repository fetch"
```

---

### Task 7: Add iteration cap to `feedReputation()` and optimize `allSyncedArticleStates` calls

**Files:**
- Modify: `NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift:367-381`

**Why:** `feedReputation(feedKey:)` loads ALL `SyncedArticleState` records, then filters to one feed key. Called per-article during scoring. With many articles scored in sequence, this is N full-table scans of synced states.

- [ ] **Step 1: Add predicated fetch for single-feed reputation**

```swift
public func feedReputation(feedKey: String?) async -> FeedReputation {
    guard let feedKey, !feedKey.isEmpty else {
        return computeFeedReputation(feedbackCount: 0, weightedFeedbackCount: 0, ratingSum: 0)
    }

    let descriptor = FetchDescriptor<SyncedArticleState>(
        predicate: #Predicate<SyncedArticleState> { $0.feedKey == feedKey }
    )
    let states = (try? modelContext.fetch(descriptor)) ?? []

    var accumulator = FeedReputationAccumulator()
    for state in states {
        accumulator.add(
            reactionValue: state.reactionValue,
            serializedReasonCodes: state.reactionReasonCodes,
            feedbackAt: state.reactionUpdatedAt ?? state.updatedAt
        )
    }
    return accumulator.reputation
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add NebularNewsKit/Sources/NebularNewsKit/Repositories/ArticleRepository.swift
git commit -m "Optimize feedReputation() to fetch only matching feed states instead of full table"
```

---

### Task 8: Run full test suite to verify no regressions

**Files:** None — verification only.

- [ ] **Step 1: Run NebularNewsKit tests**

Run: `cd /Users/tfinklea/git/nebularnews-ios/NebularNewsKit && swift test 2>&1 | tail -20`

- [ ] **Step 2: Build the app target**

Run: `xcodebuild build -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -10`

- [ ] **Step 3: If any failures, fix and re-verify before moving on**

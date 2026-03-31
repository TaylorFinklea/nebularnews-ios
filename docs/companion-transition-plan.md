# NebularNews iOS: Companion Transition Plan

**Goal**: Transform the iOS app from a standalone feed reader into a companion client for the NebularNews website, following the Feedly/Inoreader cloud-first model. Target: TestFlight beta.

**Architecture decision**: Companion-only. Standalone mode will be removed. The server handles all feed polling, AI enrichment, scoring, and personalization. The app is a reader + interaction client with offline caching for saved articles.

**Repos**:
- iOS app: `/Users/tfinklea/git/nebularnews-ios`
- Website/server: `/Users/tfinklea/git/nebularnews`

---

## Phase 1: Reliability Foundation

**Goal**: Make the existing companion mode trustworthy — error handling, pagination, and display all data the server already sends.

**Server changes**: None. All data is already served by existing `/api/mobile/*` endpoints.

### iOS Tasks

1. **Error handling + retry UI** across all companion views
   - Add a reusable error banner component with retry button
   - Apply to: `CompanionDashboardView`, `CompanionArticlesView`, `CompanionArticleDetailView`, `CompanionFeedsView`
   - Currently API failures silently show nothing

2. **Pagination in article list**
   - `CompanionArticlesView` is hardcoded to `offset: 0, limit: 20`
   - Add load-more trigger at bottom of list using `CompanionArticlesPayload.total`

3. **Render already-fetched data in article detail**
   - `CompanionArticleDetailPayload` already contains these fields but they're NOT rendered:
     - `keyPoints` — add bullet list section
     - `tagSuggestions` — add accept/dismiss UI
     - `score.reasonText`, `score.evidenceJson`, `score.confidence` — add disclosure section
     - `feedback` array — add history section
     - `sources` — add source feed attribution
   - Model sections after standalone `ArticleDetailView`

4. **Wire up feature flags**
   - `CompanionSessionPayload.features` is fetched but never checked
   - Gate reactions, tags, dashboard, news brief sections on flags
   - Call `fetchSession()` on app launch and cache flags

5. **Pull-to-refresh consistency**
   - Add loading indicators during refresh
   - Verify `.refreshable` works on all views

### Key Files
- `NebularNews/Features/Companion/CompanionViews.swift`
- `NebularNews/Features/Companion/CompanionModels.swift`
- `NebularNews/Services/MobileAPIClient.swift`

### Testing Checkpoint
- [ ] Scroll past 20 articles, more load automatically
- [ ] Kill network, open app — error banner appears with retry button
- [ ] Open article with key points — they render
- [ ] Open article with tag suggestions — accept/dismiss works
- [ ] Score evidence disclosure expands and shows reason text

---

## Phase 2: Rich Article Experience + Filters

**Goal**: Article browsing rivals the standalone Feed tab. Filters, scores in rows, images, immersive reader.

**Server changes**: None. `GET /api/mobile/articles` already supports `read`, `score`, `reaction`, `sort`, `sinceDays`, `tag`, `q` query params. The iOS client just never sends them.

### iOS Tasks

1. **Filter bar for article list**
   - Model after standalone `FeedFilterBar`: unread/all, score threshold, sort order
   - Wire filter state to query params in `MobileAPIClient.fetchArticles()`
   - Extend `fetchArticles` signature to accept filter parameters

2. **Score display in article rows**
   - Add `ScoreBadge` to companion `ArticleRow`
   - `CompanionArticleListItem` already has `score`, `scoreLabel`, `scoreStatus`

3. **Images in article rows**
   - `CompanionArticleListItem.imageUrl` exists but isn't shown
   - Add `ArticleImageView` to companion rows

4. **Immersive reader for article detail**
   - Rewrite `CompanionArticleDetailView` using the standalone immersive layout:
     - `ImmersiveHeroImage`, `GlassCard`, `ScoreAccentBar`, `RichArticleContentView`
   - `CompanionArticleDetailPayload` has `contentHtml` — feed through `RichArticleContentView`
   - Bottom action tray: Open in Browser, Reading List toggle (prep for Phase 4), Reaction, overflow

5. **Search improvements**
   - Wire search to server-side `q` parameter (already supported)
   - Add recent search history (local, `UserDefaults`)

### Key Files
- `NebularNews/Features/Companion/CompanionViews.swift`
- `NebularNews/Services/MobileAPIClient.swift`
- `NebularNews/SharedViews/` (reuse `ImmersiveHeroImage`, `GlassCard`, `ScoreAccentBar`, `RichArticleContentView`)

### Testing Checkpoint
- [ ] Filter by "unread" + "4+ score" — correct results
- [ ] Sort by oldest — order changes
- [ ] Article rows show score badges and images
- [ ] Article detail has immersive hero, glass cards, key points, score, bottom action tray
- [ ] `RichArticleContentView` renders bold/italic/links in article body
- [ ] Search returns filtered results from server

---

## Phase 3: Feed Management + Manual Refresh

**Goal**: Users can add/delete feeds, import OPML, and trigger a server poll from the app. First phase requiring server changes.

### Server Changes (nebularnews repo)

New mobile API routes — each proxies existing main API logic with `requireMobileAccess` + `app:write` scope:

1. `POST /api/mobile/feeds` — add feed by URL
2. `DELETE /api/mobile/feeds/[id]` — delete feed + exclusive articles
3. `POST /api/mobile/feeds/import` — accept OPML XML body, parse, create feeds
4. `GET /api/mobile/feeds/export` — return OPML XML
5. `POST /api/mobile/pull` — trigger manual feed poll

**Server files to create/modify**:
- `src/routes/api/mobile/feeds/+server.ts` — add POST handler
- `src/routes/api/mobile/feeds/[id]/+server.ts` — new, DELETE handler
- `src/routes/api/mobile/feeds/import/+server.ts` — new
- `src/routes/api/mobile/feeds/export/+server.ts` — new
- `src/routes/api/mobile/pull/+server.ts` — new

### iOS Tasks

1. **Extend `MobileAPIClient`** with: `addFeed(url:)`, `deleteFeed(id:)`, `importOPML(xml:)`, `exportOPML()`, `triggerPull()`

2. **Feed management UI in CompanionFeedsView**
   - Toolbar "+" button → Add Feed sheet (URL input, validate, submit)
   - Swipe-to-delete on feed rows with confirmation
   - OPML import via file picker (`.opml`, `.xml`, `.txt`)
   - OPML export via share sheet
   - Show feed error count / disabled status

3. **Manual refresh**
   - Pull-to-refresh on article list and dashboard calls `triggerPull()` then reloads after brief delay
   - Show "Refreshing feeds..." indicator

### Key Files
- `NebularNews/Services/MobileAPIClient.swift`
- `NebularNews/Features/Companion/CompanionViews.swift`
- `NebularNews/Features/Companion/CompanionModels.swift`

### Testing Checkpoint
- [ ] Add a feed by URL — appears in feed list, articles arrive after poll
- [ ] Delete a feed — disappears from list
- [ ] Import OPML file — feeds added in bulk
- [ ] Export OPML — valid XML contains all feeds
- [ ] Pull-to-refresh triggers server poll, new articles appear

---

## Phase 4: Today Briefing, Reading List, Caching

**Goal**: The killer companion features — curated Today tab, save-for-later reading list, and offline caching so the app loads instantly.

### Server Changes (nebularnews repo)

1. **`GET /api/mobile/today`** — new endpoint
   - Hero article (highest unread score)
   - Up-next list (next 5-10 highest scored unread)
   - Quick stats (unread total, new today, high fit count)
   - News brief (existing `newsBrief` from dashboard, or current edition)
   - Compose from existing dashboard helpers + "top unread by score" query

2. **Reading list support** — D1 schema change
   - Add `saved_at INTEGER` column to `article_read_state` table
   - `POST /api/mobile/articles/[id]/save` — toggle saved state
   - Extend `GET /api/mobile/articles` — add `saved=true` filter parameter
   - Return `savedAt` in article list items and detail payloads

3. **`POST /api/mobile/articles/[id]/dismiss`** — set dismiss timestamp

**Server files to create/modify**:
- `src/routes/api/mobile/today/+server.ts` — new
- `src/routes/api/mobile/articles/[id]/save/+server.ts` — new
- `src/routes/api/mobile/articles/[id]/dismiss/+server.ts` — new
- `src/routes/api/mobile/articles/+server.ts` — add `saved` filter
- D1 migration: add `saved_at` to `article_read_state`
- Update `CompanionArticleListItem` and detail response types to include `savedAt`

### iOS Tasks

1. **CompanionTodayView** (new view)
   - Hero card (top scored unread) with immersive image
   - Up-next compact rows
   - Quick stats bar (unread, new today, high fit)
   - News brief section with bullets + sources
   - Pull-to-refresh

2. **CompanionReadingListView** (new view)
   - Fetches articles with `saved=true` filter
   - Badge count on tab
   - Swipe-to-unsave

3. **Update tab bar** (MainTabView companion section)
   - Change from `[Dashboard, Articles, Chat, More]` to `[Today, Feed, Reading List, More]`
   - Dashboard content merged into Today view

4. **Save/unsave from article detail + row swipe**
   - Add bookmark toggle in article detail action tray
   - Add swipe action on article rows

5. **Offline caching layer** (`CompanionCache`)
   - Actor that stores last-fetched JSON for today, article list, feeds in cache directory
   - Views show cached data immediately, then refresh in background
   - Saved/reading-list articles cache full `contentHtml` for offline reading
   - Background task: prefetch today + recent articles periodically

6. **Background refresh for companion**
   - `BackgroundTaskManager` detects companion mode
   - BGAppRefreshTask: calls `triggerPull()`, fetches today + articles, updates cache
   - Schedules next occurrence on completion

### Key Files
- `NebularNews/Features/Companion/CompanionTodayView.swift` — new
- `NebularNews/Features/Companion/CompanionReadingListView.swift` — new
- `NebularNews/Features/Companion/CompanionCache.swift` — new
- `NebularNews/App/MainTabView.swift` — update companion tabs
- `NebularNews/App/BackgroundTaskManager.swift` — companion branch
- `NebularNews/Services/MobileAPIClient.swift` — new methods
- `NebularNews/Features/Companion/CompanionModels.swift` — today payload, cache models

### Testing Checkpoint
- [ ] Today tab shows hero card with highest-scored unread article
- [ ] News brief bullets render with source attribution
- [ ] Save article from detail view — appears in Reading List tab
- [ ] Reading List badge shows count
- [ ] Kill app, reopen — cached data shows immediately before refresh
- [ ] Background the app 30+ min, reopen — data is fresher than when you left
- [ ] Airplane mode: cached articles and reading list still browsable

---

## Phase 5: Settings, Tags, and Standalone Removal

**Goal**: Full settings, tag management, and rip out standalone mode for a clean codebase.

### Server Changes (nebularnews repo)

1. `GET /api/mobile/settings` — user-facing settings subset (poll interval, summary style, scoring prefs, news brief config)
2. `PATCH /api/mobile/settings` — update settings
3. `GET /api/mobile/tags` — all tags with article counts
4. `POST /api/mobile/tags` — create tag
5. `DELETE /api/mobile/tags/[id]` — delete tag

**Server files**:
- `src/routes/api/mobile/settings/+server.ts` — new
- `src/routes/api/mobile/tags/+server.ts` — new
- `src/routes/api/mobile/tags/[id]/+server.ts` — new

### iOS Tasks

1. **CompanionSettingsView rewrite**
   - Poll interval, summary style, news brief schedule
   - Theme/appearance (stays client-side)
   - Server connection info
   - Disconnect + sign out
   - Read/write via mobile settings endpoints

2. **CompanionTagListView** (new)
   - Tags with article counts
   - Create / delete tags
   - Navigation from More tab

3. **Remove standalone mode**
   - Delete standalone-only code:
     - `FeedPoller`, `FeedFetcher`, `ArticleContentFetcher`, `ArticlePreparationService`
     - `ProcessingQueueSupervisor`, `RefreshCoordinator`
     - `LocalStandalonePersonalizationService`, `PersonalizationMigrationCoordinator`
     - `StandaloneStateSyncService` (CloudKit sync)
     - `OnboardingSeedService`, `FirstBriefingPreparationView`
     - Standalone tab views in `MainTabView`
     - `StandaloneDashboardView`, standalone `ArticleDetailView`, `ArticleListView`, `FeedTabView`
     - All standalone ViewModels (`ArticleListViewModel`, `FeedListViewModel`, etc.)
   - Remove `isCompanionMode` / `isStandaloneMode` branching — companion is the only mode
   - Simplify `AppState` — remove standalone-specific state
   - Simplify onboarding — only companion flow (server URL + OAuth)
   - Remove `AppSettings` standalone fields (poll interval stored locally, AI mode, etc.)
   - Keep `NebularNewsKit` models and extensions that are still used (Article model for caching, `String.strippedHTML`, etc.)
   - Remove CloudKit entitlement and dual-store `ModelContainer` setup

4. **Simplify SwiftData container**
   - Remove CloudKit synced models (`SyncedFeedSubscription`, `SyncedArticleState`, `SyncedPreferences`)
   - Keep a single local store for caching if needed, or switch to file-based cache entirely

### Key Files
- Nearly every file in the project — this is a major cleanup
- Focus areas: `App/`, `Features/Companion/`, `Services/`, `NebularNewsKit/`

### Testing Checkpoint
- [ ] App builds and runs with standalone code removed
- [ ] All tests pass (remove standalone-specific tests, update remaining)
- [ ] Onboarding goes straight to server URL + OAuth
- [ ] Settings load from server and updates persist
- [ ] Tags can be created, assigned, deleted
- [ ] No references to standalone mode remain in UI
- [ ] Clean build — no unused import warnings

---

## Phase 6: Chat, Discover, and TestFlight Polish

**Goal**: Fill remaining feature gaps and polish for TestFlight beta distribution.

### Server Changes (nebularnews repo)

1. `GET /api/mobile/chat/threads` — list threads
2. `POST /api/mobile/chat/threads` — create thread
3. `POST /api/mobile/chat/threads/[id]/messages` — send message, get AI response

### iOS Tasks

1. **CompanionChatView** — replace placeholder
   - Thread list, thread detail with message bubbles
   - Compose bar, send message, display AI response
   - Article-scoped threads (from article detail overflow menu)

2. **CompanionDiscoverView** — topic/tag browsing
   - Tag grid using server tags endpoint
   - Tap tag → filtered article list
   - SF Symbol mapping for tag icons (reuse existing `DiscoverTypes` mapping)

3. **Visual polish pass**
   - Apply `NebularScreen`, `GlassCard`, `NebularBackdrop` consistently across all companion views
   - Ensure dark/light mode works everywhere
   - Loading skeletons instead of spinners where appropriate

4. **TestFlight prep**
   - App icon, launch screen
   - Onboarding copy and flow polish
   - Crash reporting / analytics (optional)
   - Privacy manifest (network usage, no tracking)
   - Handle edge cases: expired tokens, server unreachable on launch, empty states

### Testing Checkpoint
- [ ] Create chat thread, send message, get AI response
- [ ] Browse topics in Discover, filter articles by tag
- [ ] All screens use themed Nebular visual treatment
- [ ] Dark mode looks correct everywhere
- [ ] Full end-to-end: onboard → browse today → read article → react → save → manage feeds → adjust settings → chat
- [ ] Token expiry: app gracefully re-authenticates
- [ ] Server down: app shows cached data + clear error state
- [ ] Ready for TestFlight submission

---

## Phase Summary

| Phase | Server Changes | iOS Scope | Standalone Code | Target |
|-------|---------------|-----------|-----------------|--------|
| 1 | None | Error handling, pagination, render hidden data | Untouched | Reliable companion |
| 2 | None | Filters, immersive reader, images | Untouched | Rich reading experience |
| 3 | 5 new routes | Feed CRUD, OPML, manual poll | Untouched | Feed management |
| 4 | 3 new routes + migration | Today, reading list, caching, BG refresh | Untouched | Killer features |
| 5 | 5 new routes | Settings, tags, **remove standalone** | **Deleted** | Clean codebase |
| 6 | 3 new routes | Chat, discover, polish | Gone | TestFlight beta |

Phases 1-2 require zero server changes and should be done first. Phases 3-6 each need server routes deployed before the iOS client can use them. Each phase is independently deployable and testable.

# Roadmap

> Durable goals and milestones. Updated when scope changes, not every session.
> This is the **unified roadmap** for both repos. The API repo references this file.

## Vision

NebularNews — iOS-first RSS reader with AI enrichment, powered by Supabase.

## Repos

- **iOS**: `/Users/tfinklea/git/nebularnews-ios` — SwiftUI + Supabase Swift SDK
- **Backend**: `/Users/tfinklea/git/nebularnews-api` — Edge Functions + PostgREST + RLS

---

## Phases

> Phases are sequenced product work for capable models (Opus, Sonnet-class).
> Each phase should be completed before moving to the next.

### M1: Core Reading Experience (complete)
- [x] Supabase backend with RLS and 10 Edge Functions
- [x] Apple Sign In via Supabase Auth
- [x] Feed management (add/remove/pause, OPML import/export)
- [x] AI enrichment on-demand (summarize, key points, chat, brief)
- [x] Algorithmic scoring (4 signals, per-user, reaction feedback)
- [x] Offline support with SyncManager
- [x] Push notifications
- [x] TestFlight shipping (Build 4)

### M2: Article Reading Experience (complete)
- [x] Richer typography (serif body text, dynamic type, 6pt line spacing)
- [x] Inline images with lazy loading and caching (CachedAsyncImage + shared RemoteImageCache)
- [x] Improved article layout (title upgraded to .title, byline: feed · author · date + reading time)
- [x] Reading progress indicator (scroll-tracking progress bar + "N min read" in byline)
- [x] Reader mode toggle (toolbar button: doc.plaintext ↔ doc.richtext)

### M3: AI Improvements (complete)
- [x] Hybrid scoring: AI Score button in toolbar, shows "AI" vs "Auto" badge, separate from summarize
- [x] Chat UI/UX overhaul: animated typing indicator, AI avatar, markdown rendering, model attribution, polished input bar
- [x] Chat quality: expert analyst prompt, key points + tags in context, markdown citations, model attribution
- [x] Suggested questions: tappable in chat empty state, generated via enrich-article suggest_questions job
- [x] Multi-article context: "Today's News" chat on dashboard, multi-chat Edge Function with top 5 article context
- [x] Per-user AI rate limiting: checkRateLimit in usage.ts, 50K daily token limit on server keys, BYOK unlimited

### M4: Search & Discovery (complete)
- [x] Search UI: always-visible search bar with tsvector full-text search, result count in nav title
- [x] Search results: ContentUnavailableView.search empty state, relevance ranking via tsvector weights
- [x] Feed discovery: "Discover Feeds" view with curated catalog, one-tap subscribe, filters already-subscribed
- [x] Popular feeds: curated catalog organized by category (tech, AI, science, news, dev)
- [x] Category/topic browsing: sectioned list with category icons and descriptions

### M5: macOS App (complete)
- [x] Add macOS destination (SDKROOT=auto, SUPPORTED_PLATFORMS includes macosx, macOS 15.0+)
- [x] Sidebar navigation (NavigationSplitView with Today/Articles/Discover/Lists — was already coded)
- [x] Window management (defaultSize 1100x700, proper NavigationSplitView layout)
- [x] Platform compatibility (toolbar placements, list styles, UIScreen guards, glassEffect availability)
- [x] Builds clean on both iOS and macOS (signing requires Apple Developer portal config for push/Sign in with Apple)

### M6: AI Overhaul (complete)
- [x] Three-tier AI: on-device (FoundationModels) / BYOK (server-proxied) / subscription (StoreKit 2 IAP)
- [x] Streaming chat: SSE from Workers + URLSession.bytes on iOS, incremental rendering
- [x] MCP Server: 8 tools, 4 resources, Streamable HTTP at POST /mcp for Claude Desktop integration
- [x] Metering & rate limiting: ai_usage tracking, daily/weekly budgets, subscription_tiers table
- [x] Retry & reliability: exponential backoff with jitter on all AI calls
- [x] On-device pipeline: ArticleGenerationEngine extended with chat + brief for all 3 engines
- [x] Conversation memory: chat_context_summaries, last 3 summaries in system prompt
- [x] Follow-up suggestions: >> prefixed questions parsed into tappable pills
- [x] Brief 2.0: per-topic, configurable depth (headlines/summary/deep), scheduled push briefs
- [x] Batch enrichment: POST /enrich/batch with SSE results for BYOK users
- [x] Topic clustering + trend detection: daily cron, topic_clusters and topic_trends tables
- [x] AI-generated reading insights: weekly summary with AI narrative
- [x] Scoring v2: 6 signals (added save_rate, dismiss_rate behavioral signals)
- [x] Usage dashboard: token usage progress bars in iOS Settings
- [x] Floating AI assistant: context-aware sparkle FAB on every page, bottom sheet, page-context segments
- [x] Assistant history: viewable in sheet and Settings
- [x] Auto-enrichment: subscribers get articles auto-summarized on feed poll
- [x] Scheduled brief push notifications: morning/evening cron with APNS

### M7: Inbox Unification (code complete)
- [x] Email newsletter backend: CF Email Worker handler, MIME parsing (postal-mime), auto-create newsletter feeds per sender
- [x] Newsletter management API: GET/POST /newsletters/address, regenerate token
- [x] Web clipper endpoint: POST /articles/clip — scrapes URL, creates article in per-user "Web Clips" feed
- [x] Poll exclusion: email_newsletter and web_clip feeds skipped by feed poll cron
- [x] iOS newsletter UI: forwarding address in Settings with copy/regenerate
- [x] Feed type icons: envelope for newsletters, link for clips in feed list
- [x] Share Extension source: ShareViewController.swift + Info.plist ready
- [x] Share Extension Xcode target: NebularNewsShareExtension wired into xcodeproj, shared Keychain access group, builds with main app
- [ ] **CF Email Routing** *(manual)*: configure `read.nebularnews.com` in CF Dashboard, catch-all rule → nebular-news worker
- [ ] **End-to-end test** *(manual)*: forward a newsletter → appears in app; clip from Safari → appears in app
- [ ] **M7 acceptance** *(manual)*: both newsletter and clipper work on-device via TestFlight

### M8: Reader Depth (in progress)
- [ ] D1 migration: collections, collection_articles, article_highlights, article_annotations tables
- [ ] Collections API: CRUD routes for collections + article membership
- [ ] iOS Library tab: replace Lists with Library (Saved + Collections sections)
- [ ] Collection views: create, detail, add-to-collection sheet
- [ ] Highlights API: CRUD routes for text highlights with block position
- [ ] Highlight rendering: yellow background overlays on matching text in RichArticleContentView
- [ ] Highlight creation: toolbar action after text selection in article detail
- [ ] Annotations API: single per-article note (GET/PUT/DELETE)
- [ ] Annotation editor: TextEditor section in article detail view
- [ ] Markdown export: client-side MarkdownExporter with ShareLink
- [ ] **M8 acceptance**: can create a collection, add articles, highlight text, export as Markdown

### M9: Platform Polish
- [ ] iPad layout: proper split view, not just scaled iPhone
- [ ] Lock Screen widgets: unread count, latest brief bullet
- [ ] Live Activities: feed poll progress, brief generation
- [ ] Apple Watch glance: unread count + latest brief
- [ ] **M9 acceptance**: iPad looks native, widget shows on Lock Screen, Watch shows data

## Priority Order

M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9.

---

## Backlog

<!-- tier3_owner: claude -->

> Items that run **alongside phases**, not blocked by them.
> Tagged by tier so the right model handles each item.
>
> **`[minor]`** — Sonnet / GPT-5.4 / Gemini 3.1 Pro. May span a few files, requires some codebase understanding.
> **`[trivial]`** — Haiku / OSS models / Mini / Flash. Single-commit, clear instructions, minimal context needed.

### iOS — Code Quality

- [x] `[minor]` **Remove MobileAPIClient**: Done — deleted `Services/MobileAPIClient.swift`, removed legacy companion startup fallback, removed `mobileAPI` and companion session state from `AppState`, and kept APNs upload on the existing Supabase path in `NotificationManager`.
- `[x]` **Numeric booleans → proper Bool**: Done — added `isReadBool` and `disabledBool` computed properties to `CompanionArticle`, `CompanionArticleListItem`, and `CompanionFeed`. Replaced 17 `isRead == 1` / `disabled == 1` checks across all views.
- ~`[minor]` **Fix isSaved logic bug**: Fixed — now checks `savedAt != nil` instead of `isRead == 1`. Piped `savedAt` through `CompanionArticle` model.~
- ~`[minor]` **Extract pagination constants**: Done — created `PaginationConfig` enum in `AppConfiguration.swift`, replaced all hardcoded limits in `ArticleListView`, `CompanionArticlesView`, `CompanionFilteredArticleListView`, `DashboardView`.~
- `[x]` **Add accessibility labels**: Done — added `accessibilityLabel()` to interactive buttons (add, settings, toggle read, toggle save, chat, reactions, tag operations) and `accessibilityHidden(true)` to purely decorative icons (checkmarks, offline indicator, placeholders) across 7 files.
- `[x]` **Widget Extension wiring**: Done — added `NebularNewsWidgets` target to Xcode project with all source files, build configurations, and App Group entitlement. Widget extension now compiles as part of the main app.
- `[x]` **Split SupabaseManager (1792 lines)**: Done — extracted `ArticleService`, `FeedService`, `EnrichmentService`, and `AuthService` into dedicated service files; `SupabaseManager` now delegates to those domains while preserving its existing API.
- `[x]` **Extract CompanionArticleDetailView sub-views (692 lines)**: Done — extracted `ArticleBodyView`, `EnrichmentSection`, `TagsSection`, and `ReactionsView` inside `CompanionArticleDetailView.swift` so the parent view now composes those sections instead of inlining them.
- [x] `[trivial]` **Fix marketing version**: Done — set all `MARKETING_VERSION` build settings to `2.0.0` in `NebularNews.xcodeproj/project.pbxproj`.
- [x] `[trivial]` **Fix force unwrap in RichArticleContentView**: Done — replaced `tag.last!` with `tag.last.flatMap { Int(String($0)) } ?? 2` in `SharedViews/RichArticleContentView.swift`.
- [x] `[trivial]` **Fix force unwrap on Supabase URL**: Done — replaced `URL(string: "...")!` with a guarded local `URL` plus `preconditionFailure("Invalid Supabase URL")` in `Services/SupabaseManager.swift`.
- [x] `[trivial]` **Resolve TODO in ArticleFallbackImageService**: Done — replaced the open TODO with a settled note that the curated Unsplash preset catalog remains intentional until a separate live-search integration is designed. File: `Services/ArticleFallbackImageService.swift`.
- [x] `[trivial]` **Add error logging for silent background operations**: Done — replaced the silent background `try?` calls in `SupabaseManager.swift` and `CompanionFeedsView.swift` with `do/catch` plus `Logger` error reporting.
- ~`[trivial]` **Remove CloudKit references from docs**: Done — removed from `.cursorrules`, `AGENTS.md`, `.github/copilot-instructions.md`.~
- ~`[trivial]` **Fix force unwraps in FeedListView**: Done — replaced with `flatMap`/nil-coalescing.~
- ~`[trivial]` **Extract magic numbers**: Done — created `DesignTokens` enum in `App/DesignTokens.swift`, replaced hardcoded dimensions in `ArticleCard`, `ArticleDetailView`, `CompanionArticleDetailView`, `OnboardingView`.~
- ~`[trivial]` **Name Task.sleep constants**: Done — `searchDebounceInterval`, `feedPullWaitDuration`.~
- ~`[trivial]` **Remove stale MobileAPIClient encoding note**: Done — removed from `AGENTS.md`, `.cursorrules`, `.github/copilot-instructions.md`.~

### API — Code Quality

- ~`[minor]` **Extract resolveAIKey to shared**: Done — created `_shared/ai-key-resolver.ts`, imported in all three functions.~
- ~`[minor]` **Centralize env var handling**: Done — created `_shared/env-config.ts` with `requiredEnv`/`optionalEnv`, migrated `supabase.ts`, `ai-key-resolver.ts`, `scraper.ts`, `process-jobs`, `send-notification`.~
- ~`[minor]` **Add fetch timeouts**: Done — created `_shared/fetch-with-timeout.ts` with `AbortController` + env-configurable timeouts, applied to `ai.ts`, `scraper.ts`, `process-jobs`.~
- ~`[minor]` **Centralize AI model names**: Done — created `_shared/model-config.ts` with `DEFAULT_MODELS` map, migrated `ai.ts` and `ai-key-resolver.ts`. Models updated to `claude-sonnet-4-6` and `gpt-5.4-mini`.~
- `[x]` **CI/CD pipeline**: Done — added `.github/workflows/deploy-edge-functions.yml` in `nebularnews-api` to deploy Edge Functions on pushes to `main` with `npx supabase@latest functions deploy --project-ref ... --use-api --no-verify-jwt` using `SUPABASE_ACCESS_TOKEN`.
- `[x]` **Monitoring**: Done — added `00009_monitoring_views.sql` in `nebularnews-api` with dashboard views for edge-function failures, scoring quality, scraping success, and aggregate health checks for stale polling, backlog growth, score freshness, and scrape success rate.
- `[x]` `[minor]` **Docker self-hosting**: Done — `supabase start` works. Fixed two migration gaps: (1) `00005_per_feed_controls.sql` used `CREATE POLICY IF NOT EXISTS` which requires PostgreSQL 15+; changed to `DROP POLICY IF EXISTS` before `CREATE POLICY`. (2) `00006_push_notification_support.sql` needed `pg_cron` extension enabled; added `CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA cron`.
- ~`[trivial]` **Extract recordUsage to shared**: Done — created `_shared/usage.ts`, imported in both functions.~
- ~`[trivial]` **Update README**: Done — added all 3 missing functions, fixed process-jobs trigger.~
- ~`[trivial]` **Update .env.example**: Done — added both scraper keys with comments.~
- [x] `[minor]` **Extract score-articles logic (455 lines)**: Done — added `loadUserWeights`, `scoreArticleForUser`, `scoreArticlesForUser`, and `WeightedScoreResult` to `_shared/scoring.ts`. `score-articles/index.ts` slimmed from 455 → 115 lines and now only orchestrates rescore + per-user loop. `deno check` and `deno lint` pass.
- [x] `[minor]` **Extract enrich-article job handlers (430 lines)**: Done — `enrich-article/index.ts` slimmed from 496 → 99 lines. Each job handler moved to its own file under `enrich-article/handlers/` (`summarize.ts`, `key-points.ts`, `score.ts`, `auto-tag.ts`, `suggest-questions.ts`), shared article-fetch + normalizers extracted to `enrich-article/shared.ts` (`fetchArticleForEnrichment`, `fetchArticleWithContent`, `truncateContent`, `normalizeParagraphSummary`, `normalizeKeyPoints`, `normalizeTagName`, `normalizeTagConfidence`, `AICredentials` type). Dispatcher reduced to argument validation + switch. `deno check` and `deno lint` pass.
- `[x]` **Type feed-parser properly (355 lines)**: Done — created `RssItem`, `AtomEntry`, `RssChannel`, `AtomFeed`, `ParsedXml` interfaces, removed all 4 `deno-lint-ignore no-explicit-any` suppressions.
- `[x]` **Standardize logging**: Done — `_shared/logger.ts` adopted across all functions: `scraper.ts`, `process-jobs`, `send-notification`, `generate-news-brief`, `enrich-article`, `article-chat`, `poll-feeds`, `score-articles`, `scrape-article`, `export-opml`, `import-opml`.
- `[x]` **Fix `any` casts in scrape-article**: Done — created `ArticleSourceWithFeed` interface, replaced `(source as any)?.feeds` cast with properly typed JOIN result.
- `[x]` **Add error handling to poll-feeds upserts**: Done — added error handling for `article_sources` upsert, `article_sources` insert, and `jobs` insert. All failures are logged and processing continues.
- ~`[trivial]` **Extract batch size constants**: Done — created `_shared/constants.ts`, imported in all three functions.~

---

## Constraints

- iOS 17+ (SwiftUI + SwiftData)
- $0/mo target (Supabase free tier)
- AI enrichment is on-demand only (cost control)
- BYOK for user API keys

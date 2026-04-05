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

### M2: Article Reading Experience (not started)
- [ ] Richer typography (system fonts, dynamic type, proper line spacing)
- [ ] Inline images with lazy loading and caching
- [ ] Reading progress indicator (scroll position, estimated time)
- [ ] Improved article layout (header, byline, publication date, source attribution)
- [ ] Reader mode toggle (stripped vs. original formatting)

### M3: AI Improvements (not started)
- [ ] Hybrid scoring: layer AI scoring on top of the 4-signal algorithm (user-triggered per article)
- [ ] Chat UI/UX overhaul: streaming responses, better message rendering, conversation history
- [ ] Chat quality: better prompts, more article context in the window, source citations
- [ ] Suggested questions: auto-generate 2-3 starter questions per article
- [ ] Multi-article context: "ask about today's news" across multiple articles
- [ ] Per-user AI rate limiting: enforce quotas on global API keys via ai_usage table

### M4: Search & Discovery (not started)
- [ ] Search UI: prominent search bar using the existing tsvector full-text index
- [ ] Search results with highlighting and relevance ranking
- [ ] Feed discovery: suggest feeds based on user interests and reading patterns
- [ ] Popular feeds: show what other users are subscribed to
- [ ] Category/topic browsing

### M5: macOS App (not started)
- [ ] Add macOS destination to Xcode target (code ready with #if os guards)
- [ ] Sidebar navigation (feeds, saved, search, settings)
- [ ] Window management (main window, article popout)
- [ ] Keyboard shortcuts for power users
- [ ] Toolbar and menu bar integration

## Priority Order

M2 → M3 → M4 → M5. Reading experience first (core loop), then AI differentiation, then findability, then platform expansion.

---

## Backlog

<!-- tier3_owner: claude -->

> Items that run **alongside phases**, not blocked by them.
> Tagged by tier so the right model handles each item.
>
> **`[minor]`** — Sonnet / GPT-5.4 / Gemini 3.1 Pro. May span a few files, requires some codebase understanding.
> **`[trivial]`** — Haiku / OSS models / Mini / Flash. Single-commit, clear instructions, minimal context needed.

### iOS — Code Quality

- `[minor]` **Remove MobileAPIClient**: Delete `Services/MobileAPIClient.swift`, migrate push token upload in `NotificationManager` to SupabaseManager, remove `mobileAPI` from `AppState.swift:26-29`. The client is a leftover from the SvelteKit transition.
- `[minor]` **Numeric booleans → proper Bool**: `isRead == 1`, `disabled == 1` appear in 20+ view files. Add computed Bool properties on the model or normalize at decode time. Files: `ArticleListView`, `ArticleDetailView`, `FeedListView`, all Companion views.
- ~`[minor]` **Fix isSaved logic bug**: Fixed — now checks `savedAt != nil` instead of `isRead == 1`. Piped `savedAt` through `CompanionArticle` model.~
- ~`[minor]` **Extract pagination constants**: Done — created `PaginationConfig` enum in `AppConfiguration.swift`, replaced all hardcoded limits in `ArticleListView`, `CompanionArticlesView`, `CompanionFilteredArticleListView`, `DashboardView`.~
- `[minor]` **Add accessibility labels**: Icons in `FeedListView`, score badges, and action buttons lack VoiceOver labels. Audit all SF Symbol images for `.accessibilityLabel()`.
- `[minor]` **Widget Extension wiring**: Add Widget Extension target in Xcode, wire up existing files from `NebularNewsWidgets/`, set up App Groups (`group.com.nebularnews.shared`). Code is already written — this is Xcode project configuration.
- `[minor]` **Split SupabaseManager (1792 lines)**: Extract domain services — `ArticleService`, `FeedService`, `EnrichmentService`, `AuthService`. Currently a monolith with 50+ methods. File: `Services/SupabaseManager.swift`.
- `[minor]` **Extract CompanionArticleDetailView sub-views (692 lines)**: Break into `ArticleBodyView`, `EnrichmentSection`, `TagsSection`, `ReactionsView`. File: `Features/Companion/CompanionArticleDetailView.swift`.
- `[trivial]` **Fix marketing version**: Set clean `2.0.0` in Xcode project settings to replace `$(MARKETING_VERSION)` literal.
- [x] `[trivial]` **Fix force unwrap in RichArticleContentView**: Done — replaced `tag.last!` with `tag.last.flatMap { Int(String($0)) } ?? 2` in `SharedViews/RichArticleContentView.swift`.
- [x] `[trivial]` **Fix force unwrap on Supabase URL**: Done — replaced `URL(string: "...")!` with a guarded local `URL` plus `preconditionFailure("Invalid Supabase URL")` in `Services/SupabaseManager.swift`.
- `[trivial]` **Resolve TODO in ArticleFallbackImageService**: TODO at line 11 about replacing curated catalog with Unsplash search. Either implement or convert to backlog item with decision. File: `Services/ArticleFallbackImageService.swift:11`.
- `[trivial]` **Add error logging for silent background operations**: `try?` on detached tasks at `SupabaseManager.swift:298` (rescore), `CompanionFeedsView.swift:97` (feed pause). Replace `try?` with `do/catch` that logs the error.
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
- `[minor]` **CI/CD pipeline**: Set up GitHub Actions for Edge Function deployment on push to main. Run `npx supabase functions deploy --no-verify-jwt`.
- `[minor]` **Monitoring**: Track Edge Function errors, scoring quality, scraping success rates. Could be a Supabase dashboard + pg_cron health checks.
- `[minor]` **Docker self-hosting**: Test end-to-end with `supabase start`, document any gaps.
- ~`[trivial]` **Extract recordUsage to shared**: Done — created `_shared/usage.ts`, imported in both functions.~
- ~`[trivial]` **Update README**: Done — added all 3 missing functions, fixed process-jobs trigger.~
- ~`[trivial]` **Update .env.example**: Done — added both scraper keys with comments.~
- `[minor]` **Extract score-articles logic (455 lines)**: Main handler is a single 400+ line function. Extract `computeSignalWeights`, `scoreArticleForUser`, and per-user scoring loop into `_shared/scoring.ts`. File: `score-articles/index.ts`.
- `[minor]` **Extract enrich-article job handlers (430 lines)**: Summarize, key_points, score, auto_tag share a pattern. Extract each into a handler module and DRY the AI invocation. File: `enrich-article/index.ts`.
- `[minor]` **Type feed-parser properly (355 lines)**: 6 `deno-lint-ignore no-explicit-any` suppressions. Create concrete `ParsedFeed`/`ParsedItem` interfaces instead of generic objects. File: `_shared/feed-parser.ts`.
- `[trivial]` **Standardize logging**: `_shared/logger.ts` created with `log`/`logError` helpers, but **not yet adopted** — 20+ `console.log`/`console.error` calls across all functions still use raw logging. Needs a follow-up pass to import and use the logger.
- `[trivial]` **Fix `any` casts in scrape-article**: `(source as any)?.feeds` at line 61. Create proper type for `article_sources` JOIN result. File: `scrape-article/index.ts:61`.
- `[trivial]` **Add error handling to poll-feeds upserts**: Lines 110, 159, 212 have upsert/insert without individual error checks. Wrap each with try/catch and per-operation logging. File: `poll-feeds/index.ts`.
- ~`[trivial]` **Extract batch size constants**: Done — created `_shared/constants.ts`, imported in all three functions.~

---

## Constraints

- iOS 17+ (SwiftUI + SwiftData)
- $0/mo target (Supabase free tier)
- AI enrichment is on-demand only (cost control)
- BYOK for user API keys

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

> Items that run **alongside phases**, not blocked by them.
> Tagged by tier so the right model handles each item.
>
> **`[minor]`** — Sonnet / GPT-5.4 / Gemini 3.1 Pro. May span a few files, requires some codebase understanding.
> **`[trivial]`** — Haiku / OSS models / Mini / Flash. Single-commit, clear instructions, minimal context needed.

### iOS — Code Quality

- `[minor]` **Remove MobileAPIClient**: Delete `Services/MobileAPIClient.swift`, migrate push token upload in `NotificationManager` to SupabaseManager, remove `mobileAPI` from `AppState.swift:26-29`. The client is a leftover from the SvelteKit transition.
- `[minor]` **Numeric booleans → proper Bool**: `isRead == 1`, `disabled == 1` appear in 20+ view files. Add computed Bool properties on the model or normalize at decode time. Files: `ArticleListView`, `ArticleDetailView`, `FeedListView`, all Companion views.
- `[minor]` **Fix isSaved logic bug**: `ArticleDetailView.swift:414` sets `isSaved = detail.article.isRead == 1` but should check `savedAt != nil`. Comment confirms the intent doesn't match the code.
- `[minor]` **Extract pagination constants**: `limit: 30`, `limit: 100`, `limit: 10` scattered across `ArticleListView`, `CompanionArticlesView`, `CompanionFilteredArticleListView`, `DashboardView`. Move to `AppConfiguration.PaginationConfig`.
- `[minor]` **Add accessibility labels**: Icons in `FeedListView`, score badges, and action buttons lack VoiceOver labels. Audit all SF Symbol images for `.accessibilityLabel()`.
- `[minor]` **Widget Extension wiring**: Add Widget Extension target in Xcode, wire up existing files from `NebularNewsWidgets/`, set up App Groups (`group.com.nebularnews.shared`). Code is already written — this is Xcode project configuration.
- `[trivial]` **Fix marketing version**: Set clean `2.0.0` in Xcode project settings to replace `$(MARKETING_VERSION)` literal.
- `[trivial]` **Remove CloudKit references from docs**: `.cursorrules:12`, `AGENTS.md:40` reference "Standalone CloudKit sync" — CloudKit was decommissioned. Remove those lines.
- `[trivial]` **Fix force unwraps in FeedListView**: Lines 51 and 172 force-unwrap `feed.title` when a nil-coalescing fallback to `feed.url` is already the intent.
- `[trivial]` **Extract magic numbers**: Hardcoded dimensions across views (`200`, `140`, `240`, `280`, `96`). Create a `DesignTokens` struct with named constants.
- `[trivial]` **Name Task.sleep constants**: `ArticleListView:179` (300ms debounce), `FeedListView:145` (3s feed pull wait). Extract to named constants.
- `[trivial]` **Remove stale MobileAPIClient encoding note**: `AGENTS.md:32-35` and `.cursorrules:10` reference `MobileAPIClient` snake_case encoding — no longer relevant after Supabase migration.

### API — Code Quality

- `[minor]` **Extract resolveAIKey to shared**: Duplicated verbatim in `article-chat/index.ts`, `enrich-article/index.ts`, `generate-news-brief/index.ts`. Move to `_shared/ai-key-resolver.ts`.
- `[minor]` **Centralize env var handling**: Inconsistent patterns (`!`, optional chaining, null checks) across Edge Functions. Create `_shared/env-config.ts` with required/optional semantics.
- `[minor]` **Add fetch timeouts**: `process-jobs`, `_shared/scraper.ts`, `_shared/ai.ts` have no timeout on external HTTP calls. Wrap with `AbortController` + configurable timeout.
- `[minor]` **Centralize AI model names**: `"claude-sonnet-4-20250514"` and `"gpt-4o-mini"` hardcoded in 10+ places. Create `_shared/model-config.ts` with a single `MODEL_MAP`.
- `[minor]` **CI/CD pipeline**: Set up GitHub Actions for Edge Function deployment on push to main. Run `npx supabase functions deploy --no-verify-jwt`.
- `[minor]` **Monitoring**: Track Edge Function errors, scoring quality, scraping success rates. Could be a Supabase dashboard + pg_cron health checks.
- `[minor]` **Docker self-hosting**: Test end-to-end with `supabase start`, document any gaps.
- `[trivial]` **Extract recordUsage to shared**: Duplicated in `enrich-article/index.ts` and `article-chat/index.ts`. Move to `_shared/usage.ts`.
- `[trivial]` **Update README**: Edge Functions table lists 7 functions but 10 exist. Add `score-articles`, `generate-news-brief`, `scrape-article`.
- `[trivial]` **Update .env.example**: Missing `STEEL_API_KEY` and `BROWSERLESS_API_KEY` entries.
- `[trivial]` **Standardize logging**: Inconsistent log format across functions. Create `_shared/logger.ts` with `[function-name] message` pattern.
- `[trivial]` **Extract batch size constants**: `BATCH_SIZE=10`, `MAX_ARTICLES_PER_RUN=50`, `MAX_FEEDS_PER_RUN=12` hardcoded per-function. Move to `_shared/constants.ts`.

---

## Constraints

- iOS 17+ (SwiftUI + SwiftData)
- $0/mo target (Supabase free tier)
- AI enrichment is on-demand only (cost control)
- BYOK for user API keys

# Current State (2026-04-26)

## Design-wait session — Shipped

Site-wide design mockups (consumer reader + admin) are in flight. Used the wait to push on plumbing, iOS, reliability, and observability — none design-blocked. Eight commits on backend, two on web, one on iOS, plus a one-time prod data backfill.

### Chunks 1-6 (design-wait mix)

- **Chunk 1** — `GET /admin/articles/:id` endpoint + web rewrite. Article detail page no longer "metadata not in recent list" for old articles. Commits `b78855e` + `4a65c6b`.
- **Chunk 2** — Scraper guards. New `sniffContentType()` short-circuits PDFs/JSON; linkedom/Readability errors land structured (`unsupported_content_type` / `parse_failed` / `no_readable_content`). Quarantines on permanent failure. Commit `27b774f`.
- **Chunk 3** — iOS scroll restoration on reopen (M16 Tier 2 finally complete). `ScrollViewReader` + section anchors (body/tags/annotation) selected by saved percent. Race-condition mitigation via `isRestoring` flag. Commits `7d49c7f` + `7f5360e`.
- **Chunk 4** — Quality-based provider escalation. Recovery requires `wordCount >= 50 AND extraction_quality >= 0.25`; low-quality results flip Steel↔Browserless next attempt. Commit `40aa173`.
- **Chunk 5** — Vitest scaffold. 13 unit tests (sniffContentType, escalatedProvider, backoffMs). Commit `f03661e`.
- **Chunk 6** — Admin audit log. Migration 0016 + middleware on POST/PATCH/DELETE via `c.executionCtx.waitUntil`, `GET /admin/audit` endpoint. Web UI deferred. Commit `838b8b5`.

### Quarantine + retroactive backfill

- Migration 0017: `articles.quarantined_at` column + partial index `idx_articles_active`.
- `scrapeAndPersist` writes `quarantined_at = COALESCE(quarantined_at, ?)` on `QUARANTINE_METHODS`. Retry cron quarantines on `MAX_RETRIES` exhaustion.
- `/articles`, `/today` (3 queries), `/today` resume card all filter `quarantined_at IS NULL` by default.
- Admin: `?include_quarantined=true|only` on list, `POST /admin/articles/:id/unquarantine` endpoint. Web detail page shows warning callout + Unquarantine button.
- One-time backfill quarantined **151 of 1777 articles** (8.5%) with `scrape_retry_count >= 5` and empty content.
- Backend `e3cdd22`, web `4f982a5`.

### Steel + Browserless cost observability

- Migration 0018: `provider_calls` (per-call log) + `provider_usage_daily` (rollups).
- `scraper.ts` instrumentation hook in the for-loop captures duration, success, error_class (timeout/http_4xx/http_5xx/network) per call. Decoupled from provider functions to keep them pure.
- Daily cron at 3:30am UTC re-rolls trailing 7 days into rollup table (idempotent upsert), prunes raw rows older than 30 days.
- `GET /admin/usage?days=30` returns rollup history + today's running totals computed live.
- Backend `51752e4`. Web tile deferred until design lands.

### Repo housekeeping

- `TaylorFinklea/nebularnews` was archived on GitHub (pre-rewrite SvelteKit). Unarchived, force-pushed the Workers backend history; old SvelteKit commits still in early history but main is current.
- Created `TaylorFinklea/nebularnews-web` (was never had a remote). Initially private; user later flipped all three product repos to public.

### Both repos

- `nebularnews`: `51752e4` (HEAD) — pushed
- `nebularnews-web`: `4f982a5` (HEAD) — pushed
- `nebularnews-ios`: `7f5360e` (HEAD) — pushed

### Next: Push Notification Service Extension (in progress as of this update)

Brief push notifications get an image preview + 2-bullet body via a new iOS NSE target. Backend payload enrichment (`mutable-content: 1` + `bullets` + `image_url`) is the first deliverable. User creates the Xcode target manually; I customize the generated stub.

---

# Current State (2026-04-24)

## M17: Content Coverage Overhaul + SvelteKit Admin Web — Shipped

### Phase A — Backend content coverage (Workers)

- **Migration 0015** applied to production D1: added `articles.scrape_retry_count` (INTEGER default 0), `articles.next_scrape_attempt_at` (INTEGER nullable), partial index on those for the retry hot path, and a one-shot bulk `UPDATE feeds SET scrape_mode = 'auto_fetch_on_empty' WHERE scrape_mode = 'rss_only'` (574 rows flipped).
- **New hourly cron** `src/cron/retry-empty-articles.ts`: scans articles with empty/<50-word bodies whose feed permits scraping, calls `scrapeAndPersist()` via Steel → Browserless → Readability, backs off exponentially (15m, 30m, 1h, 2h, 4h) up to 5 attempts, then gives up so permanently-blocked URLs don't burn provider cost.
- **Shared `scrapeAndPersist` helper** in `src/lib/scraper.ts` used by the new cron, admin rescrape route, and ready for future reuse by the existing on-demand fetch-content path.
- **Feed default flipped**: `src/routes/feeds.ts` POST /feeds and OPML import now insert `scrape_mode = 'auto_fetch_on_empty'` explicitly (schema default stays `rss_only` because SQLite can't change column defaults without a table rebuild).
- **New admin endpoints**: `PATCH /admin/feeds/:feedId` (edit scrape_mode, disabled, title), `POST /admin/articles/:id/rescrape` (reset counters + synchronous scrape), `GET /admin/articles` (paginated + filterable), `GET /admin/briefs` (cross-user recent briefs with user_email JOIN), `POST /admin/briefs/generate-for-user` (bypass timezone cron for diagnostics).
- Deployed: version `8e381b70-1f8c-43db-9b2d-fef8db17589c`. Commits `9d7a361` (Phase A) + `5ab581b` (web auth handoff).

### Phase B — SvelteKit admin web

- **New sibling repo** at `/Users/tfinklea/git/nebularnews-web`. SvelteKit 2 + Svelte 5 runes + Tailwind v4 + `@sveltejs/adapter-cloudflare`.
- **Auth model**: Bearer-token, matching iOS. New backend endpoint `GET /api/auth/web-handoff` reads the better-auth session cookie on api.nebularnews.com and redirects to an allowlisted web callback with `?token=<token>`. Web sets its own httpOnly cookie `nn_session` and attaches Bearer on every API call. iOS untouched.
- **All admin pages rendered**: Dashboard, Feeds (list + per-feed edit + rescrape), Articles (filterable list + detail with rescrape), Users (list + detail + grant/revoke admin + trigger brief), AI usage (tokens + tool-call stats), Content moderation (recent articles), Briefs (cross-user list + user filter), Health (pull runs + scraping stats).
- **Deployed** to `https://nebularnews-admin.pages.dev` on Cloudflare Pages project `nebularnews-admin`. Custom domain `admin.nebularnews.com` pending manual DNS + Apple Services ID setup per `APPLE_SETUP.md` in the repo.
- **Dev bypass**: `DEV_BYPASS_ENABLED=true` in `.env` lets you paste a session.token row from D1 straight into the sign-in page. Disabled on production.
- Commit `87aae62` (initial scaffold; full tree).

### Outstanding manual for M17 Phase B
- Apple Services ID (`com.nebularnews.web`) + Return URL + domain verification file.
- APPLE_SERVICES_ID + APPLE_CLIENT_SECRET_WEB secrets in Wrangler.
- Verify better-auth Apple provider can accept multi-audience (App ID + Services ID); may need config adjustment.
- DNS CNAME for `admin.nebularnews.com` → `nebularnews-admin.pages.dev` in CF dashboard.

---

# Current State (2026-04-20)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## Completed Milestones
- **M1-M5**: Core reading, article UX, AI improvements, search & discovery, macOS app
- **M6**: AI Overhaul — three-tier AI, streaming chat, MCP server, floating AI assistant
- **M7**: Inbox Unification — email newsletter backend, web clipper, Share Extension
- **M8**: Reader Depth — collections, highlights, annotations, Markdown export
- **M9**: Deep Fetch + New Source Types
- **M10**: Platform Polish — iPad split view, Lock Screen widgets, Live Activity, Apple Watch glance
- **M11**: AI Assistant Direct Actions — sparkle tool calling (server + client tools, undo chips, native Anthropic streaming)

## M12: Offline Mutation Queue + AI Tool-Call Bug Fixes — Shipped ✅

### Track A — Offline Mutation Queue (iOS)
- `SyncManager` extended to cover feed mutations: action types `feed_settings`, `subscribe_feed`, `unsubscribe_feed` with matching payload structs and queue-aware convenience methods (`updateFeedSettings`, `subscribeFeed`, `unsubscribeFeed`)
- Max retries bumped 5 → 10
- Dead-letter state: actions that exceed maxRetries stay in the table but are filtered from `fetchPendingActions`. New `fetchDeadLetterActions` / `retryDeadLetter` / `discardDeadLetter` helpers for user-driven recovery
- Post-sync widget invalidation via `WidgetCenter.shared.reloadAllTimelines()` (gated for macCatalyst)
- `hasPendingAction(forResource:)` helper used by views to render "Syncing…" indicators
- `CompanionFeedsView`: pause/resume and Feed Settings save sheet route through SyncManager; subtle cloud-slash "Syncing…" label per row
- `CompanionArticleDetailView`: "Changes will sync when online" banner above tags when article has pending mutations
- Backend: `PATCH /feeds/:id/settings` accepts optional `If-Match` header (compact ETag of `paused/max/min`); 412 Precondition Failed on mismatch with `current_etag` in payload. Scaffold for future conflict-resolver UI

### Track B — AI Tool-Call Fixes (sprint-absorbed)
- FK existence guards in `chat-tools.ts`:
  - `mark_articles_read`: filters via `SELECT IN (...)` to valid article ids; reports skipped count
  - `pause_feed` / `set_feed_max_per_day`: verify `user_feed_subscriptions` row exists; include feed title in summaries
- Added `undo_set_feed_max_per_day` (was missing undo coverage); `UNDO_TOOL_NAMES` updated
- `executeServerTool` catch block now persists full error context (name + msg + stack + args + userId) to `debug_log` under scope `tool-error:{toolName}`
- `/admin/tool-call-stats` surfaces two new per-tool metrics: `thrown_errors` (count from debug_log scope) and `logging_gap` (count − succeeded − failed) — exposes under-instrumented tools
- `AdminToolCallStatsView` renders thrown_errors (red) + logging_gap (orange) columns

## Earlier session (2026-04-19/20): Sparkle assistant fixes
- **Route shadowing bug** (long debug trail): `chatRoutes.post('/chat/:articleId', ...)` was matching POST `/chat/assistant` (with `articleId="assistant"`) and inserting `chat_threads.article_id="assistant"` which violated FK to `articles(id)`. Fix: added regex constraint `{(?!assistant$|assistant/|multi$|multi/|undo-tool$).+}` to both GET/POST `/chat/:articleId` patterns so reserved sentinels skip the generic handler. Same shadowing affected GET /chat/assistant, GET /chat/multi, POST /chat/multi, POST /chat/undo-tool — all now properly routed.
- **Streaming with tool support**: added `streamChatWithTools()` in `src/lib/ai.ts` that streams Anthropic SSE with tool_use accumulation (text_delta + tool_use + done events). Wired into POST `/chat/assistant` so users see token-by-token streaming end-to-end. OpenAI falls back to buffered `runChatWithTools` (proper OpenAI tool streaming is a follow-up).

## Deployed Migrations
- 0001 through 0012 applied on production D1
- (Migration 0012 = temporary `debug_log` table; reused for `tool-error:*` scope as production diagnostic per M12 plan)

## Known Issues / Deferred
- M7 manual: CF Email Routing not yet configured for `read.nebularnews.com`
- iOS If-Match conflict resolver UI: backend scaffolding shipped, client capture+send is a follow-up
- OpenAI native tool-call streaming: still uses buffered fallback
- M11 confirm-before-mutate sheet for very destructive actions: undo-chip currently covers most cases

## Both Repos
- `nebularnews-ios`: 28c926b (HEAD)
- `nebularnews`: 63af35a (HEAD)

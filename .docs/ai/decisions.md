# Architecture Decision Records

## ADR-014: Quarantine permanent-failure articles (2026-04-26)

**Status**: Implemented (design-wait session)

**Context**: Chunks 2 and 4 produced two failure modes for articles that could never be successfully scraped: structurally unsupported content (PDFs, JSON-only HN entries) caught by `sniffContentType`, and articles that exhausted their 5-attempt retry budget without ever clearing the quality bar. Both kept reappearing in user feeds with empty content because there was no terminal state.

**Decision**: Add `articles.quarantined_at` (nullable INTEGER unix-ms). `scrapeAndPersist` writes it on `QUARANTINE_METHODS` (currently just `unsupported_content_type`). The retry cron writes it when `scrape_retry_count` reaches `MAX_RETRIES`. User-facing endpoints (`/articles`, `/today`, resume card) filter `quarantined_at IS NULL` by default. Admin can opt back in with `?include_quarantined=true|only` and clear via `POST /admin/articles/:id/unquarantine`.

**Rationale**: Hiding from feeds is the right user-facing default; "delete" would lose the URL+metadata if a feed serves a transient HTML response that triggers our heuristics. Re-scrape implicitly clears the flag — admin doesn't need to remember a separate unquarantine step. A partial index (`idx_articles_active`) keeps the default-case query cheap.

**Consequences**: One-time backfill quarantined 151 of 1777 articles (8.5%) with retry budget exhausted and no content. Admins can correct misclassifications in the web UI. Future PDF-mode-aware scraping (e.g. text extraction) would un-quarantine those articles automatically on rescrape.

## ADR-015: Self-hosted scrape-provider observability (2026-04-26)

**Status**: Implemented (design-wait session)

**Context**: After chunk 4's quality-based provider escalation shipped, the most likely cost driver became the retry cron flipping Steel ↔ Browserless calls when extraction quality is low. Steel and Browserless both bill per-call; their dashboards exist but checking them manually is reactive. We wanted a way to see usage trends without scraping their billing UIs.

**Decision**: Track every provider call internally. `provider_calls` (per-call log, pruned at 30 days) captures provider, started_at, duration_ms, success, error_class. `provider_usage_daily` (long-lived rollups) holds per-provider per-day call/success/error counts plus p50/p95 duration. Daily cron at 3:30am UTC re-rolls the trailing 7 days (idempotent upsert via PRIMARY KEY). `GET /admin/usage` returns rollup history plus today's running totals computed live. Instrumentation lives at the for-loop level in `scrapeAndExtract`, not inside provider helpers — keeps the helpers pure-fetchers.

**Rationale**: Independent ledger we can correlate with provider invoices; finds drift if their billing differs from our call counts. Error class taxonomy (`timeout` / `http_4xx` / `http_5xx` / `network`) lets us distinguish "tune our timeout" from "their incident" from "our request shape is wrong" — three very different responses. Web UI deferred until design lands; the data starts accumulating immediately.

**Consequences**: Each scrape call writes one extra row to D1 (~80 bytes). At current rates that's <100KB/day. The 30-day prune keeps the hot table bounded. The admin endpoint is rate-limited only by the `is_admin` middleware; consumers will still need backend support to render anything.

## ADR-001: Migrate D1 to Supabase Postgres (2026-03-27)

**Status**: Superseded by ADR-005

**Context**: D1 (SQLite) caused repeated production bugs — V17 migration fragility, schema.sql/runtime mismatch, `runSafe()` workarounds, FTS5 rebuild fragility, single-writer limitation.

**Decision**: Swap D1 for Supabase Postgres while keeping SvelteKit on Cloudflare Workers.

**Outcome**: Attempted but CF Workers couldn't connect to Postgres reliably (Hyperdrive CONNECT_TIMEOUT, 190ms/query, driver incompatibilities). Led to ADR-005.

## ADR-002: Apple Sign In via Supabase OAuth PKCE (2026-03-27)

**Status**: Superseded by ADR-004

**Context**: Magic link auth hit email rate limits. Needed alternative login method.

**Decision**: Use Supabase as OAuth identity broker for Apple Sign In. PKCE flow with GET endpoint at `/auth/apple`.

**Outcome**: Worked but was overly complex (SvelteKit broker in the middle). Replaced by direct Supabase Auth in ADR-004.

## ADR-003: Guided Onboarding with Curated Feeds (2026-03-27)

**Status**: Implemented

**Context**: New users saw empty app with no guidance.

**Decision**: Curated feed catalog (16 feeds, 5 categories) served via hardcoded catalog in iOS. Bulk subscribe endpoint triggers auto-pull so articles appear immediately.

## ADR-004: Replace MobileAPIClient with Direct Supabase SDK (2026-03-31)

**Status**: Implemented

**Context**: The iOS app communicated through `MobileAPIClient` to a SvelteKit web app. This added unnecessary middleware.

**Decision**: Replace with `SupabaseManager` using Supabase Swift SDK v2.x. Auth uses `signInWithIdToken` for Apple Sign In. Data reads via PostgREST. AI operations via Edge Functions.

## ADR-005: Full API-First Rewrite on Supabase (2026-03-31)

**Status**: Implemented

**Context**: CF Workers couldn't reliably connect to Postgres (Hyperdrive issues, 190ms/query after optimization). The web app was the wrong product — iOS should be primary. No RLS meant manual user isolation across 40+ endpoints.

**Decision**: Decommission SvelteKit web app entirely. Move to pure Supabase backend (Edge Functions + PostgREST + RLS). Fresh Supabase project with clean schema. iOS talks directly to Supabase. Old infrastructure fully decommissioned.

**Consequences**: $0/mo (Supabase free tier). 29 tables with RLS. 10 Edge Functions. iOS-first product. macOS code ready. Docker self-hosting possible via `supabase start`.

## ADR-006: Widget Data Sharing via App Groups (2026-04-02)

**Status**: Implemented (widget extension target must be added in Xcode)

**Context**: Widgets run in a separate process and cannot call Supabase directly.

**Decision**: Use App Groups (`group.com.nebularnews.shared`) with shared UserDefaults. Main app writes stats and top articles as JSON after every fetch. Deep links route widget taps back to in-app views.

## ADR-007: Algorithmic Scoring Without AI (2026-04-02)

**Status**: Implemented

**Context**: AI scoring costs money per article and was disabled to prevent unbounded costs. Users had no scoring feedback.

**Decision**: 4-signal algorithmic scoring (feed reputation, content freshness, content depth, tag match ratio) runs automatically via pg_cron every 5 minutes. Scores are per-user. Reactions trigger immediate re-scoring for feedback. No AI cost.

**Consequences**: All users start at score 3 until they react. Hybrid AI scoring can be layered on top later.

## ADR-008: Offline Queue with SyncManager (2026-04-03)

**Status**: Implemented

**Context**: App was unusable without network. Mutations (read, save, react, tag) failed silently offline.

**Decision**: `SyncManager` with `NWPathMonitor` detects connectivity. All mutations update SwiftData cache immediately (optimistic UI), attempt network call, and queue as `PendingAction` on failure. Actions replay in FIFO order on reconnect. Max 5 retries before dropping.

**Consequences**: App feels responsive regardless of connectivity. Background refresh also syncs pending actions.

## ADR-009: Per-Feed Browser Scraping (2026-04-02)

**Status**: Implemented

**Context**: Aggregator feeds (Hacker News) provide only titles/links in RSS — no article body. AI summarization fails without content.

**Decision**: Per-feed configurable scraping via `scrape_mode` column on feeds table. Steel (primary) + Browserless (fallback) providers. Readability extraction. Admin configures via iOS feed settings. `fetch_content` jobs processed by pg_cron every minute.

**Consequences**: Requires Steel + Browserless API keys. Only scrape-flagged feeds incur provider costs. Quality tracking via `avg_extraction_quality` on feeds table.

## ADR-010: Standardize Handoff Docs at .docs/ai/ (2026-04-03)

**Status**: Implemented

**Context**: Session handoff workflow was duplicated in each repo's CLAUDE.md/AGENTS.md. The iOS repo used `docs/ai/` while the API repo had no handoff docs. The roadmap was stale (referenced old SvelteKit/D1 architecture).

**Decision**: Move reusable handoff workflow to global `~/CLAUDE.md`. Standardize on `.docs/ai/` as the default directory across all repos. Migrate iOS from `docs/ai/` → `.docs/ai/`. Create `.docs/ai/` in the API repo. Keep starter templates at `~/.claude/templates/handoff/`. Remove Session Workflow sections from repo-level instruction files.

**Consequences**: Each repo has its own `.docs/ai/` tracked by git. Global instructions define the workflow once. Repo CLAUDE.md files only contain project-specific guidance.

## ADR-012: Flip Default Scrape Mode + Retry Loop (2026-04-24)

**Status**: Implemented (M17 Phase A)

**Context**: Many articles showed empty content in iOS because most historical feeds had `scrape_mode = 'rss_only'` (the legacy default). Feeds whose RSS items carried link-only or excerpt-only bodies never triggered Steel/Browserless extraction, and there was no retry mechanism for articles that failed to scrape on first attempt.

**Decision**: Flip defaults + add a background retry loop.
1. Migration 0015 bulk-updates `rss_only` → `auto_fetch_on_empty` (574 feeds touched in prod). The column default in the initial schema is still `rss_only`; every insert path (`src/routes/feeds.ts`, OPML import) now passes `auto_fetch_on_empty` explicitly.
2. New `articles.scrape_retry_count` + `articles.next_scrape_attempt_at` columns track background retry budget, separate from `fetch_attempt_count` which serves user-initiated fetches.
3. New hourly cron `retry-empty-articles` scans empty articles, calls shared `scrapeAndPersist()` helper, on failure increments retry count with exponential backoff (15m, 30m, 1h, 2h, 4h, capped at 24h), gives up after 5 attempts.
4. Admin web surfaces per-feed scrape mode edits, per-article rescrape button, and brief generation for a specific user.

**Consequences**: Articles with thin RSS bodies are automatically deep-fetched over time. Steel/Browserless cost scales with empty-body article volume (capped at ~50/hour by the cron batch size). Permanently-blocked sources stop retrying after 5 attempts; admin can pause those feeds via the web UI.

## ADR-013: SvelteKit Admin Web via Token Handoff (2026-04-24)

**Status**: Implemented (M17 Phase B)

**Context**: All admin observability was SQL-direct in D1 Studio. No moderator could diagnose feed failures without shelling into wrangler. The plan also called out a future consumer web reader.

**Decision**: Stand up a sibling repo `nebularnews-web` (SvelteKit 2 + Svelte 5 runes + Tailwind v4 + `@sveltejs/adapter-cloudflare`). Reuse the iOS Bearer-token auth model instead of enabling better-auth cross-subdomain cookies — a new `GET /api/auth/web-handoff` endpoint on the Workers API reads the session cookie from the api.nebularnews.com origin, looks up the session token in the `session` table, and redirects the browser to an allowlisted web callback with `?token=<token>`. The web app plants that in its own httpOnly cookie. iOS is unchanged.

**Rationale**: Decouples web's cookie flow from iOS's bearer flow (no cookie domain gymnastics, no CORS-with-credentials dance). Allowlist on the handoff prevents open-redirect abuse. Admin web lives at `admin.nebularnews.com` (Cloudflare Pages project `nebularnews-admin`). Consumer reader at `app.nebularnews.com` slots into the same app later under `/app` or a new domain.

**Consequences**: Apple Sign In for Web requires a separate Services ID (`com.nebularnews.web`) and a fresh client-secret JWT; documented in `nebularnews-web/APPLE_SETUP.md`. Better-auth may need its Apple provider to accept multiple audiences (App ID for native, Services ID for web) — verified during first real sign-in test. A dev-bypass (`DEV_BYPASS_ENABLED=true` + paste session token) lets development proceed before Apple setup completes.

## ADR-011: Unified Roadmap with Two-Tier Backlog (2026-04-04)

**Status**: Implemented

**Context**: The roadmap had flat milestones (M1-M4) with no distinction between work that needs an expensive model vs. mechanical cleanup. Infrastructure and tech debt items blocked product work in the priority order despite being independent. Two repos had separate roadmaps that duplicated information.

**Decision**: Single unified roadmap in the iOS repo (primary product). Phases are sequenced product work for capable models (Opus/Sonnet-class): M2 Article Reading → M3 AI Improvements → M4 Search & Discovery → M5 macOS. Backlog runs alongside phases, tagged `[minor]` (Sonnet/GPT-5.4/Gemini 3.1 Pro) or `[trivial]` (Haiku/OSS/Mini/Flash). Infrastructure (CI/CD, monitoring, Docker) moved to backlog since it's well-scoped. Widget Extension moved to backlog (code is written, just needs Xcode wiring). macOS stayed as a phase (needs sidebar nav design). API repo roadmap references the unified one.

**Rationale**: Expensive models focus on product differentiation (reading UX, AI features, discovery). Cheaper models handle mechanical cleanup in parallel. Each backlog item has enough context (file paths, what to change, why) that a model can pick it up cold without reading the whole codebase.

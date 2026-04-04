# Architecture Decision Records

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

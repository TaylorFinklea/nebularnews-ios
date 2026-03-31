# Architecture Decision Records

## ADR-001: Migrate D1 to Supabase Postgres (2026-03-27)

**Status**: Approved, not started

**Context**: D1 (SQLite) caused repeated production bugs — V17 migration fragility, schema.sql/runtime mismatch, `runSafe()` workarounds, FTS5 rebuild fragility, single-writer limitation.

**Decision**: Swap D1 for Supabase Postgres while keeping SvelteKit on Cloudflare Workers. The `db.ts` abstraction (`dbGet`/`dbRun`/`dbAll`) is the single point of change. Workers connects to Postgres via HTTP.

**Consequences**: ~2-week focused sprint. Supabase Pro ($25/mo). ~200 SQL queries need syntax updates. FTS5 -> tsvector. Latency increases from ~1-5ms to ~20-50ms per query (acceptable for news reader).

**Timing**: After current features stabilize (auth, onboarding, iOS).

## ADR-002: Apple Sign In via Supabase OAuth PKCE (2026-03-27)

**Status**: Implemented

**Context**: Magic link auth hit email rate limits. Needed alternative login method.

**Decision**: Use Supabase as OAuth identity broker for Apple Sign In. PKCE flow with GET endpoint at `/auth/apple` to avoid CSP `form-action 'self'` restriction. Ephemeral browser sessions on iOS to prevent stale cookie leakage.

**Consequences**: Apple client secret expires every 6 months (next: ~Sep 2026). Requires Apple Developer Service ID + Supabase provider config. Both `app.nebularnews.com` and `api.nebularnews.com` must be in Supabase redirect allowlist.

## ADR-004: Replace MobileAPIClient with Direct Supabase SDK (2026-03-29)

**Status**: Implemented (pending build verification)

**Context**: The iOS app communicated with the backend through `MobileAPIClient`, which made REST calls to a SvelteKit web app at `api.nebularnews.com`. This added an unnecessary middleware layer — the SvelteKit API endpoints were thin wrappers around the same Postgres database. With the Supabase Postgres migration approved (ADR-001), the iOS app can talk directly to Supabase.

**Decision**: Replace `MobileAPIClient` with `SupabaseManager` using the Supabase Swift SDK (`supabase-swift` v2.x). Auth switches from custom OAuth PKCE to Supabase Auth with Apple Sign In via ID token (`signInWithIdToken`). Data reads use PostgREST queries. Writes (reactions, read state, tags) use direct table upserts. AI operations (summarize, poll-feeds, OPML import/export) use Edge Function invocations.

**Consequences**:
- Removes dependency on SvelteKit mobile API endpoints
- JWT session management handled automatically by Supabase SDK (no more manual token refresh)
- Apple Sign In configured directly in Supabase Auth dashboard (not through SvelteKit broker)
- `MobileAPIClient` and `MobileOAuthCoordinator` kept temporarily for backward compatibility
- User must add `supabase-swift` SPM package in Xcode
- RLS policies on all tables must be verified for iOS app access patterns
- Edge functions must be deployed to the Supabase project

## ADR-003: Guided Onboarding with Curated Feeds (2026-03-27)

**Status**: Implemented

**Context**: New users saw empty app with no guidance.

**Decision**: Server-side curated feed catalog (~30 feeds, 7 categories) served via API. Both web (`/onboarding`) and iOS (`FeedSelectionView`) present category-based selection. Bulk subscribe endpoint triggers auto-pull so articles appear immediately.

**Consequences**: Catalog is code-based (not DB) — easy to version control, update requires deploy. iOS has three-phase onboarding: server connect -> feed selection -> main app.

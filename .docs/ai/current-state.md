# Current State (2026-04-10)

## Architecture — MIGRATED
- **Backend**: Cloudflare Workers + D1 (SQLite) in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client (Supabase SDK removed)
- **Auth**: better-auth with Apple/Google Sign In, Bearer token sessions
- **Old backend**: Supabase (nebularnews-api) — archived, not deployed

## Last Session Summary

**Date**: 2026-04-10

Major backend migration from Supabase to Cloudflare Workers + D1:

1. **Phase 1**: Stripped SvelteKit, installed Hono + better-auth, created project structure
2. **Phase 2**: Created D1 initial migration (592 lines, 30+ tables, FTS5 with triggers, ADR-001 fixes)
3. **Phase 3**: Wired better-auth with D1 via Kysely adapter, Apple/Google social sign-in
4. **Phase 4**: Built 25+ REST endpoints (articles, feeds, tags, settings, today, devices, onboarding)
5. **Phase 5**: Ported AI enrichment code (~1,100 LOC), created enrich/chat/brief endpoints
6. **Phase 6**: Created cron handlers (poll-feeds every 5min, score-articles hourly, cleanup daily)
7. **Phase 7**: Rewrote iOS networking layer — APIClient + all service files, BUILD SUCCEEDED

## Backend (nebularnews) — current file map
- `wrangler.toml` — D1 binding, 3 cron triggers, dev/staging/prod environments
- `migrations/0001_initial.sql` — comprehensive schema (30+ tables, 40+ indexes, FTS5 triggers)
- `src/index.ts` — Hono app with CORS, envelope middleware, auth, route mounting, scheduled handler
- `src/routes/` — articles, feeds, tags, settings, today, devices, onboarding, enrich, chat, brief, auth, health
- `src/lib/` — ai.ts, prompts.ts, normalizers.ts, feed-parser.ts, ai-key-resolver.ts, model-config.ts, auth.ts
- `src/cron/` — poll-feeds.ts, score-articles.ts, cleanup.ts
- `src/db/helpers.ts` — D1 query wrappers (dbGet, dbAll, dbRun, dbBatch)
- `src/middleware/` — auth.ts (Bearer token), envelope.ts (response wrapper)

## iOS App — current state
- Services rewritten: APIClient.swift (new), SupabaseManager.swift, AuthService.swift, ArticleService.swift, FeedService.swift, EnrichmentService.swift
- Supabase Swift SDK still in package graph but no longer imported — can be removed
- All SwiftUI views unchanged
- BUILD SUCCEEDED (macOS target, code signing disabled)
- TestFlight: Build 8 (2.0.1) was last Supabase-era release

## Ready to Test — Checklist
- [ ] Set secrets: `wrangler secret put BETTER_AUTH_SECRET`, `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET`
- [ ] Deploy: `cd ~/git/nebularnews && npx wrangler deploy`
- [ ] Create D1 database: `wrangler d1 create nebular-news-prod`
- [ ] Run migration: `wrangler d1 migrations apply DB --env production --remote`
- [ ] Test Apple Sign In end-to-end
- [ ] Test feed polling (add a feed, trigger cron)
- [ ] Test article enrichment with BYOK key
- [ ] Remove Supabase Swift Package from Xcode project
- [ ] Set `apiBaseURL` in iOS app to production URL

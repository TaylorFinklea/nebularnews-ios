# Current State (2026-04-11)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)
- **Old backend**: Supabase (nebularnews-api) — archived

## What's Working End-to-End
- Apple Sign In → session token → authenticated API calls
- Feed subscriptions (8 feeds, 4 active — 4 have stale URLs)
- Feed polling via cron (every 5 min) + manual trigger-pull
- 23 articles polled, 15 algorithmically scored
- Article list with scores, source names, pagination, FTS5 search
- Article detail with nested CompanionArticleDetailPayload structure
- Read/save/dismiss/react mutations
- Settings read/write
- Today dashboard (hero, up_next, stats, news_brief)
- Onboarding with curated feed catalog
- Device token registration
- Scraper code ported (Steel + Browserless + Readability) — needs API keys set

## What's Not Yet Tested
- AI enrichment (summarize, key points, AI score, chat, brief) — needs OPENAI/ANTHROPIC keys
- OPML import/export
- Tag management
- Feed add/delete from within the app
- Push notifications (APNS)
- Scoring cron (hourly auto-trigger) — manually verified working

## Known Issues
- 4 feed URLs return 404 (deeplearning.ai, openai, reuters, anthropic — URLs changed)
- Debug endpoints still in code (feeds/debug-poll, feeds/trigger-score)
- Some `articles.published_at` are null (feeds that don't include pubDate)
- 8 articles not scored (likely due to null published_at before the COALESCE fix was deployed)

## Session Commits
### nebularnews (Workers backend)
- 9542576: Phase 1 — strip SvelteKit, set up Hono
- c03ca6b: Phase 2 — D1 initial migration (592 lines, 30+ tables)
- 4fc1f95: Phase 3 — better-auth with D1
- 5128e88 + d70d564 + a9680c9: Phase 4 — 25+ core API endpoints
- 8c99a62: Phase 5 — AI enrichment, chat, brief
- 6cf8696: Phase 6 — cron workers
- Multiple fixes: auth middleware (Bearer → D1 lookup), response shapes (snake_case),
  feed polling (column names), scoring (table/column names), scraper port

### nebularnews-ios
- c91eb4f: Phase 7 — networking layer rewrite
- Multiple fixes: auth response shape, nonce hashing, Origin header, encoder strategy

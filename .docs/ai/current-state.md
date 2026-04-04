# Current State (2026-04-03)

## Architecture
- **Backend**: Supabase project `nebularnews-v2` (vdjrclxeyjsqyqsjzjfj) in us-east-1
- **iOS app**: SwiftUI + Supabase Swift SDK (direct PostgREST + Edge Functions)
- **Repos**: `nebularnews-api` (backend), `nebularnews-ios` (iOS)
- **Old infra**: All decommissioned (CF Workers, Vercel, old Supabase project, web repo archived)
- **Cost**: $0/mo (Supabase free tier)

## Backend (nebularnews-api)
- 29 tables with RLS enabled on all
- 8 migrations applied
- 10 Edge Functions deployed:
  - `poll-feeds` — RSS/Atom feed polling
  - `enrich-article` — AI summarize, score, key points, auto-tag (on-demand)
  - `process-jobs` — job queue processor (scraping jobs only)
  - `article-chat` — chat about articles with AI
  - `score-articles` — algorithmic scoring (4 signals, per-user)
  - `generate-news-brief` — AI editorial briefing
  - `scrape-article` — browser scraping with Steel/Browserless + Readability
  - `send-notification` — APNS push notifications
  - `import-opml` / `export-opml` — OPML feed management
- 6 pg_cron jobs:
  - `poll-feeds`: every 5 min
  - `process-jobs`: every 1 min (scraping only)
  - `score-articles`: every 5 min (offset by 2 min from polling)
  - `morning-brief`: 7 AM UTC
  - `evening-brief`: 6 PM UTC
  - `notify-new-articles`: every 15 min
- Scraping providers: Steel (primary), Browserless (fallback)
- Secrets: ANTHROPIC_API_KEY, OPENAI_API_KEY, STEEL_API_KEY, BROWSERLESS_API_KEY, APNS_*

## iOS App (nebularnews-ios)
- Supabase Swift SDK v2.43 for auth + data
- SwiftData local cache (CachedArticle, CachedFeed, PendingAction)
- SyncManager with offline queue (NWPathMonitor, auto-sync on reconnect)
- ArticleCache for instant loads + background refresh
- Apple Sign In via Supabase Auth
- BYOK: user API keys stored in iOS Keychain, sent via headers
- Per-feed controls: pause/resume, max articles/day, min score filter
- User settings (ProfileView) vs admin settings (CompanionSettingsView)
- AI features: summarize, key points, chat, news brief (all on-demand)
- Algorithmic scoring: 4 signals (feed reputation, freshness, depth, tag match)
- Re-scores on reaction (immediate feedback)
- Push notifications via APNS
- Home Screen widgets (stats, top article, reading queue) — code ready, needs Xcode target
- macOS code ready (#if os guards) — needs Xcode target
- Deep linking: nebularnews://article/{id}, nebularnews://today
- Onboarding: 16 feed suggestions across 5 categories
- TestFlight: Build 4 uploaded

## Session Continuity
- Handoff docs now at `.docs/ai/` (migrated from `docs/ai/`)
- Global workflow defined in `~/CLAUDE.md`
- Templates at `~/.claude/templates/handoff/`

## What works end-to-end
- Sign in with Apple → see articles from subscribed feeds
- Add/remove/pause feeds, import/export OPML
- Read/save/react to articles with offline support
- AI summarization, key points, chat (on-demand, BYOK or global keys)
- Algorithmic scoring with reaction-based learning
- Per-feed daily limits and min score filtering
- News brief generation (auto 2x daily + on-demand)
- Push notifications for new articles
- Feed scraping for aggregator feeds (HN configured)

## What's NOT done
- macOS target (code ready, needs Xcode setup)
- Widget Extension target (code ready, needs Xcode setup)
- Clean marketing version number (agvtool not resolving properly)
- Per-user AI rate limiting (BYOK done, quotas not enforced)
- Hybrid AI+algorithmic scoring
- Admin user management UI
- Full-text search UI (tsvector index exists, search not prominent in UI)
- Web/Android clients (future)
- Docker self-hosting tested end-to-end

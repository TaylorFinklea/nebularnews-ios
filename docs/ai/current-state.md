# Current State (2026-04-02, updated)

## Architecture
- **Backend**: Supabase project `nebularnews-v2` (vdjrclxeyjsqyqsjzjfj)
- **iOS app**: SwiftUI + Supabase Swift SDK (direct PostgREST + Edge Functions)
- **Repos**: `nebularnews-api` (backend), `nebularnews-ios` (iOS)
- **Old infra**: CF Workers deleted, Vercel removed, old Supabase paused, web repo archived

## What works
- Apple Sign In via Supabase Auth
- Feed polling (pg_cron every 5 min, 3 feeds, ~420+ articles)
- Article list with search, read/unread filter, sort
- Article detail view
- Save/unsave articles (Lists page)
- Per-feed controls: pause/resume, max articles/day, min score filter
- AI summarization on-demand via Edge Functions (Anthropic Claude)
- BYOK: users can store their own Anthropic/OpenAI keys in iOS Keychain, sent to Edge Function via headers
- OPML import/export
- SwiftData local cache (instant loads, offline reading)
- BBC image quality upgraded to 1024px
- Push notifications end-to-end: iOS token registration, APNS Edge Function, pg_cron batch job every 15 min
- pg_net extension enabled (also fixed poll-feeds cron which was failing)
- Algorithmic article scoring: 4-signal engine (source reputation, content freshness, content depth, tag match ratio) runs on pg_cron every 5 min, scores 1-5 per user with confidence + evidence JSON

## What's not done yet
- Per-user AI rate limiting (BYOK is done, rate limiting is not)
- User settings vs admin settings separation in UI
- On-demand AI scoring and key points (only summarize works; algorithmic scoring is live)
- macOS app
- Docker self-hosting docs
- News brief generation
- Chat with articles

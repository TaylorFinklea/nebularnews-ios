# NebularNews iOS Claude Instructions

## Architecture
- **Backend**: Cloudflare Workers + D1 (SQLite) at `api.nebularnews.com`
- **Backend repo**: `nebularnews` at `/Users/tfinklea/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client (no Supabase SDK)
- **Auth**: better-auth with Apple Sign In, Bearer token sessions stored in Keychain
- **Old backends**: Supabase (`nebularnews-api`) and SvelteKit (`nebularnews` pre-rewrite) — archived

## Working Style
- Prefer native Apple frameworks and interaction patterns over custom UI/control systems.
- Keep custom visual treatment for editorial/content surfaces, not utility controls.
- Read the existing code before changing architecture or patterns.
- Make focused, minimal changes that fit the current codebase.

## Code Change Expectations
- After code changes, make a small descriptive commit by default.
- Do not push unless the user explicitly asks.
- Use repository-native edit workflows and avoid broad rewrites unless required.

## Shell Commands
- Run one command at a time unless the output of one must pipe into the next.
- Never chain independent commands with `&&`. Use `git -C <path>` instead of `cd <path> && git`.

## Verification
- Build iOS with: `xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- Deploy Workers with: `cd /Users/tfinklea/git/nebularnews && npx wrangler deploy --env production`
- Mention clearly if something could not be verified.

## Data Layer
- **APIClient** (`Services/APIClient.swift`): Generic REST client with Bearer token auth, BYOK headers, JSON envelope decoding (.convertFromSnakeCase).
- **SupabaseManager** (`Services/SupabaseManager.swift`): Facade that delegates to service classes. Still named SupabaseManager for compatibility — calls Workers API, not Supabase.
- **ArticleService/FeedService/EnrichmentService/AuthService**: Domain services using APIClient.
- **ArticleCache** (`Services/ArticleCache.swift`): SwiftData cache for instant loads and offline reading.
- **SyncManager** (`Services/SyncManager.swift`): Offline queue. All mutations go through SyncManager.
- **KeychainManager** (in NebularNewsKit): Stores session token and personal AI API keys.

## Key Patterns
- **Auth**: better-auth returns session token on sign-in. iOS stores it in Keychain, sends as `Authorization: Bearer <token>`. Auth middleware validates via D1 session table lookup.
- **BYOK**: User's API keys stored in iOS Keychain, sent as `x-user-api-key` / `x-user-api-provider` headers.
- **Per-feed controls**: `user_feed_subscriptions` has `paused`, `max_articles_per_day`, `min_score` columns.
- **Algorithmic scoring**: 4 signals (feed reputation, freshness, depth, tag match), per-user, hourly cron.
- **Scraping**: Steel (primary) + Browserless (fallback) + Readability extraction for feeds with `scrape_mode != 'rss_only'`.
- **Response format**: All Workers endpoints return `{ ok: true, data: ... }` with snake_case keys. iOS decoder uses `.convertFromSnakeCase`.

## Workers Backend
- **D1 schema**: `migrations/0001_initial.sql` — 30+ tables, FTS5 with incremental triggers
- **Routes**: `src/routes/` — articles, feeds, tags, settings, today, enrich, chat, brief, devices, onboarding, auth, health
- **Crons**: poll-feeds (*/5 min), score-articles (hourly), cleanup (daily 3:30am)
- **Secrets**: BETTER_AUTH_SECRET, APPLE_CLIENT_ID, APPLE_CLIENT_SECRET, OPENAI_API_KEY, ANTHROPIC_API_KEY, STEEL_API_KEY, BROWSERLESS_API_KEY

## Release / TestFlight
- Run `./scripts/release.sh` to archive and upload to TestFlight.
- Flags: `--patch` (default) or `--minor`.

## Project Notes
- API keys stored in macOS Keychain for local dev, Wrangler secrets for production.
- Prefer local-first and background-friendly designs; do not block core reading flows on optional enrichment.
- AI enrichment is on-demand only (not background) to control costs.
- Apple client secret JWT expires ~Oct 2026 — regenerate with the .p8 key (Key ID: Z4D9B5P5F6).

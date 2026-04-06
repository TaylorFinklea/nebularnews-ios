# NebularNews iOS Claude Instructions

## Architecture
- **Backend**: Supabase project `nebularnews-v2` (vdjrclxeyjsqyqsjzjfj) — Edge Functions + PostgREST + RLS
- **Backend repo**: `nebularnews-api` at `/Users/tfinklea/git/nebularnews-api`
- **iOS app**: SwiftUI + Supabase Swift SDK v2.x — direct PostgREST for reads, Edge Functions for AI/scraping
- **No web app**: The SvelteKit web app was decommissioned. The old `nebularnews` repo is archived.

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
- Build iOS with: `xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Deploy Edge Functions with: `cd /Users/tfinklea/git/nebularnews-api && npx supabase functions deploy <name> --no-verify-jwt`
- Mention clearly if something could not be verified.

## Data Layer
- **SupabaseManager** (`Services/SupabaseManager.swift`): All Supabase API calls. PostgREST for reads, Edge Functions for AI/chat/scraping.
- **ArticleCache** (`Services/ArticleCache.swift`): SwiftData cache for instant loads and offline reading.
- **SyncManager** (`Services/SyncManager.swift`): Offline queue. All mutations go through SyncManager which updates cache optimistically, attempts network, queues on failure.
- **KeychainManager** (in NebularNewsKit): Stores user's personal AI API keys.

## Key Patterns
- Client-side filtering: PostgREST can't filter on left-joined columns. Read/saved/feed-limit filters are applied client-side after fetching. Overfetch 4x to compensate.
- BYOK: User's API keys stored in iOS Keychain, sent as `x-user-api-key` / `x-user-api-provider` headers to Edge Functions.
- Per-feed controls: `user_feed_subscriptions` has `paused`, `max_articles_per_day`, `min_score` columns. RLS hides paused feed articles.
- Algorithmic scoring: 4 signals (feed reputation, freshness, depth, tag match), per-user, auto via pg_cron.

## Release / TestFlight
- Run `./scripts/release.sh` to archive and upload to TestFlight.
- Flags: `--patch` (default, 2.0.1 → 2.0.2) or `--minor` (2.0.1 → 2.1.0).
- The script bumps version via `agvtool`, archives, exports, uploads, and commits.
- **Non-interactive auth**: Set `ASC_API_KEY_PATH`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` env vars for automated upload. Without them, falls back to Xcode GUI session auth.
- **Auto-release**: A PostToolUse hook detects `feat(m\d)` commit messages and emits `AUTO_RELEASE`. When you see this, dispatch the release agent in the background.
- **Manual release**: Dispatch the release agent directly, or run `bash scripts/release.sh`.

## Edge Function Deployment
- All functions deployed with `--no-verify-jwt` (auth handled in function code)
- Secrets managed via `npx supabase secrets set KEY=value`
- Supabase project ref: `vdjrclxeyjsqyqsjzjfj`
- Anon key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZkanJjbHhleWpzcXlxc2p6amZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NTk0OTIsImV4cCI6MjA5MDUzNTQ5Mn0.9j644tw6xud8GNW-J0X_sgtR_oyXGEoi59cN-O7wTHY`

## Project Notes
- API keys (OPENAI, ANTHROPIC) stored in macOS Keychain for local dev, Supabase secrets for production.
- Prefer local-first and background-friendly designs; do not block core reading flows on optional enrichment.
- AI enrichment is on-demand only (no background AI processing) to control costs.
- Apple client secret JWT expires ~Sep 2026 — regenerate with the .p8 key.

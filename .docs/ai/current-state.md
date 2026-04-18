# Current State (2026-04-18)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## Completed Milestones
- **M1-M5**: Core reading, article UX, AI improvements, search & discovery, macOS app
- **M6**: AI Overhaul — three-tier AI, streaming chat, MCP server, floating AI assistant, admin dashboard, auto-enrichment, scheduled briefs, scoring v2, topic clustering
- **M7**: Inbox Unification (code complete) — email newsletter backend, web clipper, Share Extension. Manual: CF Email Routing config, e2e device testing.
- **M8**: Reader Depth — collections, highlights, annotations, Markdown export. Deployed.

## M9: Deep Fetch + New Source Types — Deployed ✅

### Problem Solved
Many feeds (e.g. Anthropic) only deliver title + link with no body content. This broke reading and all AI enrichment actions.

### Done
- **D1 migration 0009** (`migrations/0009_deep_fetch.sql`): adds `last_fetch_attempt_at`, `fetch_attempt_count`, `last_fetch_error` to `articles` table
- **`POST /articles/:id/fetch-content`** (articles.ts): on-demand deep scrape; Steel → Browserless → fetch+Readability fallback; 1-hour cooldown after 2+ attempts
- **Auto-scrape on AI actions** (enrich.ts): `fetchArticleWithContent()` transparently deep-fetches empty articles before summarize/key-points/etc.
- **`auto_fetch_on_empty` scrape_mode** (poll-feeds.ts, feeds.ts): triggers scrape during RSS poll when ingested item has < 50 words; `PATCH /feeds/:id` toggles mode
- **iOS deep-fetch UI**: "Fetch Full Article" CTA in empty-state + toolbar button; `FeedURLNormalizer` for Reddit/HN/Mastodon/YouTube URL normalization; feed settings scrape-mode picker
- **Admin**: `GET /admin/scraping-stats` endpoint + `AdminScrapingStatsView` showing fetched counts, cooldowns, extraction quality, recent errors

### Post-deploy Bug Fixes (2026-04-18)
- **Search crash**: SwiftData `#Predicate` with `?? ""` on optional fields generated TERNARY SQL CoreData can't handle — moved search to in-memory `.filter()` after fetch
- **Scraper 500s**: `linkedom` fails parsing certain HTML in Workers V8 — wrapped `parseHTML`/`reader.parse()` in try-catch for graceful degradation
- **YouTube @handle**: `@handles` ≠ legacy usernames; RSS requires channel_id — normalizer now passes through with hint to use channel RSS URL directly
- **Summary broken**: `article_summaries` INSERT used non-existent `length_category`/`style` columns — removed
- **Brief broken**: `news_brief_editions` INSERT used completely wrong column names (table is designed for scheduled cron, not on-demand) — removed INSERT, brief returns result directly
- **Brief SQL variable limit**: D1 hits ~100-variable limit with large `IN` clauses when user has many feeds or long lookback window — rewrote to single JOIN query with constant variable count
- **Admin scraping stats decode crash**: `attempted_at: Int` (non-optional) failed to decode when D1 returns null — made `Int?`

## Deployed Migrations
- 0001 through 0009 applied on production D1

## Known Issues
- M7 manual: CF Email Routing not yet configured for `read.nebularnews.com`
- Highlight creation uses paste-based alert (MVP); future: intercept native text selection
- SyncManager doesn't yet queue collection/highlight/annotation mutations offline
- YouTube @handle feed URLs don't auto-resolve to RSS (requires channel_id lookup)

## Both Repos
- `nebularnews-ios`: 2edf397 (HEAD)
- `nebularnews`: 1571c33 (HEAD)

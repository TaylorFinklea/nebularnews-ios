# Current State (2026-04-17)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## Completed Milestones
- **M1-M5**: Core reading, article UX, AI improvements, search & discovery, macOS app
- **M6**: AI Overhaul — three-tier AI, streaming chat, MCP server, floating AI assistant, admin dashboard, auto-enrichment, scheduled briefs, scoring v2, topic clustering
- **M7**: Inbox Unification (code complete) — email newsletter backend, web clipper, Share Extension. Manual: CF Email Routing config, e2e device testing.

## M8: Reader Depth — Code Complete (deployed)

### Done
- **Phase 1 (Collections)**: D1 migration (4 tables), Workers CRUD route, iOS CollectionService, Library tab (replaces Lists), CreateCollectionSheet, EditCollectionSheet, AddToCollectionSheet, collection detail view
- **Phase 2 (Highlights)**: Workers highlights route (CRUD), article detail endpoint returns highlights, iOS HighlightService, HighlightsSection in detail view, highlight creation via alert + toolbar button
- **Phase 3 (Annotations)**: Workers annotations route (GET/PUT/DELETE), article detail endpoint returns annotation, iOS AnnotationService, AnnotationSection with TextEditor sheet
- **Phase 4 (Export)**: Client-side MarkdownExporter, ShareLink in article detail toolbar and collection detail menu
- M8 deployed to production (migration 0008 applied, Workers live)

## M9: Deep Fetch + New Source Types — Code Complete (not yet deployed)

### Problem Solved
Many feeds (e.g. Anthropic) only deliver title + link with no body content. This broke reading and all AI enrichment actions.

### Done
- **D1 migration 0009** (`migrations/0009_deep_fetch.sql`): adds `last_fetch_attempt_at`, `fetch_attempt_count`, `last_fetch_error` to `articles` table
- **`POST /articles/:id/fetch-content`** (articles.ts): on-demand deep scrape; Steel → Browserless → fetch+Readability fallback; 1-hour cooldown after 2+ attempts; respects `scrape_provider` from feed
- **Auto-scrape on AI actions** (enrich.ts): `fetchArticleWithContent()` now transparently deep-fetches if `content_text` is empty, then proceeds with summarize/key-points/etc.
- **`auto_fetch_on_empty` scrape_mode** (poll-feeds.ts, feeds.ts): new mode triggers scrape during RSS poll only when ingested item has < 50 words; `PATCH /feeds/:id` endpoint to toggle mode
- **iOS `FetchContentResult` DTO + `EnrichmentService.fetchFullContent()`**: wires `POST /articles/:id/fetch-content` into iOS
- **iOS `FeedURLNormalizer`** (`Services/FeedURLNormalizer.swift`): normalizes Reddit, YouTube, Mastodon, HN pasted URLs to RSS equivalents; sets `scrapeMode` for link-aggregators
- **iOS empty-state CTA** (`RichArticleContentView`, `ArticleBodyView`): shows "Fetch Full Article" button when content is absent; toolbar always shows the action
- **iOS feed settings**: Picker now shows `rss_only` / `auto_fetch_on_empty` / `always`; `CompanionAddFeedSheet` uses normalizer and sends scrapeMode on subscription

### Remaining (Manual)
- Deploy Workers: `cd ~/git/nebularnews && npx wrangler deploy --env production`
- Run migration: `npx wrangler d1 migrations apply nebular-news-prod --env production --remote` (note: binding is `nebular-news-prod` with hyphens)
- End-to-end test: open Anthropic article → tap Fetch → content loads; tap Summarize on empty article → auto-fetch + summary

## Deployed Migrations
- 0001 through 0008 applied on production D1
- 0009 (deep_fetch) written, not yet deployed

## Known Issues
- M7 manual: CF Email Routing not yet configured for `read.nebularnews.com`
- Highlight creation uses paste-based alert (MVP); future: intercept native text selection
- SyncManager doesn't yet queue collection/highlight/annotation mutations offline

## Both Repos
- `nebularnews-ios`: 77d0a75 (HEAD — M9 iOS code complete)
- `nebularnews`: 75618d1 (HEAD — M9 backend code complete)

# Next Steps (2026-04-17)

## Deploy M9 Backend

- [ ] Deploy Workers: `cd ~/git/nebularnews && npx wrangler deploy --env production`
- [ ] Run migration: `npx wrangler d1 migrations apply nebular-news-prod --env production --remote`
  - Note: binding name is `nebular-news-prod` (hyphens), not `nebularnews-prod`

## Test M9 Deep Fetch

- [ ] Open an Anthropic article (title-only) → tap "Fetch Full Article" → content loads
- [ ] Tap "Summarize" on a second empty article → backend auto-fetches + summary generates
- [ ] Paste a subreddit URL in AddFeed → detects as Subreddit, normalizes to `.rss`, shows hint
- [ ] Paste a YouTube channel URL → normalizes to RSS feed URL
- [ ] Paste `https://news.ycombinator.com` → normalizes to `https://hnrss.org/frontpage`
- [ ] Open feed settings → change scrape mode to "Auto-fetch when empty" → save → next poll uses it

## Test M8 Reader Depth (if not yet done)

- [ ] Create a collection → add articles → view, edit, delete
- [ ] Create a highlight from article detail
- [ ] Add an annotation (note) to an article
- [ ] Export article as Markdown via ShareLink
- [ ] Export collection as Markdown via ShareLink

## M7 Manual Items (Still Pending)

- [ ] Configure CF Email Routing: `read.nebularnews.com` in CF Dashboard
- [ ] End-to-end test: forward a newsletter, clip from Safari on device

## M9 Deferred / Polish

- [ ] Quality-based retry: if `extraction_quality < 0.3`, try next provider tier
- [ ] Retroactive backfill of existing empty articles (per-feed opt-in)
- [ ] True non-RSS source integrations: Reddit JSON API, Mastodon REST, YouTube Data API
- [ ] Source-type dispatcher refactor in poll-feeds.ts

## M8 Deferred Polish

- [ ] SyncManager offline support for collection/highlight/annotation mutations
- [ ] Improve highlight creation: intercept native text selection instead of paste alert
- [ ] Highlight rendering: yellow background overlays in RichArticleContentView

## Future Milestones

- **M10: Platform Polish** — iPad layout, Lock Screen widgets, Live Activities, Watch glance

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation
- [ ] User timezone support for scheduled briefs (currently UTC)
- [ ] AI assistant direct actions (tool-calling to filter articles, navigate, apply tags)

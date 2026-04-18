# Next Steps (2026-04-18)

## Test M9 Deep Fetch (in progress)

- [x] Deploy Workers + migration 0009
- [x] Open an Anthropic article → tap "Fetch Full Article" → content loads
- [x] Summarize on empty article → auto-fetch + summary generates
- [x] Paste subreddit URL → detects as Subreddit, normalizes to `.rss`, shows hint
- [x] Generate news brief (24h) → works after JOIN rewrite
- [ ] Paste `https://news.ycombinator.com` → normalizes to `https://hnrss.org/frontpage`
- [ ] Open feed settings → change scrape mode to "Auto-fetch when empty" → save
- [x] Admin → Users / Feeds / AI Stats / Scraping Stats → all fixed (wrong table name, nullable title, nullable attemptedAt)

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
- [ ] YouTube @handle → RSS resolution (requires network call to resolve channel_id)
- [ ] Source-type dispatcher refactor in poll-feeds.ts

## M8 Deferred Polish

- [ ] SyncManager offline support for collection/highlight/annotation mutations
- [ ] Improve highlight creation: intercept native text selection instead of paste alert
- [ ] Highlight rendering: yellow background overlays in RichArticleContentView

## M10: Platform Polish (Tier 1 code complete — needs device testing)

- [x] Lock Screen widget completion: TopArticleWidget + StatsWidget + ReadingQueueWidget all support accessory families (rectangular/circular/inline as appropriate)
- [x] iPad split-view: NavigationSplitView on regular size class, TabView on compact; reused macOS sidebar pattern
- [x] Article reader max-width 720pt for iPad/Mac comfort
- [x] Live Activity for brief generation: shared BriefActivityAttributes, BriefLiveActivity widget (lock + DI compact + DI expanded), BriefLiveActivityController wraps generateBrief() flow; NSSupportsLiveActivities=true added to Info.plist
- [ ] **Device test**: install on iPad → verify split-view layout in portrait + landscape, Stage Manager
- [ ] **Device test**: add accessory widget to Lock Screen → verify renders + privacy redaction
- [ ] **Device test**: trigger brief generation → verify Live Activity appears in Dynamic Island + Lock Screen, dismisses after 30s

## M10 Deferred / Stretch (Tier 2)

- [ ] Apple Watch glance — new watchOS target with unread complication + top-5 list, Handoff to phone
- [ ] AddFeedSheet popover-vs-sheet on iPad regular size class
- [ ] AI assistant FAB anchor in detail pane on iPad regular (currently anchors to window edge)
- [ ] Post-mutation widget refresh — markRead/save mutations don't currently invalidate widget cache
- [ ] APNs Live Activity push for scheduled (cron) brief generation

## Future Milestones

- **M11**: AI assistant direct actions (tool-calling: filter articles, navigate, apply tags) — see backlog

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation
- [ ] User timezone support for scheduled briefs (currently UTC)
- [ ] AI assistant direct actions (tool-calling to filter articles, navigate, apply tags)

# Next Steps (2026-04-26)

## Push Notification Service Extension — in progress

- [x] Backend: `mutable-content: 1` flag + brief payload `bullets` array + lead `image_url` — **(this session)**
- [ ] User creates NSE target in Xcode (File → New → Target → Notification Service Extension; product name `NebularNewsNotifyService`, bundle id `com.nebularnews.ios.NotifyService`, embed in NebularNews)
- [ ] Customize generated `NotificationService.swift` — image download with 8s timeout, body rewrite to 2 bullets, graceful fallback in `serviceExtensionTimeWillExpire()`
- [ ] macOS xcodebuild clean (NSE skipped on macOS destination)
- [ ] Device verification: install from Xcode → trigger brief via "Preview next brief" → confirm image + 2 bullets land on lock screen

## Design-wait deferred (after design lands)

- Audit-log web UI on the admin (data-only ship today)
- Provider usage tile on the dashboard (data-only ship today)
- iOS reading streaks (design-touchy)
- AI-assistant "navigate to article" TODO (small)
- Article-type push notifications via NSE (backend doesn't currently emit them)

## Verification work pending device

- Chunk 3 (M16 Tier 2): scroll to mid-article, back out, reopen → confirm auto-scroll lands at saved anchor
- Provider observability: after first hourly retry cron run post-deploy, `provider_calls` should populate; check `/admin/usage` returns non-empty `today` map

## Watch for next 24-72h

- Quality-based escalation (chunk 4) might be too aggressive at 0.25 threshold — watch `avg_extraction_quality` on dashboard. If many recovered articles flip back to retry-state and burn provider cost, tune downward.
- 17 articles with `no_readable_content` marker that didn't get backfilled — see if retry cron quarantines them naturally over the next day.

---

# Next Steps (2026-04-24)

## M17 manual follow-ups (unblock admin web)

- [ ] Apple Services ID `com.nebularnews.web` (dev portal) + Return URL `https://api.nebularnews.com/api/auth/callback/apple` + `admin.nebularnews.com` domain verification — follow `nebularnews-web/APPLE_SETUP.md`.
- [ ] Host Apple domain-verification file at `admin.nebularnews.com/.well-known/apple-developer-domain-association.txt` via SvelteKit `static/`.
- [ ] Mint web client-secret JWT with the existing `.p8` (key id `Z4D9B5P5F6`) and set it as Wrangler secret `APPLE_CLIENT_SECRET_WEB` (prod env).
- [ ] `wrangler secret put APPLE_SERVICES_ID --env production` → `com.nebularnews.web`.
- [ ] Update `src/lib/auth.ts` to hand better-auth a multi-audience Apple clientId once the real flow is ready to test.
- [ ] CF dashboard → Pages → `nebularnews-admin` → Custom domain → add `admin.nebularnews.com`.
- [ ] First real end-to-end sign-in test on the custom domain; turn off `DEV_BYPASS_ENABLED` for prod.

## M17 Phase A device verification

- [ ] Watch Steel/Browserless costs for the first 24–48h post-deploy — 574 feeds just flipped from rss_only to auto_fetch_on_empty.
- [ ] Spot-check iOS: open an article that was empty yesterday, confirm it now has content after the retry cron picked it up.
- [ ] Admin web → Feeds → sanity-check the `scrape_mode` column for high-subscriber feeds.
- [ ] Admin web → Articles → `Empty only` filter → confirm the retry cron is draining the backlog over time.

## Phase C candidates (consumer web reader)

- `app.nebularnews.com` SvelteKit reader: Today, article detail, brief history, sparkle chat. Share components with admin where it makes sense.
- CORS tightening on the Workers API — currently `*`; lock to admin + app + native scheme before consumer launch.

---

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

## M11: AI Assistant Direct Actions (Tier 1 code complete — needs device testing)

- [x] Migration 0010: `chat_messages.tool_calls_json` column (applied to production D1)
- [x] Backend: `runChatWithTools()` for OpenAI + Anthropic native tool-calling with normalized `RunChatToolResult` union
- [x] Backend: `src/lib/chat-tools.ts` registry — 9 server-executed tools (4 data reads reusing MCP handlers + 5 mutations: mark_articles_read / set_article_reaction / apply_tag_to_article / set_feed_max_per_day / pause_feed) + 4 client-executed tools (open_article / navigate_to_tab / set_articles_filter / generate_brief_now)
- [x] Backend: `/chat/assistant` runs max-4-round tool loop; emits `tool_call_server` + `tool_call_client` SSE events; persists tool calls to `tool_calls_json`
- [x] Backend: assistant system prompt updated with tool usage guidance
- [x] iOS: `AssistantContentSegment.toolResult` + parser for `[[tool:name:summary:1|0]]` inline markers; chip rendering in `AssistantChatBubble`
- [x] iOS: `StreamingChatService` parses new SSE event types into `ChatDelta.toolServerResult` / `.toolClientCall`
- [x] iOS: `AssistantActionDispatcher` maps client tools to AppState mutations + DeepLinkRouter
- [x] iOS: AppState `pendingTabSwitch` / `pendingArticlesFilter` / `pendingBriefGeneration` bindings observed by MainTabView / CompanionArticlesView / CompanionTodayView
- [x] iOS + macOS builds clean. Backend deployed (325c6049).
- [ ] **Device test**: ask AI to mark articles read → chip appears, articles flip to read in list
- [ ] **Device test**: ask AI to open an article → detail view pushes
- [ ] **Device test**: ask AI to filter articles → filter bar updates, list refreshes
- [ ] **Device test**: ask AI to tag an article → tag appears in article detail
- [ ] **Device test**: ask AI to pause/cap a noisy feed → feed settings update
- [ ] **Device test**: try a prompt that should require no tools → no spurious tool calls

## M11 Deferred / Stretch (Tier 2)

- [x] Tool-call analytics in Admin dashboard — `GET /admin/tool-call-stats` + `AdminToolCallStatsView` (7-day totals + per-tool success rates)
- [x] `subscribe_to_feed` server tool — ports FeedURLNormalizer to TypeScript; guards YouTube @handles
- [x] AI-applied filter banner — purple "AI applied filter · Reset" strip in CompanionArticlesView
- [x] Assistant system prompt updated with tool-use guardrails (don't invent ids, don't narrate over chips)
- [ ] Confirm-before-mutate sheet OR undo-chip for destructive actions (mark_articles_read >5, pause_feed, unsubscribe) — pick one approach; undo-chip recommended for lower friction
- [ ] On-device FoundationModels tool-calling when Apple Intelligence supports it
- [ ] Multi-step planner mode using extended thinking / reasoning models
- [ ] Voice input → tool call via SiriKit / AppIntents

## M12: Offline Mutation Queue + AI Tool-Call Bug Fixes — Shipped (needs device verification)

**Track A — Offline Queue (iOS):**
- [x] SyncManager extended to feed mutations (feed_settings / subscribe_feed / unsubscribe_feed)
- [x] Max retries 5 → 10
- [x] Dead-letter state with retry/discard helpers
- [x] Post-sync `WidgetCenter.reloadAllTimelines()`
- [x] `hasPendingAction(forResource:)` helper + "Syncing…" indicators on feed rows and article detail
- [x] CompanionFeedsView pause/resume + Feed Settings save sheet route through SyncManager
- [x] Backend If-Match scaffolding on PATCH /feeds/:id/settings with ETag in success response
- [ ] **Device test**: Airplane Mode → tag, mark read, pause feed → re-enable network → confirm replay within 5s
- [ ] **Device test**: same flow but force-quit before re-enabling network → confirm persistence
- [ ] **Device test**: widget reflects new unread/saved counts within 15s of sync without app relaunch

**Track B — AI Tool-Call Fixes (sprint-absorbed):**
- [x] FK guards in mark_articles_read / pause_feed / set_feed_max_per_day
- [x] undo_set_feed_max_per_day added to UNDO_TOOL_NAMES
- [x] Full error context logged to debug_log scope `tool-error:*`
- [x] /admin/tool-call-stats: thrown_errors + logging_gap columns
- [ ] **Manual test**: ask sparkle "pause the feed called 'nonexistent'" → red chip "Couldn't find feed", debug_log captures the call
- [ ] **Manual test**: open Admin → Tool Calls → confirm new columns render, verify pause_feed/set_feed_max_per_day show 0 logging gap after a real call

## M12 Deferred / Stretch (Tier 2)

- [ ] Queue inspection UI in Settings → Advanced (pending list with age, retry count, last error; manual retry/discard)
- [ ] Sync conflict resolver UI when 412 returns — sheet with Keep server / Apply mine / Discard
- [ ] Tool-call failure admin alerting (red badge if 24h success rate < 80%)
- [ ] iOS If-Match capture+send (backend scaffolding shipped, client wiring deferred)

## Future Milestones

- **M13** candidates: timezone-aware briefs (cron + iOS settings), watchOS app, RevenueCat/receipt validation
- **M10 deferred polish** (Sonnet-tier backlog): AddFeedSheet popover on iPad regular, AI FAB anchor, post-mutation widget refresh, APNs Live Activity push for scheduled briefs

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation
- [ ] User timezone support for scheduled briefs (currently UTC)
- [ ] OpenAI native tool-call streaming (currently buffered fallback)

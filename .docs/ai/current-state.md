# Current State (2026-04-20)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## Completed Milestones
- **M1-M5**: Core reading, article UX, AI improvements, search & discovery, macOS app
- **M6**: AI Overhaul — three-tier AI, streaming chat, MCP server, floating AI assistant
- **M7**: Inbox Unification — email newsletter backend, web clipper, Share Extension
- **M8**: Reader Depth — collections, highlights, annotations, Markdown export
- **M9**: Deep Fetch + New Source Types
- **M10**: Platform Polish — iPad split view, Lock Screen widgets, Live Activity, Apple Watch glance
- **M11**: AI Assistant Direct Actions — sparkle tool calling (server + client tools, undo chips, native Anthropic streaming)

## M12: Offline Mutation Queue + AI Tool-Call Bug Fixes — Shipped ✅

### Track A — Offline Mutation Queue (iOS)
- `SyncManager` extended to cover feed mutations: action types `feed_settings`, `subscribe_feed`, `unsubscribe_feed` with matching payload structs and queue-aware convenience methods (`updateFeedSettings`, `subscribeFeed`, `unsubscribeFeed`)
- Max retries bumped 5 → 10
- Dead-letter state: actions that exceed maxRetries stay in the table but are filtered from `fetchPendingActions`. New `fetchDeadLetterActions` / `retryDeadLetter` / `discardDeadLetter` helpers for user-driven recovery
- Post-sync widget invalidation via `WidgetCenter.shared.reloadAllTimelines()` (gated for macCatalyst)
- `hasPendingAction(forResource:)` helper used by views to render "Syncing…" indicators
- `CompanionFeedsView`: pause/resume and Feed Settings save sheet route through SyncManager; subtle cloud-slash "Syncing…" label per row
- `CompanionArticleDetailView`: "Changes will sync when online" banner above tags when article has pending mutations
- Backend: `PATCH /feeds/:id/settings` accepts optional `If-Match` header (compact ETag of `paused/max/min`); 412 Precondition Failed on mismatch with `current_etag` in payload. Scaffold for future conflict-resolver UI

### Track B — AI Tool-Call Fixes (sprint-absorbed)
- FK existence guards in `chat-tools.ts`:
  - `mark_articles_read`: filters via `SELECT IN (...)` to valid article ids; reports skipped count
  - `pause_feed` / `set_feed_max_per_day`: verify `user_feed_subscriptions` row exists; include feed title in summaries
- Added `undo_set_feed_max_per_day` (was missing undo coverage); `UNDO_TOOL_NAMES` updated
- `executeServerTool` catch block now persists full error context (name + msg + stack + args + userId) to `debug_log` under scope `tool-error:{toolName}`
- `/admin/tool-call-stats` surfaces two new per-tool metrics: `thrown_errors` (count from debug_log scope) and `logging_gap` (count − succeeded − failed) — exposes under-instrumented tools
- `AdminToolCallStatsView` renders thrown_errors (red) + logging_gap (orange) columns

## Earlier session (2026-04-19/20): Sparkle assistant fixes
- **Route shadowing bug** (long debug trail): `chatRoutes.post('/chat/:articleId', ...)` was matching POST `/chat/assistant` (with `articleId="assistant"`) and inserting `chat_threads.article_id="assistant"` which violated FK to `articles(id)`. Fix: added regex constraint `{(?!assistant$|assistant/|multi$|multi/|undo-tool$).+}` to both GET/POST `/chat/:articleId` patterns so reserved sentinels skip the generic handler. Same shadowing affected GET /chat/assistant, GET /chat/multi, POST /chat/multi, POST /chat/undo-tool — all now properly routed.
- **Streaming with tool support**: added `streamChatWithTools()` in `src/lib/ai.ts` that streams Anthropic SSE with tool_use accumulation (text_delta + tool_use + done events). Wired into POST `/chat/assistant` so users see token-by-token streaming end-to-end. OpenAI falls back to buffered `runChatWithTools` (proper OpenAI tool streaming is a follow-up).

## Deployed Migrations
- 0001 through 0012 applied on production D1
- (Migration 0012 = temporary `debug_log` table; reused for `tool-error:*` scope as production diagnostic per M12 plan)

## Known Issues / Deferred
- M7 manual: CF Email Routing not yet configured for `read.nebularnews.com`
- iOS If-Match conflict resolver UI: backend scaffolding shipped, client capture+send is a follow-up
- OpenAI native tool-call streaming: still uses buffered fallback
- M11 confirm-before-mutate sheet for very destructive actions: undo-chip currently covers most cases

## Both Repos
- `nebularnews-ios`: 28c926b (HEAD)
- `nebularnews`: 63af35a (HEAD)

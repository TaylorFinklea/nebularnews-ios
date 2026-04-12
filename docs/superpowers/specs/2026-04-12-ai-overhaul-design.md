# M6: AI Overhaul — Design Spec

## Context

NebularNews is an iOS RSS reader with AI enrichment (summarize, key points, score, chat, briefs). The backend recently migrated from Supabase to Cloudflare Workers + D1. AI features were built in M3 but are currently request-response only, have no rate limiting (table exists but isn't enforced), no streaming, and limited tier differentiation. The on-device FoundationModels engine exists but only supports summarize/tag/score — no chat or briefs.

This milestone turns AI from a bolt-on feature into the core differentiator: three pricing tiers, streaming chat, an MCP server for Claude Desktop integration, smarter content generation, and a learning intelligence layer.

## Three-Tier AI Model

Every tier has **full feature parity** — summarize, key points, score, chat, briefs, batch enrichment, auto-tag, suggested questions. The difference is where inference runs, not what features are available.

### Tier 1: On-Device (Free)

- **Inference**: FoundationModels (iOS 26+ / macOS 26+)
- **Network**: Results sync to server after generation (POST enrichment results to Workers for storage)
- **Chat**: Multi-turn conversation using FoundationModels session (new capability to build)
- **Briefs**: Generated locally from cached articles, synced to server
- **Availability**: `SystemLanguageModel.default.availability == .available`
- **Fallback**: If device model unavailable, gracefully show "On-device AI not available on this device" — no silent degradation to cloud
- **Cost to operator**: $0

### Tier 2: BYOK (Free to operator)

- **Inference**: Server-proxied — app sends API key in `x-user-api-key` / `x-user-api-provider` headers, Workers proxies to Anthropic/OpenAI
- **Chat**: Streaming via SSE through Workers
- **Batch enrichment**: User-initiated "Enrich All" while app is open
- **Rate limits**: None (user's key, user's bill)
- **Cost to operator**: Workers compute only (~$0)

### Tier 3: Subscription (Paid via StoreKit 2 IAP)

- **Inference**: Server-side using platform API keys
- **Chat**: Streaming via SSE through Workers
- **Background enrichment**: Auto-summarize on feed poll (server-side cron)
- **Scheduled briefs**: Push notifications with morning/evening briefs
- **Rate limits**: Daily/weekly token budgets per subscription tier
- **Overages**: Opt-in at API cost + 10%; user can disable overages for hard cap
- **Billing**: StoreKit 2 with server-side receipt validation

### Tier Resolution (iOS)

The `AIGenerationCoordinator` currently selects engines via `AppSettings.automaticAIMode`. This extends to a unified tier resolver:

```
1. Check user's selected tier preference in Settings
2. If "on-device": check FoundationModels availability → use or show unavailable message
3. If "byok": check Keychain for API key → use or prompt to add key
4. If "subscription": check StoreKit entitlement → use or show subscription upsell
5. If no explicit preference: auto-detect (BYOK key exists? → byok. Subscription? → subscription. Device capable? → on-device. Otherwise → no AI)
```

### Tier Resolution (Workers)

```
1. Check x-user-api-key header → BYOK (proxy to provider, no rate limit)
2. Check subscription entitlement (via receipt validation or cached entitlement in D1) → subscription (use platform key, enforce rate limit)
3. Check x-on-device-result header → store result only (no AI call needed)
4. No tier → return 403 with tier_required error + available options
```

---

## Phase A: Infrastructure

### A1: Streaming Pipeline

**Workers (SSE endpoint):**
- New streaming variant of `runChat()` in `src/lib/ai.ts` that returns a `ReadableStream` instead of awaiting the full response
- For Anthropic: use streaming API (`stream: true`) which returns SSE chunks with `content_block_delta` events
- For OpenAI: use streaming API (`stream: true`) which returns SSE chunks with `choices[0].delta.content`
- Normalize both providers into a common SSE format: `data: {"type":"delta","content":"word "}\n\n` and `data: {"type":"done","usage":{...}}\n\n`
- Chat routes (`/chat/:articleId` and `/chat/multi`) get new `?stream=true` query param — when set, return SSE instead of JSON
- Workers returns `Content-Type: text/event-stream` with `Transfer-Encoding: chunked`

**iOS (URLSession streaming):**
- New `StreamingChatService` that uses `URLSession.bytes(for:)` to consume SSE
- Parse SSE lines (`data: {...}`) incrementally
- Publish deltas via `AsyncStream<ChatDelta>` where `ChatDelta` is `.text(String)` | `.done(usage: TokenUsage)`
- Chat views subscribe to the stream and append text incrementally with animation
- Error mid-stream: show partial response with "Response interrupted" indicator

**Files to modify:**
- `src/lib/ai.ts` — add `runChatStreaming()` returning `ReadableStream`
- `src/routes/chat.ts` — add `?stream=true` support to both chat endpoints
- New: `NebularNews/Services/StreamingChatService.swift`
- Modify: `CompanionArticleChatView.swift`, `MultiArticleChatView.swift` — consume stream

### A2: Metering & Rate Limiting

**Token tracking (Workers):**
- After every AI call (streaming or not), record usage to `ai_usage` table
- Fields: `user_id`, `provider`, `model`, `tokens_input`, `tokens_output`, `endpoint` (which route), `is_byok` (boolean), `created_at`
- For streaming: capture usage from the final `done` event
- New helper: `recordUsage(db, userId, provider, model, usage, endpoint, isByok)` called at end of every AI route

**Budget enforcement (Workers):**
- New middleware or helper: `checkBudget(db, userId, tier)` called before AI calls for subscription users
- Queries `ai_usage` for rolling window (daily sum, weekly sum)
- Compares against tier limits stored in `subscription_tiers` table
- If over budget and overages disabled: return 429 with `budget_exceeded` error + reset time
- If over budget and overages enabled: allow but flag as overage in usage record
- BYOK users: skip budget check entirely
- On-device result storage: skip budget check (no AI call on server)

**Subscription tiers table (D1):**
```sql
CREATE TABLE subscription_tiers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,           -- 'basic', 'pro'
  daily_token_limit INTEGER,    -- daily input+output token budget
  weekly_token_limit INTEGER,   -- weekly input+output token budget
  features_json TEXT,           -- JSON array of enabled features
  price_monthly_cents INTEGER,
  created_at INTEGER NOT NULL
);
```

**Usage dashboard (iOS):**
- New section in Settings: "AI Usage"
- Shows: tokens used today / daily limit, tokens used this week / weekly limit
- Bar chart or progress ring visualization
- "Manage Subscription" link → StoreKit subscription management
- For BYOK: show usage stats but no limits
- For on-device: show "Using on-device AI — no usage limits"

**Files to modify:**
- `src/lib/ai.ts` — add `recordUsage()` call after every `runChat()` / `runChatStreaming()`
- `src/routes/enrich.ts`, `src/routes/chat.ts`, `src/routes/brief.ts` — add budget checks
- New: `src/lib/rate-limiter.ts` — `checkBudget()`, `recordUsage()`
- New: `src/routes/usage.ts` — GET `/usage/summary` (daily/weekly stats)
- New migration: subscription_tiers table + seed data
- New: iOS Settings "AI Usage" section

### A3: StoreKit 2 IAP

**Subscription products:**
- Two tiers initially: "NebularNews AI Basic" and "NebularNews AI Pro"
- Monthly auto-renewable subscriptions
- Defined in App Store Connect, fetched via `Product.products(for:)`

**iOS implementation:**
- New: `SubscriptionManager` (actor) in NebularNewsKit
  - `availableProducts: [Product]`
  - `currentEntitlement: SubscriptionTier?`
  - `purchase(product:)` — initiates StoreKit 2 purchase flow
  - `restorePurchases()` — restore on new device
  - `listenForTransactions()` — `Transaction.updates` async sequence for renewals/cancellations
  - On successful purchase: POST receipt to Workers for server-side validation

**Server-side validation (Workers):**
- New route: POST `/subscription/verify` — receives App Store receipt/transaction, validates with Apple's App Store Server API
- Stores entitlement in D1: `user_subscriptions` table with `user_id`, `tier`, `expires_at`, `transaction_id`
- Cron or on-demand: check for expired subscriptions, downgrade tier
- AI routes check `user_subscriptions` when resolving tier

**Files to create:**
- `NebularNewsKit/Sources/NebularNewsKit/Subscription/SubscriptionManager.swift`
- `NebularNewsKit/Sources/NebularNewsKit/Subscription/SubscriptionTier.swift`
- `src/routes/subscription.ts` — verify receipt, check entitlement
- New migration: `user_subscriptions` table

### A4: On-Device Pipeline Extension

**Extend `ArticleGenerationEngine` protocol:**
```swift
// Add to existing protocol:
func generateChat(
    messages: [ChatMessage],
    articleContext: ArticleSnapshot?
) async throws -> ChatGenerationOutput

func generateBrief(
    articles: [ArticleSnapshot],
    settings: BriefSettings
) async throws -> BriefGenerationOutput
```

**FoundationModelsEngine additions:**
- `generateChat()`: Use `LanguageModelSession` with conversation history. System prompt matches server-side expert analyst prompt. Returns full response (no streaming for on-device — FoundationModels doesn't support SSE).
- `generateBrief()`: Takes cached articles, generates structured brief with bullets + source article IDs. Same prompt structure as server-side `buildNewsBriefPrompt()`.

**Result sync to server:**
- After on-device generation, POST results to new Workers endpoint: `POST /sync/enrichment`
- Payload: `{ article_id, type (summary|key_points|score|chat_message|brief), result, provider: "foundation_models", model: "system" }`
- Workers stores in same tables as server-generated results — no distinction in storage
- Sync is fire-and-forget (don't block UI on sync success)

**Files to modify:**
- `NebularNewsKit/.../GenerationTypes.swift` — extend protocol with chat + brief methods
- `NebularNewsKit/.../FoundationModelsEngine.swift` — implement chat + brief
- `NebularNewsKit/.../AnthropicGenerationEngine.swift` — implement chat + brief (for consistency)
- `NebularNewsKit/.../AIGenerationCoordinator.swift` — route chat/brief through tier resolver
- New: `src/routes/sync.ts` — POST `/sync/enrichment` endpoint

### A5: Retry & Reliability

**Workers retry logic:**
- Wrap AI calls in retry helper: `withRetry(fn, { maxAttempts: 3, backoff: 'exponential', initialDelay: 1000 })`
- On provider failure: try fallback provider if available (Anthropic → OpenAI or vice versa)
- Record failed attempts in `ai_usage` with `status: 'failed'`
- For enrichment jobs: track attempt count, don't retry after 3 failures

**iOS error handling:**
- On streaming error mid-response: show partial response + "Response was interrupted. Tap to retry."
- On budget exceeded: show tier upgrade prompt
- On no AI tier: show onboarding to select a tier
- On network failure: queue for retry when connection restored (for enrichment, not chat)

**Files to modify:**
- New: `src/lib/retry.ts` — `withRetry()` helper
- Modify all AI routes to use retry wrapper
- Modify iOS chat views for error recovery UI

---

## Phase B: MCP Server

### B1: Streamable HTTP Transport

**Implementation on Workers:**
- New route group: `/mcp/*` — handles MCP protocol over Streamable HTTP
- POST `/mcp` — receives JSON-RPC requests, returns JSON-RPC responses
- Supports `initialize`, `tools/list`, `tools/call`, `resources/list`, `resources/read`
- Auth: Bearer token in Authorization header (same as all other API routes)
- Use the `@modelcontextprotocol/sdk` TypeScript package for protocol handling if it supports Workers, otherwise implement the JSON-RPC layer directly (it's straightforward)

**Files to create:**
- `src/routes/mcp.ts` — MCP route handler
- `src/mcp/tools.ts` — tool definitions and handlers
- `src/mcp/resources.ts` — resource definitions and handlers

### B2: MCP Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `search_articles` | Full-text search across user's articles | `query: string`, `limit?: number`, `feed_id?: string` |
| `get_article` | Get full article content + enrichment | `article_id: string` |
| `get_brief` | Get latest news brief or generate one | `generate?: boolean` |
| `list_feeds` | List user's feed subscriptions | `include_paused?: boolean` |
| `ask_about_news` | Ask a question about recent articles (multi-article chat) | `question: string` |
| `get_trending_topics` | Topics trending in user's feeds | `window_hours?: number` |
| `get_article_summary` | Get or generate summary for an article | `article_id: string` |
| `save_article` | Save/bookmark an article | `article_id: string` |

Each tool handler reuses existing route logic — `search_articles` calls the same FTS5 query as the articles search endpoint, `ask_about_news` uses the same multi-chat context assembly as `/chat/multi`, etc.

### B3: MCP Resources

| Resource URI | Description |
|-------------|-------------|
| `nebularnews://feeds` | User's feed list as OPML |
| `nebularnews://articles/recent` | Last 20 articles with titles, scores, summaries |
| `nebularnews://brief/latest` | Most recent news brief |
| `nebularnews://reading-history` | Recent reading activity |

Resources return structured text that Claude can use as context without making tool calls.

### B4: User Setup Flow

- In iOS Settings: new "Integrations" section
- "Connect to Claude Desktop" — generates a config snippet the user can copy:
  ```json
  {
    "mcpServers": {
      "nebularnews": {
        "url": "https://api.nebularnews.com/mcp",
        "headers": {
          "Authorization": "Bearer <session-token>"
        }
      }
    }
  }
  ```
- Show instructions for pasting into Claude Desktop config
- Session token is the same Bearer token used for all API calls
- Token refresh: if session expires, user regenerates from iOS app

---

## Phase C: Chat & Content

### C1: Streaming Chat

- Wire up the SSE infrastructure from Phase A into the existing chat views
- `CompanionArticleChatView` and `MultiArticleChatView` switch to `StreamingChatService`
- Words animate in as they arrive (character-by-character or word-by-word)
- Typing indicator replaced by actual streaming text
- Model attribution shown after response completes
- On-device chat: not streamed (FoundationModels returns full response), but displayed with a typewriter animation for consistency

### C2: Conversation Memory

- Currently: each article chat is isolated, multi-chat has no memory
- New: optional "conversation memory" that carries context across article chats
- Implementation: When user chats about Article B after chatting about Article A, include a summary of the Article A conversation in the context
- Workers: new `chat_context_summaries` table — after each chat, generate a 2-sentence summary of the conversation, store it per user
- Context assembly: include last 3 conversation summaries in system prompt as "Previous discussions"
- User can toggle this off in Settings ("Cross-article memory")

### C3: Follow-Up Suggestions

- After each AI chat response, generate 2-3 follow-up questions
- Implementation: append a hidden instruction to the system prompt: "After your response, suggest 2-3 follow-up questions on new lines prefixed with '>>'"
- Parse suggestions from response, display as tappable pills below the message
- Reuse the existing suggested-questions UI pattern from `CompanionArticleChatView`

### C4: Brief 2.0

- **Scheduled briefs**: Workers cron checks `user_settings.news_brief_morning_time` / `evening_time`, generates brief at those times, sends push notification
- **Per-topic briefs**: User can configure briefs for specific tags/topics, not just "all news"
- **Configurable depth**: "Headlines only" (3 words per bullet), "Summary" (current), "Deep dive" (paragraph per story)
- **On-device briefs**: For on-device tier, iOS generates brief locally from cached articles and syncs to server

### C5: Auto & Batch Enrichment

- **Auto-enrichment (subscription tier)**: After feed poll cron fetches new articles, automatically run summarize + key-points + auto-tag for subscribers. Respects token budget.
- **Batch enrichment (BYOK)**: New "Enrich All" button in article list toolbar. Sends batch request to Workers: `POST /enrich/batch` with array of article IDs. Server processes sequentially using user's BYOK key. Returns results as they complete (SSE stream of enrichment results).
- **Configurable summary style**: Wire `summaryStyle` setting (concise/detailed/bullet) and `summaryLength` (short/medium/long) through to the prompt builder. Currently hardcoded.

---

## Phase D: Intelligence

### D1: Topic Clustering

- After auto-tag runs on articles, group articles by shared tags into topic clusters
- New D1 table: `topic_clusters` — `id`, `user_id`, `name`, `tag_ids_json`, `article_count`, `latest_article_at`, `created_at`
- Workers cron (daily): scan recent articles, identify tag co-occurrence patterns, create/update clusters
- iOS: new "Topics" section in dashboard showing active clusters with article counts
- Tapping a cluster shows filtered article list

### D2: Trend Detection

- Compare topic cluster activity over rolling windows (24h vs 7d)
- If a cluster's article count in 24h exceeds its 7d daily average by 2x+, mark as "trending"
- New D1 table: `topic_trends` — `cluster_id`, `trend_score`, `window_start`, `window_end`
- iOS: "Trending" badge on topic clusters, optional "Trending Topics" card on dashboard
- Push notification option: "Alert me when a topic trends"

### D3: Scoring v2

- Extend the 4-signal algorithmic scoring with behavioral signals:
  - **Read depth**: How far user scrolled (% of article read) — tracked client-side, synced to server
  - **Time spent**: Reading duration per article — already partially tracked
  - **Save rate**: User's save ratio for articles from this feed/topic
  - **Dismiss rate**: How often user dismisses articles from this feed/topic
- These become signals 5-8 in the weighted scoring formula
- AI scoring prompt updated to include behavioral profile alongside preference profile
- Scoring cron incorporates new signals into algorithmic pass

### D4: Reading Insights

- Weekly digest of reading patterns, generated by AI
- Data inputs: articles read, time spent, topics, feeds, scores, save/dismiss ratios
- Workers endpoint: `GET /insights/weekly` — generates or returns cached weekly insight
- iOS: new "Reading Insights" card on dashboard (weekly)
- Content: "You read 23 articles this week, mostly about AI (45%) and climate (20%). You're spending more time on long-form pieces from Ars Technica."

---

## Verification Plan

### Phase A
- [ ] Streaming: Send a chat message, verify words appear incrementally in the chat view
- [ ] Metering: After AI calls, verify `ai_usage` table has correct token counts
- [ ] Rate limiting: Set a low daily budget, exhaust it, verify 429 response
- [ ] StoreKit: Test subscription purchase in sandbox, verify entitlement stored in D1
- [ ] On-device chat: On iOS 26+ simulator/device, verify FoundationModels chat works and results sync to server
- [ ] Retry: Kill network mid-enrichment, verify retry succeeds on reconnect

### Phase B
- [ ] MCP: Configure Claude Desktop with NebularNews MCP server, verify `search_articles` returns results
- [ ] MCP: Ask Claude Desktop "What's in my news today?" — verify it calls `get_brief` or `ask_about_news`
- [ ] MCP: Verify auth works (invalid token gets rejected)

### Phase C
- [ ] Streaming chat: Full end-to-end — send message, see streaming response, see follow-up suggestions
- [ ] Brief 2.0: Configure morning brief, verify push notification arrives with brief content
- [ ] Batch enrichment: BYOK user taps "Enrich All" on 10 articles, verify all get summarized

### Phase D
- [ ] Topic clusters: After enough articles are tagged, verify clusters appear on dashboard
- [ ] Trending: Simulate burst of articles in one topic, verify trend detection triggers
- [ ] Scoring v2: Read several articles deeply, verify scores adjust for similar content
- [ ] Insights: Verify weekly reading insights generate and display correctly

### Build verification
- iOS: `xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
- Workers: `cd /Users/tfinklea/git/nebularnews && npx wrangler deploy --env production`

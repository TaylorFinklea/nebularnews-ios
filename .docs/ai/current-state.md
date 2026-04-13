# Current State (2026-04-12)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## M6: AI Overhaul — In Progress

### Phase A: Infrastructure (COMPLETE)
- **A1 Streaming**: SSE streaming on Workers (`runChatStreaming` in ai.ts) + `StreamingChatService.swift` on iOS using `URLSession.bytes`. Chat views render incrementally.
- **A2 Metering**: `rate-limiter.ts` with `recordUsage()` and `checkBudget()`. `ai_usage` table extended with `endpoint` and `is_byok` columns. `subscription_tiers` and `user_subscriptions` tables created. Usage route at `GET /usage/summary`.
- **A3 StoreKit 2**: `SubscriptionManager` actor in NebularNewsKit (product loading, purchase, restore, transaction listener). `SubscriptionTier` enum. Server-side verification at `POST /subscription/verify`.
- **A4 On-Device Pipeline**: `ArticleGenerationEngine` protocol extended with `generateChat()` and `generateBrief()`. All three engines (FoundationModels, Anthropic, OpenAI) implement them. Sync route at `POST /sync/enrichment`.
- **A5 Retry**: `withRetry()` in `retry.ts` with exponential backoff + jitter, integrated into `runChat()`.

### Phase B: MCP Server (COMPLETE)
- **8 tools**: search_articles, get_article, get_brief, list_feeds, ask_about_news, get_trending_topics, get_article_summary, save_article
- **4 resources**: nebularnews://feeds, articles/recent, brief/latest, reading-history
- **Transport**: JSON-RPC 2.0 over POST `/mcp` with Bearer token auth
- Config snippet for Claude Desktop available

### Phase C: Chat & Content (COMPLETE)
- **C1 Streaming Chat**: Done in A1 — views already use SSE
- **C2 Conversation Memory**: `chat_context_summaries` table, last 3 summaries injected into system prompt
- **C3 Follow-up Suggestions**: AI appends `>>` prefixed questions, parsed and shown as tappable pills
- **C5 Batch Enrichment**: `POST /enrich/batch` with SSE stream of results for BYOK users

### Phase D: Intelligence (COMPLETE)
- **D1 Topic Clustering**: `topic_clusters` table, daily cron groups articles by tag
- **D2 Trend Detection**: `topic_trends` table, 24h vs 7d comparison, trending badge
- **D3/D4 Insights**: `GET /insights/topics`, `/insights/trending`, `/insights/weekly` endpoints
- Intelligence cron runs daily at 3:30 AM alongside cleanup

## What Needs Testing
- Streaming chat end-to-end (set AI provider keys first)
- MCP server with Claude Desktop
- Batch enrichment flow
- StoreKit 2 in sandbox
- Follow-up suggestion parsing
- Topic clustering after enough articles are tagged
- Run migration 0002, 0003, 0004 on D1

## Migrations Pending Deployment
- `0002_subscriptions_and_metering.sql` — subscription_tiers, user_subscriptions, ai_usage columns
- `0003_conversation_memory.sql` — chat_context_summaries
- `0004_intelligence_layer.sql` — topic_clusters, topic_trends, reading_insights

## Recent Commits (this session)
### nebularnews (Workers)
- SSE streaming for chat endpoints
- Metering, rate limiting, subscription tiers
- MCP server (8 tools, 4 resources)
- Subscription verification endpoints
- Enrichment sync endpoint
- Retry logic
- Conversation memory + follow-up suggestions
- Batch enrichment endpoint
- Intelligence cron + insights routes

### nebularnews-ios
- StreamingChatService (SSE consumer)
- Streaming chat views (article + multi)
- StoreKit 2 SubscriptionManager + SubscriptionTier
- AI engine protocol extensions (chat + brief)
- Follow-up suggestion pills

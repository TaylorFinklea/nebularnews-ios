# Plan: M11 — AI Assistant Direct Actions

## Context

Today the floating AI assistant is read-only conversational: ask a question, get a markdown answer with article pills + suggested follow-ups. Every action the user wants to take afterward (mark read, apply tag, open article, change filter, subscribe, raise the daily cap on a noisy feed) requires them to leave the chat, navigate, and tap. The chat already receives rich `AIPageContext` per surface — it knows what the user is looking at — but the assistant can only *talk about* state, never *change it*.

M11 is the bridge: tool-calling. The model gets a small registry of named tools, calls them when appropriate, and the iOS client either renders the result inline ("Marked 12 articles as read") or executes the action locally (open article, change filter). M6 already shipped the MCP server with 8 tools for external clients (Claude Desktop) — M11 reuses that contract for the in-app chat and adds the mutation + navigation tools that didn't make sense for a remote client.

**Why now**: The single biggest UX gap is "I asked the AI about something useful — why can't it just do it?" Per next-steps.md, this is the next slated milestone after M10 (which is shipped). The roadmap calls it `M11: AI assistant direct actions (tool-calling: filter articles, navigate, apply tags)`.

---

## Strategy

Two layers of tools, dispatched through one chat-endpoint loop:

1. **Server-side tools** (data + mutations): backend executes, returns result to the model, model produces final text + a confirmation segment for the UI.
2. **Client-side tools** (navigation + view state): backend returns the tool-call intent verbatim; iOS executes it locally (deep link, change filter binding, etc.).

The chat endpoint enforces a hard tool-call loop limit (3 rounds) to prevent runaway loops eating BYOK tokens. The model registry is small and curated — no dynamic tool registration.

---

## Scope

### Tier 1 — Must ship

**Backend (`/Users/tfinklea/git/nebularnews`):**
- Extend `runChat()` in `src/lib/ai.ts` to accept `tools: ToolDefinition[]` and return a discriminated union (`{ kind: 'message'; content; usage }` | `{ kind: 'toolCalls'; calls: [...]; usage }`). Wire the `tools` parameter through both `callOpenAI()` and `callAnthropic()`. Parse `tool_calls` (OpenAI) and `content[].type == 'tool_use'` (Anthropic).
- Add a `chat-tools.ts` registry in `src/lib/` exposing the tools in two banks:
  - Server-executed: `mark_articles_read`, `set_article_reaction`, `apply_tag_to_article`, `set_feed_max_per_day`, `pause_feed`, plus reuse of MCP `search_articles`, `list_feeds`, `get_trending_topics` (call into existing MCP tool handlers in `src/mcp/tools.ts:11-104` — refactor those handlers into a shared module so both MCP and chat can call them without duplication).
  - Client-executed (returned to iOS without server execution): `open_article`, `set_articles_filter`, `navigate_to_tab`, `generate_brief_now`.
- Update `POST /chat/assistant` in `src/routes/chat.ts:739` to:
  - Pass the registered tools to `runChat()`.
  - When response is `kind: 'toolCalls'`, execute server-side calls inline, append results as tool-role messages, recurse (max 3 rounds), and forward client-side calls to the SSE stream.
  - Persist tool-call sequences alongside the assistant message.
- Migration `0010_chat_tools.sql`: add `tool_calls_json TEXT` column to `chat_messages`. Nullable, so old rows are unaffected.
- New SSE event types in the existing stream: `tool_call_server` (for the UI to render a confirmation segment), `tool_call_client` (for iOS to execute locally).
- Loop guard: counter on the request context; break and return whatever text the model has produced after 3 rounds. Surface as a `tool_loop_limit` error code if no text was produced.
- BYOK + budget enforcement: each tool call still records token usage via `recordUsage()` (`src/lib/rate-limiter.ts`); short-circuit if budget exceeded mid-loop.

**iOS (`/Users/tfinklea/git/nebularnews-ios`):**
- Extend `AssistantContentSegment` (`Features/AIAssistant/`) with two new cases:
  - `.toolResult(name: String, summary: String, succeeded: Bool)` — rendered as a small inline chip ("Marked 12 articles as read", "Applied 'tech' tag to article", "Couldn't change filter — feed not found").
  - `.pendingClientAction(ToolCall)` — internal only, dispatched to the action handler before being replaced by `.toolResult` once executed.
- Extend `StreamingChatService.performAssistantStream()` (`Services/StreamingChatService.swift:41`) to parse the new SSE event types and yield `ChatDelta.toolResult(...)` / `ChatDelta.clientAction(...)` deltas.
- New `Services/AssistantActionDispatcher.swift` — single entry point that maps client-side tool names to actions:
  - `open_article` → `DeepLinkRouter.handle(URL("nebularnews://article/{id}"))`
  - `navigate_to_tab` → mutate `MainTabView.selectedTab` via `appState`
  - `set_articles_filter` → mutate `CompanionArticleFilter` via a new `appState.pendingArticlesFilter` published binding (CompanionArticlesView reads + clears on receipt)
  - `generate_brief_now` → set `appState.pendingBriefGeneration = true`; CompanionTodayView observes and triggers `generateBrief()` next render
- Update `AIAssistantCoordinator` to invoke `AssistantActionDispatcher` for client-side calls and append `.toolResult` segments for confirmations.
- Update `AssistantChatBubble` to render the new segment types (chip styling, success/failure color).

### Tier 2 — Stretch

- **Confirm-before-mutate** sheet for destructive actions (`mark_articles_read` for >5 articles, `pause_feed`, `unsubscribe_from_feed`). Backend returns a `requires_confirmation` flag; iOS shows a native `.confirmationDialog` before executing.
- **Tool-call analytics**: admin dashboard panel (`Features/Admin/`) showing call counts per tool, success rate, average latency. Reads from `tool_calls_json` aggregated.
- **`subscribe_to_feed`** server-side tool — needs URL normalization + `FeedURLNormalizer`-equivalent on the server. Adds first-time-feed flow inside chat ("Subscribed to Hacker News — capping at 10/day given your other subscriptions").

### Explicitly out of scope

- Free-form code execution / arbitrary SQL.
- Tools that touch other users' data (admin-style cross-user tools).
- Tools that send notifications, email, or external HTTP calls beyond Steel/Browserless (already gated behind the deep-fetch endpoint).
- Persistent tool-result audit log (rely on `chat_messages.tool_calls_json` for now).
- On-device model tool-calling (FoundationModels engine doesn't support it cleanly yet — server only).
- Reasoning-model multi-step planning (Anthropic extended thinking, OpenAI o-series).

---

## Critical files

**Backend (`/Users/tfinklea/git/nebularnews`):**
- `src/lib/ai.ts` — extend `runChat`, `callOpenAI`, `callAnthropic` for tools
- `src/lib/chat-tools.ts` — **new** — tool registry + server-side execution dispatcher
- `src/mcp/tools.ts` — **refactor** — extract handler bodies (`searchArticlesHandler`, `listFeedsHandler`, etc.) into a shared module so chat-tools.ts can call them without duplication
- `src/routes/chat.ts:739` — wire tools, run loop, emit new SSE event types
- `src/lib/rate-limiter.ts` — extend for per-tool-call budget short-circuit
- `migrations/0010_chat_tools.sql` — **new** — `ALTER TABLE chat_messages ADD COLUMN tool_calls_json TEXT`

**iOS (`/Users/tfinklea/git/nebularnews-ios`):**
- `NebularNews/NebularNews/Features/AIAssistant/AssistantContentSegment.swift` (or wherever the enum lives) — add `.toolResult`, `.pendingClientAction`
- `NebularNews/NebularNews/Services/StreamingChatService.swift:41` — handle new SSE event types
- `NebularNews/NebularNews/Services/AssistantActionDispatcher.swift` — **new** — client-side tool dispatch
- `NebularNews/NebularNews/Features/AIAssistant/AIAssistantCoordinator.swift` — wire dispatcher
- `NebularNews/NebularNews/Features/AIAssistant/AssistantChatBubble.swift` — render new segments
- `NebularNews/NebularNews/App/AppState.swift` — add `pendingArticlesFilter`, `pendingBriefGeneration` published bindings for cross-view dispatch
- `NebularNews/NebularNews/Features/Companion/CompanionArticlesView.swift` — observe `pendingArticlesFilter`, apply + clear
- `NebularNews/NebularNews/Features/Companion/CompanionTodayView.swift` — observe `pendingBriefGeneration`, trigger generateBrief

---

## Verification

1. **Backend unit test path**: `wrangler dev`, then `curl POST /chat/assistant` with a prompt like "mark all my newsletter articles as read" and confirm:
   - Response contains a `tool_call_server` SSE event with `mark_articles_read` + count.
   - `chat_messages.tool_calls_json` has the recorded tool call.
   - Hitting the endpoint twice in a row stays under 3 loop rounds (no recursion blowup).
2. **iOS unit-of-work**: open a feed, ask the AI "open the first article" → article detail pushes onto the stack via deep link (no network roundtrip on the iOS side beyond the chat call itself).
3. **Mutation correctness**: ask "tag this article 'evergreen'" on an article detail page → tag appears in `tags[]` of the article model + persists to `article_tags` server-side (verify via `GET /articles/:id`).
4. **Loop guard**: prompt-engineer the model into a tool-call loop (e.g., "keep calling search_articles until you find one about quantum computing") → confirm response cuts off at round 3 with `tool_loop_limit` warning surfaced inline.
5. **Streaming UX**: tool result chips appear immediately when emitted (before final text), final text streams in below them. No flicker, no out-of-order rendering.
6. **Build matrix**: both iOS Simulator and macOS builds clean.

---

## Risks & open questions

- **Provider tool-calling shape divergence**: OpenAI returns `tool_calls` in a discrete message; Anthropic interleaves `tool_use` blocks within `content[]`. The `runChat` return shape needs to normalize both. Spend time on the abstraction up-front; messy now = endless followups later.
- **MCP tool handler refactor scope**: `src/mcp/tools.ts` currently couples handler logic with MCP request/response shape. Extracting handlers into pure functions is a medium-sized refactor — we already touched this file in the audit fix. Risk: regressing the MCP server. Mitigation: leave the MCP entrypoints untouched, just extract the inner `dbAll`/`dbGet` call sequences into `src/lib/article-actions.ts` etc., and have both MCP and chat-tools wrap them.
- **`set_articles_filter` cross-tab dispatch**: if user is on Today and asks "show me unread tech articles", we need to switch tabs *and* set the filter. Order matters — set the filter first, then navigate, so the destination view renders with the new filter on first paint.
- **BYOK pricing visibility**: tool-calling roughly doubles tokens (function definitions take ~50–200 tokens each, plus tool result roundtrips). Consider showing a subtle "1 tool call" indicator alongside the existing token count in the chat footer.
- **Confirm-before-mutate boundary**: which mutations are destructive enough to require confirmation? Initial line: anything affecting >5 records or that the user can't easily undo (`mark_articles_read` bulk, `unsubscribe`). Single-article mutations (set reaction, apply tag) feel fine without a prompt.
- **Stale `pendingArticlesFilter`**: if the user dismisses the chat after the AI sets a filter, the filter is now active without an obvious trigger. Surface a brief banner ("AI applied filter: unread + tag: tech · Reset?") in `CompanionArticlesView` when the filter was AI-set.

---

## Follow-up (not this milestone)

- On-device tool execution via `FoundationModels` (Apple Intelligence) — needs Apple to ship native function-calling. Not on the public roadmap as of session date.
- Multi-step planner mode using Anthropic extended thinking / OpenAI o-series for complex requests ("clean up my feeds — pause anything that hasn't published in 30 days and cap noisy feeds at 10/day").
- Cross-session memory of user preferences ("you usually ask me to summarize Anthropic articles → auto-summarize newly arrived ones").
- Voice input → tool-call ("hey assistant, mark all newsletter stuff as read") via SiriKit shortcuts or AppIntents.

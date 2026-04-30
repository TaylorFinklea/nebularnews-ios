# AI Mutation Guardrails (sparkle assistant)

> M11 Tier 2 — destructive-tool confirm + undo-chip with per-tool policy.
> Spec date: 2026-04-29.

## Product Overview

The sparkle AI assistant ships destructive tool calls today (mark_articles_read, pause_feed, set_feed_max_per_day, set_feed_min_score, unsubscribe_from_feed) but has only one safety net: an Undo button on the result chip. That covers most accidental small-blast-radius mutations, but two product issues remain:

1. **Bulk reads and feed pauses feel unsafe**: a user typing "mark everything stale as read" can flip 200 articles before the chip renders, and the undo button isn't always reliable if the chat sheet is dismissed mid-stream.
2. **Different users want different defaults**: power users want chip + undo (low friction); cautious users want a confirmation sheet for anything that touches more than one record. Today it's one-size-fits-all.

This phase ships **both** UI patterns and a **per-tool policy** in Settings so users opt into the cadence they want. Defaults err on the side of friction — "Confirm" is the out-of-the-box value for every destructive tool.

**User-facing wins**

- Confirmation sheet shows exactly what is about to happen ("Mark 47 articles as read in Hacker News, This Week in Rust, …") and surfaces the conversational context that triggered it.
- Undo chip becomes a real promise — it stays anchored even if the chat sheet closes, with a visible 7-second countdown.
- New Settings → Advanced → AI Guardrails screen lets the user lower friction per-tool when they trust the AI for that specific action.

**Out of scope**

- Cross-device policy sync (per-tool policy is local UserDefaults; sync is a follow-up if users complain).
- New destructive tools beyond the five named below.
- Replacing the existing chip-with-undo system for non-destructive tools (apply_tag, set_article_reaction, save_articles, etc. — those keep their current behavior).
- Voice / Siri integration.

## Current State

### Backend (`/Users/tfinklea/git/nebularnews`)

- Tool registry: `src/lib/chat-tools.ts` defines `SERVER_TOOLS` and `CLIENT_TOOLS`. Server tools are executed inline in the SSE round loop.
- Destructive server tools currently in `SERVER_TOOLS`:
  - `mark_articles_read` (`chat-tools.ts:64-74`)
  - `set_feed_max_per_day` (`chat-tools.ts:122-133`)
  - `pause_feed` (`chat-tools.ts:134-145`)
  - `subscribe_to_feed` (`chat-tools.ts:146-157`) — destructive in the sense that it can flip a `rss_only` feed to `auto_fetch_on_empty` and add an entry to the user's subscription list.
- **`set_feed_min_score` does NOT yet exist** as a server tool. It is named in the user's product brief — the spec adds it. iOS already exposes a `min_score` knob on `user_feed_subscriptions` (it's a column in D1 `user_feed_subscriptions`).
- **`unsubscribe_from_feed` does NOT yet exist** as a server tool. It is named in the user's product brief. iOS has `SyncManager.unsubscribeFeed(feedId:)` (queue type `unsubscribe_feed`) used by the swipe-to-delete row in `CompanionFeedsView`. Backend exposes `DELETE /feeds/:id` (`feeds.ts:133`). The spec adds the server tool wrapper.
- Inline execution flow (`src/routes/chat.ts:1054-1098`):
  1. `streamChatWithTools()` yields a `done` event with the AI's tool-use blocks.
  2. For each call, `executeServerTool(call, toolCtx)` runs the mutation immediately.
  3. SSE emits `tool_call_server` with `summary`, `succeeded`, and an optional `undo: { tool, args }` payload.
  4. The same loop continues for up to `MAX_TOOL_ROUNDS = 4` (`chat.ts:27`).
- Undo channel: `POST /chat/undo-tool` (`chat.ts:1245`) accepts `{ tool, args }` and dispatches `executeUndoTool` with the `UNDO_TOOL_NAMES` allowlist (`chat-tools.ts:261-270`). The undo args are minted server-side and round-tripped through iOS verbatim (base64-encoded JSON over SSE).
- `chat_messages.tool_calls_json` (migration `0010`) records the per-message tool log with `kind: 'server' | 'client'`, summary, succeeded, and undo payload.

### iOS (`/Users/tfinklea/git/nebularnews-ios`)

- SSE parser: `Services/StreamingChatService.swift:135-178` decodes `tool_call_server` into `ChatDelta.toolServerResult(name, summary, succeeded, undoTool, undoArgsB64)` and `tool_call_client` into `.toolClientCall(name, args)`.
- Client-side tool dispatch: `Services/AssistantActionDispatcher.swift` maps `open_article`, `navigate_to_tab`, `set_articles_filter`, `generate_brief_now` into `AppState` pending bindings (no destructive ones today).
- Coordinator: `Features/AIAssistant/AIAssistantCoordinator.swift:86-108` consumes the stream. On `.toolServerResult`, it appends a `[[tool:...]]` marker to `streamingContent`. On `.toolClientCall`, it dispatches and appends a chip.
- Chip renderer: `Features/AIAssistant/AssistantChatBubble.swift:93-117` shows a green/orange capsule with summary text and an inline "Undo" button when an `UndoPayload` is present. Undo POSTs to `/chat/undo-tool` (`AIAssistantCoordinator.swift:145-183`).
- Undo persistence: the chip lives only inside the chat transcript. If the user closes the assistant sheet (`AIAssistantSheetView`) before tapping Undo, the chip is still there next time the sheet opens — but there is no toast outside the sheet, no countdown, and tapping Undo only works if the chat sheet is presented (it's a SwiftUI button inside the bubble).
- Per-tool policy storage: nothing exists today. There is no AI-Guardrails screen in `Features/Settings/SettingsView.swift`.
- AppState (`App/AppState.swift`) holds `pendingTabSwitch`, `pendingArticlesFilter`, `pendingBriefGeneration`, `pendingArticleOpen`. These will gain a sibling for queued confirmation requests.

### Locked product decisions (do not re-litigate)

1. **Both UIs ship**: confirmation sheet AND undo chip with countdown.
2. **Per-tool policy in Settings → Advanced → AI Guardrails**: one toggle per destructive tool (`Confirm` vs `Undo only`).
3. **Defaults on a fresh install**: ALL destructive tools default to `Confirm`. The user opts INTO `Undo only` per tool.
4. **mark_articles_read threshold**: `Confirm` only when the AI proposes more than 5 article ids; smaller batches run immediately under the `Undo only` policy regardless of the user's setting (the threshold is hard-coded — small batches are always low-friction).
5. **Tools covered**: `unsubscribe_from_feed`, `mark_articles_read>5`, `pause_feed` (when the call would set `paused=true`; resume is non-destructive), `set_feed_max_per_day`, `set_feed_min_score`. `subscribe_to_feed` is NOT in this set — adding a feed is recoverable and low-blast-radius.

## Architecture

### The decisive question: when does the server-executed tool actually run?

Today, server tools run **inline** during the SSE round loop. By the time iOS sees `tool_call_server` over SSE, the D1 mutation has already happened. That makes a true "confirm before mutate" impossible without changing the protocol.

This spec resolves it by introducing a **two-phase tool-call protocol**:

```
Phase A: propose  → server announces "I'm about to run pause_feed(feed=X)"
                    via SSE event tool_call_propose, then PAUSES this turn.
                    The streaming connection stays open; the server holds the
                    `convo` array (assistant + tool_use block accumulated so
                    far) in memory keyed by a propose_id.
                    (Cloudflare Workers single-request lifetime constraint:
                    we can't pause forever — see "Hand-off / failure modes"
                    for the timeout strategy.)

Phase B: confirm  → iOS POSTs to /chat/confirm-tool with { propose_id,
                    decision: 'approve' | 'reject', edits?: { ... } }.
                    Server resumes: executes tool (or skips on reject),
                    re-enters the SSE loop with the result in `convo`,
                    streams the rest as today.
```

Because Workers requests are bounded and we don't want to hold a streaming response open through user think-time, the server **does not actually pause the original SSE connection** for confirm-required tools. Instead:

- For tools that the user has set to `Confirm` in Settings (or for `mark_articles_read` with >5 ids regardless of setting), the server emits `tool_call_propose` and **terminates the current SSE turn** (emits a `done` event with empty content, no tool execution).
- iOS shows the confirmation sheet. The user approves or rejects.
- iOS calls `POST /chat/confirm-tool` with the original propose payload. The server runs the tool and emits a fresh SSE response continuing the conversation (assistant follow-up text, more tool calls if any).
- iOS appends the new SSE stream to the existing transcript so it reads as one continuous turn.

This avoids long-lived Workers requests, persists state to D1 between phases, and keeps the existing SSE event vocabulary additive (one new event type, one new endpoint).

For the **`Undo only`** policy, the protocol is unchanged from today — server runs inline, emits `tool_call_server`, iOS shows the chip. The new wrinkle is iOS showing a **toast-style countdown anchor** that stays visible even after the chat sheet closes (5-7s window — see UI spec).

### Why not server-confirm-as-undo-window for everything?

We considered "no propose protocol — always run inline, always show a 7s undo countdown that the user can extend". Rejected because:

- For `unsubscribe_from_feed` and `mark_articles_read` >50, the side effects (lost article positions, lost saved state) can be expensive to recover even with undo (read-state restore is fine; subscription restore is fine; but if a poll-cron fires in the gap and re-fetches the feed that was deleted, we'd lose ordering / per-feed cap state).
- The user has explicitly asked for both UIs and per-tool choice. Forcing one is wrong.

### Why per-tool policy local-only?

`UserDefaults` (NOT Keychain — it's preference data, not secrets; not iCloud — sync isn't requested and would add a 1-2 day round-trip if a stale device cached the wrong policy). If users later ask for "I changed it on my phone, why doesn't my Mac know?" we can mirror to `/settings` server-side (the existing `CompanionSettingsPayload` already syncs per-user prefs).

## Backend Changes

### B1. Migration `0020_tool_call_proposals.sql`

```sql
-- Stores in-flight tool-call proposals awaiting user confirmation.
-- Rows are short-lived (TTL ~10 minutes); a daily cron evicts stale rows.
CREATE TABLE tool_call_proposals (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  thread_id TEXT NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
  tool_name TEXT NOT NULL,
  args_json TEXT NOT NULL,                  -- the full call.args JSON
  preview_summary TEXT NOT NULL,            -- e.g. "Mark 47 articles as read in 3 feeds"
  preview_detail_json TEXT NOT NULL,        -- richer payload for the sheet (article titles, feed name, before/after values)
  conversation_snapshot_json TEXT NOT NULL, -- the partial `convo` array up to and including the tool_use turn, so the server can resume
  provider TEXT NOT NULL,                   -- 'openai' | 'anthropic'
  model TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  resolved_at INTEGER,                      -- null until user confirms/rejects/expires
  resolution TEXT                           -- 'approved' | 'rejected' | 'expired'
);

CREATE INDEX idx_tool_call_proposals_user_active ON tool_call_proposals(user_id, resolved_at) WHERE resolved_at IS NULL;
CREATE INDEX idx_tool_call_proposals_created ON tool_call_proposals(created_at);
```

### B2. New server tools

Add to `SERVER_TOOLS` in `src/lib/chat-tools.ts`:

```ts
{
  name: 'unsubscribe_from_feed',
  description: 'Unsubscribe the user from a feed. Reversible via undo within the same session.',
  parameters: {
    type: 'object',
    properties: { feed_id: { type: 'string' } },
    required: ['feed_id'],
  },
},
{
  name: 'set_feed_min_score',
  description: 'Set the minimum article score for a feed subscription. Articles below this score are hidden from lists. Use 0 to disable.',
  parameters: {
    type: 'object',
    properties: {
      feed_id: { type: 'string' },
      min_score: { type: 'number', description: '0 = no filter, 1-100 inclusive' },
    },
    required: ['feed_id', 'min_score'],
  },
},
```

Implement `executeServerTool` cases:

- `unsubscribe_from_feed`: look up the existing `user_feed_subscriptions` row (capture for undo), DELETE the row, return undo `{ tool: 'undo_unsubscribe_from_feed', args: { feed_id, prior_paused, prior_max_per_day, prior_min_score } }`.
- `set_feed_min_score`: similar to `set_feed_max_per_day` — capture prior, UPDATE, return undo `{ tool: 'undo_set_feed_min_score', args: { feed_id, min_score: priorValue } }`.

Add to `UNDO_TOOL_NAMES`:

```ts
'undo_unsubscribe_from_feed',
'undo_set_feed_min_score',
```

Implement undo cases in `executeUndoTool`:

- `undo_unsubscribe_from_feed`: re-INSERT the `user_feed_subscriptions` row with the captured paused / max / min. Use `INSERT ... ON CONFLICT DO UPDATE` so a parallel re-subscribe doesn't 409.
- `undo_set_feed_min_score`: UPDATE back to the prior value (NULL if 0).

### B3. The `tool_call_propose` SSE event

Update `chat.ts:1054-1098` to wrap each `roundToolCalls` element in a policy check **before** `executeServerTool` runs. The policy lookup is **client-driven** — iOS sends its current per-tool policy as part of the chat request body so the server doesn't need to maintain server-side per-user prefs for this:

Request body adds an optional field:

```ts
type AssistantBody = {
  message: string;
  pageContext: AIPageContext;
  threadId: string | null;
  guardrails?: {
    // For each named tool, "confirm" or "undo_only". Missing = default Confirm.
    policies: Record<string, 'confirm' | 'undo_only'>;
  };
};
```

Server-side policy resolution function `requiresConfirmation(call: ToolCall, policies: Record<string, 'confirm' | 'undo_only'>): boolean`:

```
- unsubscribe_from_feed:    confirm unless policies.unsubscribe_from_feed === 'undo_only'
- pause_feed:               if call.args.paused === true, same rule; resume always runs inline
- set_feed_max_per_day:     same rule
- set_feed_min_score:       same rule
- mark_articles_read:       if article_ids.length > 5, same rule; <=5 always runs inline
- (any other tool):         no confirmation
```

When `requiresConfirmation` returns true:

1. Build `preview_detail_json` (see B4 — the preview enrichment).
2. INSERT into `tool_call_proposals` with `args_json`, `conversation_snapshot_json` = the `convo` array AT THE POINT before the tool ran, including the assistant's tool-use turn.
3. Emit SSE:
   ```ts
   sse({
     type: 'tool_call_propose',
     proposeId,
     name: call.name,
     args: call.args,
     summary,                // short e.g. "Mark 47 articles as read"
     detail: { ... },        // full structured detail (B4)
     contextHint: lastUserMessage, // the user's chat message that triggered this
   });
   ```
4. **Stop the loop after the propose event**. Emit `done` with `content: ''` and the usage so far. Persist what we have to `chat_messages` (the assistant's tool-use prefix text, if any, plus an entry in `tool_calls_json` with `kind: 'proposed'`).
5. The propose event is a **terminal turn** for this SSE response — iOS will issue a fresh request to `/chat/confirm-tool` to resume.

If a single round produces multiple tool calls and only some require confirmation, **propose blocks the entire round**: emit propose for the first confirm-required call, halt, and let the user resolve before the rest run. Rationale: the AI's later calls in the same round may depend on the proposed mutation (e.g., "first pause this feed, then mark its articles as read"). Don't fork.

### B4. Preview detail enrichment

`preview_detail_json` is a tool-specific structured payload that powers the confirm sheet. Implement in `chat-tools.ts` as `buildProposalDetail(call: ToolCall, ctx: ToolExecutionContext): Promise<ToolProposalDetail>`:

```ts
type ToolProposalDetail =
  | { kind: 'mark_articles_read';
      count: number;
      previews: Array<{ id: string; title: string; feedTitle: string | null }>; // first 8
      remainingCount: number; // count - previews.length
      feedBreakdown: Array<{ feedTitle: string; n: number }>; // top 5 by count
    }
  | { kind: 'pause_feed';
      feedId: string;
      feedTitle: string | null;
      currentArticleCount24h: number;
      currentlyPaused: boolean;
    }
  | { kind: 'unsubscribe_from_feed';
      feedId: string;
      feedTitle: string | null;
      subscribedAt: number | null;
      totalArticlesEver: number;
      currentlyPaused: boolean;
    }
  | { kind: 'set_feed_max_per_day';
      feedId: string;
      feedTitle: string | null;
      currentCap: number | null;
      proposedCap: number;
      avgArticlesPerDay: number;
    }
  | { kind: 'set_feed_min_score';
      feedId: string;
      feedTitle: string | null;
      currentMinScore: number | null;
      proposedMinScore: number;
      currentScoreDistribution: { p25: number; p50: number; p75: number };
    };
```

Implementation hits D1 for each tool — keep queries cheap (single feed lookup, count(*), `LIMIT 8` on titles).

### B5. New endpoint `POST /chat/confirm-tool`

Append to `chat.ts` after `/chat/exec-tool`:

```
POST /chat/confirm-tool
Body: {
  proposeId: string,
  decision: 'approve' | 'reject',
  // Optional: client may edit args (e.g. "approve but only mark first 10")
  edits?: Record<string, unknown>,
}

Response: text/event-stream — same SSE vocab as /chat/assistant.
  emits: delta / tool_call_server / tool_call_client / done / error
```

Behavior:

1. Look up `tool_call_proposals` by `proposeId` AND `user_id` (auth scope). Reject 404 if not found, 409 if `resolved_at IS NOT NULL`, 410 if older than 10 minutes.
2. Mark `resolved_at = now`, `resolution = decision`.
3. If `decision === 'reject'`:
   - Append a synthetic tool result to the conversation snapshot: `{ role: 'tool', callId, content: 'User declined to run this action.' }`.
   - Run the rest of the SSE round loop (give the AI a chance to acknowledge: "Okay, I won't unsubscribe — anything else?").
   - DON'T persist a new chat_messages row from scratch — append to the existing assistant turn's `tool_calls_json` with `kind: 'rejected'` and emit a `tool_call_server` event with `succeeded: false` and `summary: 'Cancelled by user'` so iOS can render an info chip.
4. If `decision === 'approve'`:
   - Apply `edits` over `args_json` (deep-merge).
   - Run `executeServerTool({ id: callId, name: tool_name, args: mergedArgs }, ctx)`.
   - Emit `tool_call_server` with the result (including undo payload) — this is identical to the normal inline flow.
   - Append the tool result to the conversation snapshot, run the rest of the SSE round loop.
   - Persist the final assistant turn (or append to the existing one) with the tool log.

The endpoint MUST require an active session and MUST verify `userId` matches the proposal's `user_id`.

### B6. Cleanup cron

In `wrangler.toml` cron triggers (already-scheduled hourly cron likely fits): add a sweep that updates `resolved_at = now, resolution = 'expired'` for proposals older than 10 minutes. Doesn't rollback anything (nothing was applied) — just reclaims state.

## iOS Changes

### I1. Per-tool policy storage

New file `Services/AIGuardrailsPolicy.swift`:

```swift
@MainActor
@Observable
final class AIGuardrailsPolicy {
    enum Mode: String, CaseIterable, Codable, Sendable {
        case confirm
        case undoOnly
    }

    /// All destructive tools we can govern. Names match server tool names.
    static let governedTools: [String] = [
        "unsubscribe_from_feed",
        "mark_articles_read",       // only enforced when count > 5
        "pause_feed",               // only enforced when paused == true
        "set_feed_max_per_day",
        "set_feed_min_score",
    ]

    private let defaults: UserDefaults
    private static let prefix = "aiGuardrails.policy."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func mode(for tool: String) -> Mode {
        guard let raw = defaults.string(forKey: Self.prefix + tool),
              let mode = Mode(rawValue: raw) else {
            return .confirm  // default
        }
        return mode
    }

    func setMode(_ mode: Mode, for tool: String) {
        defaults.set(mode.rawValue, forKey: Self.prefix + tool)
    }

    /// Snapshot for the chat request body.
    func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for t in Self.governedTools {
            out[t] = mode(for: t).rawValue
        }
        return out
    }
}
```

Inject as `appState.aiGuardrails: AIGuardrailsPolicy` (lazy-init in AppState init).

### I2. Send policy snapshot with each chat request

In `StreamingChatService.swift` `performAssistantStream`, extend `AssistantBody`:

```swift
struct AssistantBody: Encodable {
    let message: String
    let pageContext: AIPageContext
    let threadId: String?
    let guardrails: Guardrails?
    struct Guardrails: Encodable {
        let policies: [String: String]
    }
}
```

The coordinator passes the snapshot (`AppState.shared.aiGuardrails.snapshot()`) when calling the streaming method. Wire `policy: AIGuardrailsPolicy?` through to `streamAssistantMessage`.

### I3. Decode the new SSE event

Add to `SSEEvent`:

```swift
private struct SSEEvent: Decodable {
    // ... existing fields
    var proposeId: String?
    var detail: ToolProposalDetail?
    var contextHint: String?
}
```

Define `ToolProposalDetail` as a discriminated union (`kind` field) mirroring B4. Use `Decodable` with a `kind` switch.

In `ChatDelta`:

```swift
case toolProposal(
    proposeId: String,
    name: String,
    args: [String: AnyCodable],
    summary: String,
    detail: ToolProposalDetail,
    contextHint: String?
)
```

In `performAssistantStream` switch, handle `case "tool_call_propose"` by yielding the new delta.

### I4. Confirmation sheet UI

**Decision: full sheet (NOT `.confirmationDialog`, NOT `.alert`).**

Rationale:
- `.confirmationDialog` is too constrained — we need to show article titles, feed breakdown, before/after values, and the conversational context that triggered it.
- `.alert` is even more constrained.
- The sheet matches the existing in-chat-context UX of the assistant (the assistant itself is a sheet) and gives room for the rich preview.

New file `Features/AIAssistant/AIToolConfirmationSheet.swift`:

```swift
struct AIToolConfirmationSheet: View {
    let proposal: PendingProposal
    let onConfirm: (_ edits: [String: AnyCodable]?) -> Void
    let onReject: () -> Void

    struct PendingProposal {
        let proposeId: String
        let toolName: String
        let summary: String
        let detail: ToolProposalDetail
        let contextHint: String?    // "You asked: 'mark all the AI hype as read'"
    }
    // ...
}
```

Layout:

```
┌──────────────────────────────────────────┐
│ [icon] Mark 47 articles as read?         │  <- title from summary
│                                          │
│ You asked: "mark all the AI hype as read"│  <- contextHint (if present)
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │ 47 articles across 3 feeds:          │ │  <- detail-specific block
│ │  • Hacker News (24)                  │ │
│ │  • This Week in Rust (15)            │ │
│ │  • Anthropic Blog (8)                │ │
│ │                                      │ │
│ │ First few:                           │ │
│ │  · "GPT-4o is now multimodal..."     │ │
│ │  · "Cargo 1.78 released..."          │ │
│ │  · "Claude Opus 4 announcement..."   │ │
│ │  · …and 44 more                      │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ [ Cancel ]              [ Mark as read ] │
│                                          │
│ ──────                                   │
│ Always do this without asking            │
│ [ ] Don't ask again for this tool        │
└──────────────────────────────────────────┘
```

- The "Don't ask again" checkbox, if checked when the user taps Confirm, flips that tool to `.undoOnly` in `AIGuardrailsPolicy` before dispatching the approve.
- The action button label is tool-specific ("Mark as read", "Pause feed", "Unsubscribe", "Apply cap", "Apply score filter").
- The title icon is tool-specific (`checkmark.circle`, `pause.circle`, `xmark.circle`, `slider.horizontal.3`, `chart.bar.xaxis`).
- Use `.presentationDetents([.medium, .large])` so the user can expand if the article list is long.

Detail blocks per tool kind:

- **mark_articles_read**: bullet list of feed breakdown (top 5), then "First few:" with up to 8 article titles, then "…and N more" if `remainingCount > 0`.
- **pause_feed**: feed title (large), "Currently publishing X articles/day" line, "After pause, no new articles until you resume."
- **unsubscribe_from_feed**: feed title (large), "Subscribed since {relative date}", "X total articles fetched", then a warning callout: "Existing read state and saved articles are kept. Re-subscribing later starts fresh — no automatic re-fetch."
- **set_feed_max_per_day**: "Cap {feedTitle} at {N}/day" with a before→after row ("Currently {currentCap ?? "no cap"} → {proposedCap}"), and an info line "Feed averages X articles/day".
- **set_feed_min_score**: "Hide articles below score {N} in {feedTitle}" with before→after, and a small histogram hint: "Recent scores: 25th p {p25}, median {p50}, 75th p {p75}".

### I5. Wiring the proposal through the coordinator

In `AIAssistantCoordinator`, add `pendingProposal: AIToolConfirmationSheet.PendingProposal?` (`@Observable`-tracked).

In `sendMessage` switch, add `case .toolProposal(...)`:

```swift
case .toolProposal(let id, let name, let args, let summary, let detail, let contextHint):
    pendingProposal = .init(
        proposeId: id, toolName: name, summary: summary,
        detail: detail, contextHint: contextHint
    )
    // The current SSE turn is over. Stop the streaming loop and wait for the user.
    isStreaming = false
    return  // exit the for-await loop
```

(Implementation note: because `for await` is already iterating `stream`, structure this as a flag — set `pendingProposal`, break out of the loop, leave `streamingContent` as-is so any pre-tool assistant text stays visible.)

Add new method:

```swift
func resolveProposal(approve: Bool, edits: [String: AnyCodable]? = nil, dontAskAgain: Bool = false) async {
    guard let p = pendingProposal else { return }
    pendingProposal = nil

    if dontAskAgain {
        appState.aiGuardrails.setMode(.undoOnly, for: p.toolName)
    }

    // Resume the conversation by streaming /chat/confirm-tool.
    isStreaming = true
    let stream = StreamingChatService.shared.streamConfirmTool(
        proposeId: p.proposeId,
        decision: approve ? "approve" : "reject",
        edits: edits
    )
    // Drain — same switch as sendMessage; appends to streamingContent.
    for await delta in stream {
        // ... (same case handling, including .toolProposal which can re-fire if
        //      the AI's follow-up turn proposes another confirm-required tool)
    }
    // ... finalize same as sendMessage
}
```

Add `streamConfirmTool` method to `StreamingChatService` — same shape as `streamAssistantMessage`, posts to `api/chat/confirm-tool`, parses the same SSE events.

### I6. Sheet presentation

In `AIAssistantSheetView` (the existing assistant container), add:

```swift
.sheet(item: $coordinator.pendingProposal) { proposal in
    AIToolConfirmationSheet(
        proposal: proposal,
        onConfirm: { edits in Task { await coordinator.resolveProposal(approve: true, edits: edits) } },
        onReject: { Task { await coordinator.resolveProposal(approve: false) } }
    )
    .presentationDetents([.medium, .large])
}
```

Make `PendingProposal` conform to `Identifiable` (`id = proposeId`).

### I7. Undo-chip countdown anchor

For tools running under `Undo only` policy, we need a more prominent / persistent undo affordance than the in-bubble button.

**Decision: Toast anchored to the AI assistant FAB (the floating sparkle button), with a circular countdown.**

Rationale:
- The chat sheet may be dismissed before the user notices the chip.
- Anchoring to the FAB means the undo is reachable from any tab.
- The toast doesn't intrude on the reading surface — it sits above the FAB.
- Anchoring to a system toast or `Notification` would feel like an iOS notification, confusing.

Implementation:

- New `Features/AIAssistant/AIUndoToast.swift` — a Capsule view with summary text + circular `ProgressView` showing countdown + "Undo" button.
- Owned by `AIAssistantCoordinator` as `pendingUndoToast: PendingUndoToast?`. Set when `.toolServerResult(undo: ...)` fires AND the tool name is in `AIGuardrailsPolicy.governedTools` AND mode is `.undoOnly` (i.e., chip+toast is the user's chosen path for this tool).
- Lifetime: 7 seconds (single constant, NOT per-tool — keeps the toast predictable). Tap toast or its Undo button → POST `/chat/undo-tool` (reuse `coordinator.undoTool`). Dismiss → set `pendingUndoToast = nil`.
- Rendered in `AIAssistantOverlay` (the global FAB host) above the FAB. Use `.transition(.move(edge: .bottom).combined(with: .opacity))`.
- If a second destructive tool fires while a toast is up: replace the existing toast (don't queue) and start a new countdown. The first action is no longer undoable via toast — but the in-bubble Undo button is still available for the older one when the chat sheet is opened.

For tools NOT in `governedTools` but with an undo payload (e.g. `apply_tag_to_article`, `set_article_reaction`), keep current behavior: in-bubble chip with inline Undo button, no toast. Don't make the toast a global broadcast for every mutation.

### I8. Settings → Advanced → AI Guardrails screen

New file `Features/Settings/AIGuardrailsSettingsView.swift`:

```swift
struct AIGuardrailsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                ForEach(AIGuardrailsPolicy.governedTools, id: \.self) { tool in
                    NavigationLink(value: tool) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(toolDisplayName(tool))
                                .font(.body)
                            Text(modeDescription(appState.aiGuardrails.mode(for: tool)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("AI Guardrails", systemImage: "shield.lefthalf.filled")
            } footer: {
                Text("Choose how the AI handles each destructive action. Confirm pauses for approval; Undo only runs immediately with a 7-second undo window.")
            }
        }
        .navigationDestination(for: String.self) { tool in
            AIGuardrailsToolDetailView(tool: tool)
        }
    }
}
```

Detail view `AIGuardrailsToolDetailView`: a Picker bound to `appState.aiGuardrails.mode(for:tool)` with two segments (`Confirm` / `Undo only`), plus a footer explaining the difference.

Tool display names (exact strings):

- `unsubscribe_from_feed` → "Unsubscribe from a feed"
- `mark_articles_read` → "Mark 6+ articles as read"  (clarifies the >5 threshold)
- `pause_feed` → "Pause a feed"
- `set_feed_max_per_day` → "Cap a feed's daily articles"
- `set_feed_min_score` → "Filter a feed by minimum score"

Wire from `SettingsView.swift`: add a new section "Advanced" with one `NavigationLink` to `AIGuardrailsSettingsView()`. Keep existing sections intact.

### I9. iPad / macOS notes

- The confirmation sheet uses `.presentationDetents` which on iPad regular renders as a centered card — that's fine.
- The undo toast on macOS / iPad regular: the FAB is anchored differently (see M10 deferred backlog). Position the toast `bottom-leading` of the assistant FAB irrespective of platform — `AIAssistantOverlay` already knows its own anchor.

## Interfaces and Data Flow

### New SSE event

```
event: tool_call_propose
data: {
  "type": "tool_call_propose",
  "proposeId": "tcp_abc123",
  "name": "mark_articles_read",
  "args": { "article_ids": ["a1", "a2", ...] },
  "summary": "Mark 47 articles as read",
  "detail": {
    "kind": "mark_articles_read",
    "count": 47,
    "previews": [{ "id": "a1", "title": "...", "feedTitle": "..." }, ...],
    "remainingCount": 39,
    "feedBreakdown": [{ "feedTitle": "Hacker News", "n": 24 }, ...]
  },
  "contextHint": "You asked: 'mark all the AI hype as read'"
}
```

### New endpoint

```
POST /chat/confirm-tool
Auth: Bearer
Body: {
  "proposeId": "tcp_abc123",
  "decision": "approve" | "reject",
  "edits": { ... } | null   // optional partial overrides
}
Response: text/event-stream (same vocab as /chat/assistant)
Errors:
  401 unauthorized
  404 proposal not found / not yours
  409 already resolved
  410 expired (>10 min)
  500 internal
```

### New chat-request guardrails field

```
POST /chat/assistant body extension:
{
  "message": "...",
  "pageContext": { ... },
  "threadId": "...",
  "guardrails": {
    "policies": {
      "unsubscribe_from_feed": "confirm",
      "mark_articles_read": "undo_only",
      "pause_feed": "confirm",
      "set_feed_max_per_day": "undo_only",
      "set_feed_min_score": "confirm"
    }
  }
}
```

Field is optional — server treats missing as all-Confirm.

### iOS Settings UI

Settings → Advanced → AI Guardrails → per-tool detail (segmented picker `Confirm` / `Undo only`). UserDefaults backing, key prefix `aiGuardrails.policy.`. No iCloud / no server sync.

## Edge Cases and Failure Modes

- **Proposal expires (>10 min)**: `/chat/confirm-tool` returns 410. iOS clears `pendingProposal`, shows a soft inline message in the chat ("That action timed out. Ask again if you'd still like to do it.").
- **User dismisses the confirm sheet without tapping anything**: treat as `reject`. Implement via `.onDisappear` on the sheet — if no decision was made, fire `resolveProposal(approve: false)`. Server records `resolution = 'rejected'` and the AI gets a "User declined" tool result.
- **Multiple proposals in one round**: server emits one propose, halts. After confirmation, the resumed loop may emit another propose for a sibling call. Handle the chained case — `resolveProposal` already drains a fresh stream that can yield another `.toolProposal`.
- **Tool execution fails after approval**: the `tool_call_server` event still emits with `succeeded: false` and no undo payload. iOS shows an orange chip ("Couldn't pause feed: not subscribed"). No toast, no special handling.
- **Approve with edits**: only `mark_articles_read` supports edits in this phase (user can choose to mark fewer than the AI proposed). Sheet has a stretch-tier "Mark only first N" stepper — defer to follow-up if it bloats the UI.
- **User taps Undo after the 7s toast window**: the in-bubble chip Undo button still works (it doesn't expire — the undo payload is preserved in `chat_messages.tool_calls_json`). Toast is best-effort, chip is persistent.
- **Undo fails on the server** (e.g., row already changed by a concurrent action): server returns `succeeded: false`. iOS shows a red chip ("Couldn't undo — feed already re-subscribed by another change"). The original chip stays visible.
- **Policy change mid-stream**: if the user toggles a tool from Confirm → Undo only while a chat is in-flight, the in-flight message used the stale snapshot. That's fine — the next message picks up the new policy. Don't try to mutate in-flight state.
- **mark_articles_read with exactly 5 ids**: runs inline (>5 is the threshold, not >=5).
- **pause_feed with paused=false (resume)**: never requires confirmation — resume is the safe direction. Same for `subscribe_to_feed` (not in governed list at all).
- **set_feed_max_per_day to a higher number than current** (loosening): still treated as a mutation requiring confirm under the user's policy. Could be smarter ("loosening is safe, tightening is risky") but adds policy complexity; defer.
- **Server-side BYOK budget exceeded mid-loop**: the propose endpoint shouldn't emit propose events if the user has already blown the budget. `recordUsage` happens on `/chat/assistant` and `/chat/confirm-tool` — if the resume-stream's first AI call short-circuits on budget, the response is a `done` with an error message, not a propose.
- **iOS app backgrounded between propose and confirm**: `pendingProposal` lives in `AIAssistantCoordinator` (in-memory). On app relaunch the proposal is lost. The server-side row will expire after 10 min. Acceptable for v1; persisting `pendingProposal` to UserDefaults across launches is a stretch. (If we do persist, `resolveProposal` must tolerate a now-expired proposal id with a graceful "took too long" message.)
- **Chat sheet closed while toast is visible**: toast is rendered in `AIAssistantOverlay` (the global FAB host), independent of the sheet. Continues counting down. Tapping it opens the sheet AND fires the undo. (If sheet was already mid-animation closing when undo fires, await sheet dismissal then re-present? Simplest: open sheet to its prior state, then run undo. The undo result chip will append to the transcript on next render.)

## Test Plan

### Backend verification

```bash
cd /Users/tfinklea/git/nebularnews && npx wrangler deploy --env production
```

Apply migration:
```bash
cd /Users/tfinklea/git/nebularnews && npx wrangler d1 migrations apply nebularnews --env production
```

Manual SSE test (replace `$TOK` with a real session token):
```bash
curl -N -X POST https://api.nebularnews.com/api/chat/assistant?stream=true \
  -H "Authorization: Bearer $TOK" \
  -H "Content-Type: application/json" \
  -d '{"message":"unsubscribe me from Hacker News","pageContext":{"surface":"today"},"guardrails":{"policies":{"unsubscribe_from_feed":"confirm"}}}'
```
Expect: SSE stream ends with `tool_call_propose` and `done` with empty content. No D1 write to `user_feed_subscriptions`. New row in `tool_call_proposals`.

Approve:
```bash
curl -N -X POST https://api.nebularnews.com/api/chat/confirm-tool \
  -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  -d '{"proposeId":"tcp_...","decision":"approve"}'
```
Expect: SSE emits `tool_call_server` with `succeeded:true`, then `done`. `user_feed_subscriptions` row removed. `tool_call_proposals.resolved_at` set, `resolution='approved'`.

Reject:
```bash
curl ... -d '{"proposeId":"tcp_...","decision":"reject"}'
```
Expect: SSE emits `tool_call_server` with `succeeded:false, summary:"Cancelled by user"`, then assistant follow-up text via `delta` events, then `done`. No D1 mutation. `resolution='rejected'`.

### iOS build

```bash
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

### Acceptance Criteria

- [ ] Migration `0020_tool_call_proposals.sql` applies cleanly to production D1.
- [ ] Backend deploy succeeds; `/chat/confirm-tool` reachable on production.
- [ ] `unsubscribe_from_feed` and `set_feed_min_score` are listed in `SERVER_TOOLS`; `undo_unsubscribe_from_feed` and `undo_set_feed_min_score` are in `UNDO_TOOL_NAMES`.
- [ ] Asking sparkle "unsubscribe me from <feed>" with default policy emits `tool_call_propose` and DOES NOT mutate D1 until confirm.
- [ ] Asking sparkle "mark all 200 stale items as read" with default policy emits propose; `mark_articles_read` with 3 ids does NOT emit propose (runs inline).
- [ ] Asking sparkle "resume my paused tech feed" runs `pause_feed(paused=false)` inline (resume is non-destructive); "pause my noisy feed" emits propose.
- [ ] Confirmation sheet renders the tool-specific detail block with feed name, count, and contextHint string for all five tools.
- [ ] "Don't ask again for this tool" checkbox in the sheet flips that tool's `AIGuardrailsPolicy` to `.undoOnly` after Confirm.
- [ ] Tapping Cancel emits a soft chip ("Cancelled by user") in the chat transcript and lets the AI follow up.
- [ ] Dismissing the sheet by swipe is treated as Cancel (no D1 mutation, propose marked rejected).
- [ ] After confirmation, the resumed SSE stream appends to the same assistant message's transcript without flicker or duplicated text.
- [ ] When a tool's policy is `.undoOnly`, the action runs inline AND a 7-second toast appears anchored to the AI FAB (NOT just the in-bubble chip).
- [ ] Tapping the toast Undo button POSTs `/chat/undo-tool` with the same args bag the in-bubble Undo would send and returns the same result.
- [ ] The toast disappears after 7 seconds; the in-bubble chip Undo button still works after that window.
- [ ] Settings → Advanced → AI Guardrails lists all five governed tools with current mode subtitles.
- [ ] Toggling a tool's mode persists across app relaunch (UserDefaults key `aiGuardrails.policy.<tool>`).
- [ ] On a fresh install, every governed tool reads as `.confirm`.
- [ ] Proposal expires (>10 min) → confirm returns 410 → iOS shows "That action timed out" message in chat, clears `pendingProposal`.
- [ ] Cleanup cron evicts proposals older than 10 minutes (verify by inserting a manual row with `created_at = now - 11min`, running cron locally or waiting one tick).
- [ ] iOS macOS build (`xcodebuild ... platform=macOS`) clean.
- [ ] iOS Simulator (iPhone) build clean.

## Hand-off Tier

**Sonnet implementer** (multi-layer change touching backend tool-call protocol, iOS streaming, AppState bindings, Settings).

### Files likely touched

**Backend (`/Users/tfinklea/git/nebularnews`):**

- `migrations/0020_tool_call_proposals.sql` — **new**
- `src/lib/chat-tools.ts` — add 2 server tools, 2 undo handlers, `requiresConfirmation`, `buildProposalDetail`
- `src/routes/chat.ts` — wrap streaming round loop with policy check; new `/chat/confirm-tool` endpoint; cleanup cron entry
- `src/cron/` — add or extend cleanup-cron module to expire stale proposals
- `wrangler.toml` — wire cron if a new schedule is needed (otherwise hourly cron picks it up)

**iOS (`/Users/tfinklea/git/nebularnews-ios`):**

- `Services/AIGuardrailsPolicy.swift` — **new**
- `App/AppState.swift` — inject `aiGuardrails: AIGuardrailsPolicy` (lazy)
- `Services/StreamingChatService.swift` — extend `AssistantBody` with guardrails, decode `tool_call_propose`, add `streamConfirmTool` method, add `ChatDelta.toolProposal`, define `ToolProposalDetail` (Decodable union)
- `Features/AIAssistant/AIAssistantCoordinator.swift` — handle `.toolProposal` delta, add `pendingProposal` + `pendingUndoToast`, add `resolveProposal`, gate toast on `.undoOnly`
- `Features/AIAssistant/AIToolConfirmationSheet.swift` — **new**
- `Features/AIAssistant/AIUndoToast.swift` — **new**
- `Features/AIAssistant/AIAssistantOverlay.swift` — host `AIUndoToast` above the FAB
- `Features/AIAssistant/AIAssistantSheetView.swift` — present confirmation sheet via `.sheet(item:)`
- `Features/Settings/SettingsView.swift` — add Advanced → AI Guardrails NavigationLink section
- `Features/Settings/AIGuardrailsSettingsView.swift` — **new**
- `Features/Settings/AIGuardrailsToolDetailView.swift` — **new**

### Constraints

- Do NOT change behavior for tools NOT in `AIGuardrailsPolicy.governedTools`. `apply_tag_to_article`, `set_article_reaction`, `save_articles`, `react_to_articles`, `subscribe_to_feed` keep the current chip+inline-undo flow with no toast.
- Do NOT introduce iCloud sync for the policy. UserDefaults only.
- Do NOT delete `tool_call_proposals` rows on resolve — keep them for audit; cleanup cron only handles expiry of unresolved rows. (Future audit-log integration can read them.)
- Server must NEVER execute a confirm-required tool without a matching `tool_call_proposals` row whose `resolution = 'approved'`. The `executeServerTool` path through `/chat/confirm-tool` is the only path that runs governed tools when `requiresConfirmation` returned true.
- Wrangler deploys (incl. prod) are pre-authorized — apply migration and deploy as part of implementation.
- Do not bump marketing version. Build-only release per `release.sh` defaults.

### Verification commands

Backend:
```
cd /Users/tfinklea/git/nebularnews && npm run typecheck
cd /Users/tfinklea/git/nebularnews && npx wrangler d1 migrations apply nebularnews --env production
cd /Users/tfinklea/git/nebularnews && npx wrangler deploy --env production
```

iOS:
```
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 15' build CODE_SIGNING_ALLOWED=NO
```

Acceptance: walk the iOS device through every Acceptance Criteria checkbox above. Confirm the confirmation sheet, the toast countdown, the per-tool Settings, the cancel-as-reject path, and the proposal-expiry path on a real device.

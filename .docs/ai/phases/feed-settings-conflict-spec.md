# Plan: Feed Settings If-Match + 412 Conflict Resolver (iOS)

> Status: Spec — backend scaffolding already shipped (M12 Track A). iOS-only follow-up.
> Date: 2026-04-29.
> Recommended implementer: **Sonnet** (medium reasoning).

---

## Product Overview

When a user opens **Feed Settings** on one device, makes changes, and saves, those changes can collide with edits made on another device (or in a brief tab they forgot about). Today, the iOS client blindly POSTs the new state and last-writer-wins clobbers whatever the other device set — silently. This is a known data-loss vector for `paused`, `max_articles_per_day`, and `min_score` (the three per-feed user controls).

The Workers backend already emits a compact ETag for the subscription row and accepts `If-Match` on `PATCH /feeds/:id/settings`. When the header is present and stale, the server returns **412 Precondition Failed** with `current_etag` and the current values in the error body. The iOS client today does not capture or send the ETag — so the protection is dead-code from the device's perspective.

This phase wires up the iOS side end-to-end:

1. iOS computes/captures the ETag at read time and sends it on every save.
2. On 412, the SyncManager pauses the queued mutation in a `conflict` state instead of retrying.
3. The user sees an inline diff sheet with three actions — **Keep server**, **Apply mine**, **Merge** — and a per-field picker on Merge.
4. Telemetry logs every 412 (rare under single-device use; common dual-device signal).

This delivers the "obvious fix" for what is otherwise silent multi-device data loss on the only writable per-feed surface in the app.

---

## Current State

**Backend (`/Users/tfinklea/git/nebularnews/src/routes/feeds.ts`, already shipped):**
- ETag format (line 147-148): `` `p${paused}m${max_articles_per_day ?? ''}n${min_score ?? ''}` `` — e.g. `p0m100n3`, `p1mn` (nulls render as empty).
- `paused` is a `0|1` integer in D1 (the API converts to bool only in `GET /feeds` rows, not in the etag).
- PATCH `/feeds/:id/settings` (line 155) reads `If-Match` header. If present and stale → 412 with body `{ ok: false, error: { code: 'precondition_failed', message, current_etag } }`. Note: `current_etag` is the only conflict-state field returned today; the *current values* are NOT echoed back.
- Successful PATCH returns `{ ok: true, data: { etag: newEtag } }`.
- `GET /feeds` (line 25) returns `paused` (bool), `max_articles_per_day`, `min_score` per row but does **not** include an `etag` field. iOS must compute it locally on read.

**iOS (`/Users/tfinklea/git/nebularnews-ios`):**
- `Services/APIClient.swift` — `rawRequest(...)` does not accept custom headers and discards response headers (returns only `Data`). No 412 branch in error handling (line 127 lumps `>= 400` into `serverError`).
- `Services/FeedService.swift:40` — `updateFeedSettings` calls `requestVoid(method: "PATCH", ...)`. No `If-Match`. No success ETag captured (the call is `Void`).
- `Services/SupabaseManager.swift:132` — facade delegate; no ETag plumbing.
- `Services/SyncManager.swift:338` — `updateFeedSettings` queues on offline/failure. Failures of any kind reset to a generic retry. **No conflict state on `PendingAction`.** Max retries = 10 → dead-letter.
- `Models/PendingAction.swift` — fields are `actionType`, `articleId`, `payload`, `retryCount`, `lastError`. No state enum, no conflict marker, no captured ETag.
- `Features/Companion/CompanionFeedsView.swift:420` — `FeedSettingsSheet` Form; saves through `sync.updateFeedSettings(...)` and silently swallows non-`queuedOffline` errors (line 571: "Best-effort — surfacing an alert here would break the dismiss flow"). 412 currently disappears here.
- `Features/Companion/CompanionModels.swift:229` — `CompanionFeed` has `paused`, `maxArticlesPerDay`, `minScore` but no `etag` field.

**Handoff docs:**
- `.docs/ai/current-state.md:106` notes backend scaffolding shipped, client wiring deferred.
- `.docs/ai/next-steps.md:170, 172` — both bullets covered by this spec.
- A sibling **sync queue inspector spec** is referenced (`.docs/ai/phases/sync-queue-inspector-spec.md`) but does not yet exist; this spec defines the data hook the inspector will read from.

---

## Implementation Plan

Ordered. Each step is decision-complete — no design judgment required by the implementer.

### Step 1 — Compute ETag locally (helper)

Add `Services/FeedSettingsETag.swift` (new file) with a single pure helper:

```swift
enum FeedSettingsETag {
    /// Mirrors the server's subscriptionEtag() in
    /// nebularnews/src/routes/feeds.ts:147 — DO NOT diverge.
    /// `paused`: bool → "0" or "1"
    /// `maxArticlesPerDay`: nil → "", value → decimal string
    /// `minScore`: nil → "", value → decimal string (note: 0 is a real value, not nil)
    static func compute(paused: Bool, maxArticlesPerDay: Int?, minScore: Int?) -> String {
        let p = paused ? "1" : "0"
        let m = maxArticlesPerDay.map(String.init) ?? ""
        let n = minScore.map(String.init) ?? ""
        return "p\(p)m\(m)n\(n)"
    }
}
```

Add a unit-test-friendly extension at the bottom of `CompanionFeed`:

```swift
extension CompanionFeed {
    /// ETag derived from the three mutable subscription fields.
    /// `paused` defaults to false when nil to match server INSERT default of 0.
    /// `minScore` is **not** defaulted — nil means "unset" and server distinguishes that from 0.
    var settingsEtag: String {
        FeedSettingsETag.compute(
            paused: paused ?? false,
            maxArticlesPerDay: maxArticlesPerDay,
            minScore: minScore
        )
    }
}
```

**Rationale:** Backend `GET /feeds` does not include the etag, so a roundtrip would require a backend change (out of scope per user). Local computation matches byte-for-byte with `subscriptionEtag()` and is correct as long as the iOS read of feeds happened against the same row state the user is editing.

### Step 2 — Custom headers + raw response on `APIClient`

Edit `Services/APIClient.swift`:

1. Extend `rawRequest(...)` to accept `additionalHeaders: [String: String]? = nil` and return `(data: Data, response: HTTPURLResponse)` instead of just `Data`. Update existing callers to ignore the response tuple's second element.
2. Add a new typed throw branch on 412:
   ```swift
   if httpResponse.statusCode == 412 {
       if let body = try? decoder.decode(APIErrorResponse.self, from: data),
          let currentEtag = body.error.currentEtag {
           throw APIError.preconditionFailed(currentEtag: currentEtag, message: body.error.message)
       }
       throw APIError.serverError(412, "Precondition failed")
   }
   ```
3. Extend `APIErrorDetail` to optionally decode `currentEtag` (snake_case → camelCase via existing decoder). Add `case preconditionFailed(currentEtag: String, message: String)` to `APIError`.
4. Add a typed `request(...)` overload for callers that need response headers — specifically for capturing the success ETag on PATCH:
   ```swift
   func requestWithHeaders<T: Decodable>(
       method: String, path: String,
       body: (any Encodable)? = nil,
       additionalHeaders: [String: String]? = nil
   ) async throws -> (T, [String: String]) { ... }
   ```
   Headers dictionary normalizes keys to lowercase for case-insensitive lookup.

**Do not touch other endpoints.** Existing callers should keep using `request` / `requestVoid`.

### Step 3 — Send `If-Match`, capture new ETag in `FeedService`

Edit `Services/FeedService.swift:40`. Replace the body of `updateFeedSettings` so it:

1. Accepts a new param `ifMatch: String?` (nil for first-time/migration callers, but implementations should always pass it).
2. Sends `If-Match: <etag>` header when non-nil.
3. Uses `requestWithHeaders` against the typed response `{ etag: String? }` and returns the new etag string.

New signature:

```swift
@discardableResult
func updateFeedSettings(
    feedId: String,
    paused: Bool? = nil,
    maxArticlesPerDay: Int? = nil,
    minScore: Int? = nil,
    ifMatch: String? = nil
) async throws -> String?
```

Mirror the signature on `SupabaseManager.updateFeedSettings` (`Services/SupabaseManager.swift:132`).

### Step 4 — Extend `PendingAction` for conflict state + captured ETag

Edit `Models/PendingAction.swift` and add three optional fields:

```swift
var state: String = "pending"        // "pending" | "conflict" | "deadletter"
var ifMatchEtag: String?             // sent on retry to detect concurrent edits
var conflictServerEtag: String?      // populated on 412
var conflictServerSnapshotJSON: String?  // best-effort snapshot of server state at 412 time
```

`state` lives alongside `retryCount` for now — `pending` covers both fresh and retrying-with-error. `conflict` short-circuits both the queue picker (Step 5) and the dead-letter path. `deadletter` is what `retryCount >= maxRetries` means today; explicit field makes it queryable.

**Migration note:** SwiftData adds nullable columns transparently; no migration script required. Existing rows get `state = "pending"` by default. Verify by running the app once after the change and confirming no SwiftData errors in the logger.

### Step 5 — Wire 412 → conflict pause in SyncManager

Edit `Services/SyncManager.swift`:

1. Update `FeedSettingsPayload` to include the **proposed values** (already there) plus a new `ifMatch: String?` (the etag that was current when the sheet was opened). Bump payload by adding the field as nullable; old queued payloads decode with `ifMatch == nil` and behave like a non-If-Match save.
2. `updateFeedSettings(feedId:paused:maxArticlesPerDay:minScore:)` (line 338) gains a new `ifMatch: String?` parameter. Threads it into the `FeedSettingsPayload` and the underlying `supabase.updateFeedSettings(...)` call.
3. Inside `executeAction(...)` (line 208) for `case "feed_settings"`:
   ```swift
   case "feed_settings":
       let payload = try JSONDecoder().decode(FeedSettingsPayload.self, from: Data(action.payload.utf8))
       do {
           _ = try await supabase.updateFeedSettings(
               feedId: action.articleId,
               paused: payload.paused,
               maxArticlesPerDay: payload.maxArticlesPerDay,
               minScore: payload.minScore,
               ifMatch: payload.ifMatch
           )
       } catch let APIError.preconditionFailed(currentEtag, _) {
           // Park the action — do NOT bump retryCount, do NOT delete.
           action.state = "conflict"
           action.conflictServerEtag = currentEtag
           // Server only returns the etag, not values. Snapshot what we can
           // by re-reading the feed list once and capturing the matching row.
           if let snap = await fetchFeedSnapshotJSON(feedId: action.articleId) {
               action.conflictServerSnapshotJSON = snap
           }
           logger.warning("412 conflict on feed_settings for \(action.articleId) — parked for user resolution")
           appState?.feedConflicts.notify(feedId: action.articleId)
           return  // do NOT delete the row in syncPendingActions
       }
   ```
4. Update `fetchPendingActions` and `syncPendingActions` to skip rows where `state == "conflict"` (they should not be retried until the user resolves them). The existing `retryCount < maxRetries` predicate is broadened to `state == "pending" && retryCount < maxRetries`.
5. Add `fetchConflictedActions() -> [PendingAction]` and `var conflictedActionCount: Int` mirroring the dead-letter pattern.
6. Add a `resolveConflict(_ action: PendingAction, with resolution: FeedSettingsResolution)` method (see Step 6 for the resolution type) that:
   - Rewrites the action's payload with the merged values.
   - Sets `payload.ifMatch = action.conflictServerEtag` (since the user has now seen the server state, the next retry sends the *server's* etag as If-Match — assuming nobody else edits in the meantime).
   - Resets `state = "pending"`, clears `conflictServerEtag` / `conflictServerSnapshotJSON`, leaves `retryCount` at 0 (the resolution is logically a fresh save).
   - Calls `syncPendingActions()` immediately so the user sees the change land.

`fetchFeedSnapshotJSON` can be a small private helper that calls `supabase.fetchFeeds()` and JSON-encodes the matching row — best-effort, swallow errors. If the snapshot fails, the diff sheet falls back to "server values unknown — Keep server / Apply mine only" (no per-field merge).

### Step 6 — `FeedSettingsResolution` + diff sheet UI

Add `Features/Companion/FeedSettingsConflictSheet.swift` (new file).

Resolution model:

```swift
enum FeedSettingsFieldChoice: String, Codable {
    case server, mine
}

struct FeedSettingsResolution {
    var paused: FeedSettingsFieldChoice
    var maxArticlesPerDay: FeedSettingsFieldChoice
    var minScore: FeedSettingsFieldChoice
    static let allServer = FeedSettingsResolution(paused: .server, maxArticlesPerDay: .server, minScore: .server)
    static let allMine = FeedSettingsResolution(paused: .mine, maxArticlesPerDay: .mine, minScore: .mine)
}
```

Sheet UI (`FeedSettingsConflictSheet`):
- Presented from `CompanionFeedsView` when `appState.feedConflicts.pending` contains the feed (subscribed via the existing `@Environment(AppState.self)`).
- Header: "Feed settings changed elsewhere" + subtitle showing feed title.
- Below the header, a small caption: `Server last modified <relative time>` if the snapshot includes a timestamp; otherwise just `Server state captured <relative time ago>` from when the 412 was received (`PendingAction.createdAt` proxy).
- A `Form` with one `Section` per field (Status, Cap, Min Score). Each section renders three columns rendered as labeled rows:
  - Field name
  - Server value (read-only label)
  - Mine value (read-only label, highlighted if it differs from server)
  - Below: a `Picker(\"Choose\", selection: $choice)` with two options — `.server` and `.mine`. Default selection: `.server` for fields where server differs from mine; `.mine` for fields where they match (no-op anyway).
- Three primary buttons in toolbar:
  - **Keep server** — submits `.allServer` (the resolved payload becomes server state — effectively discards the local edit).
  - **Apply mine** — submits `.allMine`.
  - **Merge** — submits the per-field picker selections.
- Both **Keep server** and **Apply mine** are also one-tap shortcuts that bypass the per-field pickers.
- On submit: call `sync.resolveConflict(action, with: resolution)` and dismiss.

Edge case: if the server snapshot is unavailable (snapshot fetch failed in Step 5), show a simpler two-button sheet (Keep server / Apply mine) with a footer explaining "Couldn't load current server values — pick a side and we'll sync."

### Step 7 — Pass ETag through the save sheet

Edit `Features/Companion/CompanionFeedsView.swift:420` (`FeedSettingsSheet`):

1. Capture the etag at sheet-open time:
   ```swift
   @State private var capturedEtag: String
   // in init:
   _capturedEtag = State(initialValue: feed.settingsEtag)
   ```
2. In `save()` (line 548), pass `ifMatch: capturedEtag` through to `sync.updateFeedSettings(...)` and `appState.supabase.updateFeedSettings(...)`.
3. Catch `APIError.preconditionFailed` from the direct (non-queue) path:
   - Queue the action with `state = "conflict"` (use a new `SyncManager.queueConflict(...)` helper that mirrors the queueing+notify path from Step 5, since the live save bypassed the queue).
   - Surface the conflict sheet via the same notify channel.

**Do NOT** re-fetch the feed list on sheet open to refresh the etag. If the user opens settings, sits there 10 minutes, then taps Save — we send the stale etag and let the server 412. This is the simpler path and the conflict sheet handles it correctly. Re-fetching on open would add latency to a hot path for a rare race.

### Step 8 — Notify channel + entry point in CompanionFeedsView

Add to `App/AppState.swift`:

```swift
@Observable
final class FeedConflictsCenter {
    private(set) var pendingFeedIds: Set<String> = []
    func notify(feedId: String) { pendingFeedIds.insert(feedId) }
    func resolved(feedId: String) { pendingFeedIds.remove(feedId) }
}
```

Wire `var feedConflicts = FeedConflictsCenter()` onto `AppState`. `CompanionFeedsView` watches it; when the set is non-empty, presents the `FeedSettingsConflictSheet` for the first matching feed (FIFO). Sheet calls `appState.feedConflicts.resolved(feedId)` on dismiss.

### Step 9 — Telemetry

Log 412s through the existing `os.Logger` plumbing. Two log points:
- `SyncManager.executeAction` (Step 5): `logger.warning("412 conflict on feed_settings for \(feedId) — parked")` — already in the snippet above.
- A counter on `AppState.feedConflicts.totalSeen: Int` (incremented in `notify`) — surfaced in the existing **Settings → Advanced → Sync queue** panel as "Sync conflicts: N" alongside the dead-letter count. Reset to 0 on app launch (in-memory only — this is debug telemetry, not user-facing audit).

Do not add a third-party analytics dependency. Logger output is sufficient.

### Step 10 — Hook for the (planned) sync queue inspector

The sibling spec (`.docs/ai/phases/sync-queue-inspector-spec.md`, not yet written) will need a way to enumerate conflicted actions and resolve them in-place. This spec exposes the surface area:

- `SyncManager.fetchConflictedActions() -> [PendingAction]` (Step 5).
- `SyncManager.resolveConflict(_:with:)` (Step 5).
- `PendingAction.conflictServerSnapshotJSON` carries the data needed to render the diff in the inspector.

No code in this spec lives in an inspector view — that's the sibling's job. Just keep the API surface stable.

---

## Interfaces and Data Flow

### iOS-internal interface changes

| Symbol | Change |
| --- | --- |
| `APIClient.rawRequest` | Adds `additionalHeaders` param; returns `(Data, HTTPURLResponse)`. |
| `APIClient.requestWithHeaders` | **New** typed overload returning `(T, [String: String])`. |
| `APIError.preconditionFailed(currentEtag:message:)` | **New** case. |
| `APIErrorDetail.currentEtag` | **New** optional field. |
| `FeedService.updateFeedSettings` | Adds `ifMatch: String?` param; returns `String?` (new etag). |
| `SupabaseManager.updateFeedSettings` | Mirror of above. |
| `SyncManager.updateFeedSettings` | Adds `ifMatch: String?` param. |
| `SyncManager.fetchConflictedActions()` | **New** read API. |
| `SyncManager.resolveConflict(_:with:)` | **New** mutate API. |
| `SyncManager.queueConflict(...)` | **New** internal helper for live-save 412s. |
| `PendingAction.state` / `.ifMatchEtag` / `.conflictServerEtag` / `.conflictServerSnapshotJSON` | **New** SwiftData fields, all optional/defaulted. |
| `CompanionFeed.settingsEtag` | **New** computed property. |
| `FeedSettingsETag.compute(...)` | **New** helper enum. |
| `FeedSettingsResolution` / `FeedSettingsFieldChoice` | **New** types. |
| `FeedConflictsCenter` | **New** `@Observable` on `AppState`. |

### Network contract (already shipped — for reference)

- Outbound: `PATCH /api/feeds/:id/settings` with `If-Match: p<0|1>m<int|empty>n<int|empty>` and JSON body `{ paused?, maxArticlesPerDay?, minScore? }`.
- Inbound success: `200 { ok: true, data: { etag: <new> } }`.
- Inbound conflict: `412 { ok: false, error: { code: "precondition_failed", message, currentEtag } }`. Note: server uses snake_case `current_etag` on the wire, decoder maps to camelCase via `convertFromSnakeCase`.

### File formats

`PendingAction.payload` JSON for `feed_settings` actions gains an optional `ifMatch` string. Decoding tolerates absence (old queue entries pre-upgrade).

---

## Edge Cases and Failure Modes

1. **Two devices race, both have the same starting etag.** Device A wins, server etag rotates. Device B's PATCH 412s. Device B parks the action; user resolves on Device B. Device A is unaware — no UI on A. ✅ Acceptable; the state is consistent on the server.
2. **User edits offline, then concurrent edit happens before they come online.** When SyncManager flushes, the queued PATCH 412s. Conflict sheet appears the next time `CompanionFeedsView` is foregrounded (and `feedConflicts.pendingFeedIds` is non-empty). The captured etag in the queued payload is from the offline-pre-edit moment, but that's correct — server compares to *current* state.
3. **User opens settings, idles 10 minutes, taps Save.** No re-fetch; stale etag sent; server 412s; conflict sheet appears. This is intentional — the alternative (re-fetch on every Save) is overkill for a rare race.
4. **Server snapshot fetch fails on 412 (rare network blip between PATCH and snapshot fetch).** Sheet renders in two-button mode (Keep server / Apply mine). User picks a side; resolution still works.
5. **User taps Merge, picks all-server values.** Equivalent to Keep server. Submitted resolution is `.allServer` — the action becomes a no-op PATCH (server values unchanged). Backend handles correctly (see line 204: `if (sets.length === 0) return c.json({ ok: true, data: null })` — actually we still send sets because we always include all three fields; the PATCH succeeds and returns the unchanged etag). Acceptable.
6. **`minScore = 0` vs `minScore = nil`.** These produce different etags (`n0` vs `n`). The save sheet always reads from a `@State Int` initialized from `feed.minScore ?? 0` — so the device's representation collapses nil → 0 on the way out. This is a pre-existing behavior; the etag computation must mirror what the device *sends*, not what the device *read*. Since the save sheet sends `0` after the user opens it, the etag computed at sheet-open from the original `feed.minScore` (which may be nil → "n" suffix) will not match if the user immediately taps Save without changing min score. **Fix:** compute the captured etag using the *displayed/initial* values in the sheet (i.e. `paused: feed.paused ?? false`, `maxArticlesPerDay: Int(maxArticlesPerDay), minScore: minScore`) — or, simpler, **only send `If-Match` for changed fields**. Implementer should pick the simpler path: compute the etag from what the server thinks the row is right now (the `CompanionFeed` source values), and send only changed fields plus the If-Match header. Since `min_score = 0` and `min_score = NULL` are both valid distinct states, the existing UI semantically conflates them — but the etag check will pass when the row is actually unchanged because we send the same thing the server has. This footgun should be called out in a `// FIXME:` comment but is not in scope to fix.
7. **Sheet dismissed while save in flight.** SwiftUI cancels the task on dismiss. Existing behavior — not changed by this spec.
8. **Dead-lettered action that's also a conflict.** Should not happen since `state` is `pending` XOR `conflict` XOR `deadletter`. If the user resolves a conflict → state goes `conflict → pending` → next sync run either succeeds or starts over from `retryCount = 0`. Worst case: rapid second concurrent edit → another 412 → re-park.
9. **App force-quit while conflict is pending.** SwiftData persists the `PendingAction` row including its `state = "conflict"`. Next launch: `CompanionFeedsView.onAppear` checks `sync.fetchConflictedActions()` and re-populates `appState.feedConflicts.pendingFeedIds`. Sheet re-presents.
10. **User unsubscribes from the feed while a conflict is parked.** The conflict references a feed_id that no longer has a subscription. On `resolveConflict`, the PATCH will return 404 from the server (no subscription row). Treat 404 as "user resolved by deletion" — delete the queued action with a debug log. Implementer adds a `case 404` branch in the conflict-resolution flow.

---

## Test Plan

### Build verification

```
xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Must succeed clean.

### Unit-test seam

Add `FeedSettingsETagTests` (Swift Testing under `NebularNews/NebularNewsTests/`, follow existing test conventions if present; if no test target exists, skip and document the gap):

- `compute(paused: true, maxArticlesPerDay: nil, minScore: nil)` → `"p1mn"`
- `compute(paused: false, maxArticlesPerDay: 100, minScore: 3)` → `"p0m100n3"`
- `compute(paused: false, maxArticlesPerDay: nil, minScore: 0)` → `"p0mn0"`

Match the server's output for the same inputs (run `node` against `subscriptionEtag` to cross-check before shipping).

### Manual scenario tests

**Scenario A — single device, no conflict**
- Open feed settings, change `paused` from off to on, tap Save.
- Network log shows `If-Match: p0m...n...` header.
- Response captured. No conflict sheet.
- Re-open settings: paused state reflects new value.

**Scenario B — two-device conflict (the load-bearing test)**
- Sign into the same account on iOS (Device 1) and a second iOS device or Simulator (Device 2).
- On Device 1: open feed settings for any subscribed feed, do not change anything yet.
- On Device 2: open same feed's settings, change `min_score` from 0 to 3, Save. Confirm success.
- On Device 1: change `paused` to on, tap Save.
- **Expected:** conflict sheet appears showing Server `min_score = 3`, Mine `min_score = 0`, Server `paused = false`, Mine `paused = true`.
- Pick **Merge** → server min_score, mine paused → tap Submit.
- Reload settings on both devices. Both show `paused = true, min_score = 3`. ✅

**Scenario C — offline edit then concurrent edit**
- Device 1: airplane mode on. Edit feed settings, Save (queues offline).
- Device 2: edit same feed's settings to a different state, Save.
- Device 1: airplane mode off. SyncManager flushes.
- Device 1 surfaces the conflict sheet. User resolves.

**Scenario D — stale etag from idle**
- Open feed settings on Device 1 (note the feed state).
- On Device 2, change a value and save.
- Wait 10+ minutes on Device 1, then tap Save without changing anything.
- Expected: conflict sheet appears (stale If-Match). User picks Keep server → action no-ops cleanly.

**Scenario E — feed deleted between conflict and resolution**
- Conflict parks an action.
- User unsubscribes from the feed.
- User taps Resolve on the conflict sheet → 404 → action quietly deleted with debug log.

**Scenario F — server snapshot fetch fails**
- Simulate by killing network between PATCH (412) and the snapshot fetch (e.g. set the device offline immediately after seeing the 412 in logs).
- Sheet renders in two-button mode (Keep server / Apply mine).

### Verification commands

```
xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

```
xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 16' build CODE_SIGNING_ALLOWED=NO
```

(Backend is unchanged. No `wrangler deploy` needed.)

### Acceptance criteria

- [ ] iOS computes ETags locally that match the server byte-for-byte (verified against `node -e 'console.log(\`p${1}m${100}n${3}\`)'` for at least 3 input combinations).
- [ ] `PATCH /feeds/:id/settings` requests sent from the iOS save sheet include `If-Match` header. Confirmed via Charles or `xcrun simctl` proxy.
- [ ] Successful PATCH captures the new etag from `data.etag` (does not require persistence — the next read recomputes from values).
- [ ] On 412, the queued `PendingAction` row transitions to `state = "conflict"` (not retry, not dead-letter). Confirmed via DB inspector or `sync.fetchConflictedActions().count`.
- [ ] `FeedSettingsConflictSheet` presents automatically on the next foreground of `CompanionFeedsView` when a conflict is pending.
- [ ] Sheet renders three columns (Field / Server / Mine) and a per-row picker; three primary actions (Keep server / Apply mine / Merge).
- [ ] Two-device race test (Scenario B) ends with both devices showing the resolved state after the next reload.
- [ ] Offline-then-conflict test (Scenario C) surfaces the conflict sheet on next sync.
- [ ] Stale-etag test (Scenario D) surfaces the conflict sheet on Save.
- [ ] Feed-deleted-mid-conflict test (Scenario E) does not crash and quietly drops the action.
- [ ] Snapshot-failed test (Scenario F) falls back to two-button sheet.
- [ ] `os_log` shows a `[SyncManager]` warning line each time a 412 lands. Counter on `AppState.feedConflicts.totalSeen` increments correspondingly.
- [ ] No `xcodebuild` warnings introduced. Builds clean on both `platform=macOS` and `platform=iOS Simulator`.
- [ ] Existing flows unaffected: subscribing, unsubscribing, scrape mode picker, dead-letter UI, OPML import/export. Smoke test all five after change.

---

## Handoff

**Recommended tier:** Sonnet implementer (medium reasoning). The plan is decision-complete and bounded to ~8 files; no architectural judgment required. Mechanical-tier (Haiku/cheaper) would struggle with the SwiftData state-field migration semantics and the SwiftUI sheet presentation choreography.

**Files likely touched:**

- `NebularNews/NebularNews/Services/APIClient.swift` (extend headers + 412 branch + typed overload)
- `NebularNews/NebularNews/Services/FeedService.swift:40` (add ifMatch param, capture new etag)
- `NebularNews/NebularNews/Services/SupabaseManager.swift:132` (mirror signature)
- `NebularNews/NebularNews/Services/SyncManager.swift:208,338` (412 branch in executeAction, ifMatch param, conflict resolution helpers)
- `NebularNews/NebularNews/Services/FeedSettingsETag.swift` (**new**)
- `NebularNews/NebularNews/Models/PendingAction.swift` (4 new optional fields)
- `NebularNews/NebularNews/Features/Companion/CompanionModels.swift:229` (settingsEtag computed property)
- `NebularNews/NebularNews/Features/Companion/CompanionFeedsView.swift:420` (FeedSettingsSheet captures etag, surfaces 412)
- `NebularNews/NebularNews/Features/Companion/FeedSettingsConflictSheet.swift` (**new**)
- `NebularNews/NebularNews/App/AppState.swift` (FeedConflictsCenter)

**Constraints for the implementer:**

- **Do not change the backend.** ETag emission and the 412 contract are settled in `nebularnews/src/routes/feeds.ts:155-221` and shipped to production. Verify the wire format only — do not edit.
- **Do not re-fetch on sheet open.** The user explicitly chose the simpler path: send the stale etag and let the server 412.
- **Keep the SyncManager API surface additive.** Existing callers must compile with the new `ifMatch:` defaulting to `nil`.
- **Snake-case wire / camel-case Swift.** Decoder uses `.convertFromSnakeCase` — `current_etag` decodes to `currentEtag`. Do not hand-roll.
- Match the existing house style (brief doc comments, `os.Logger` for warnings, no third-party deps, native SwiftUI Form/Picker only).
- One commit per logical step is fine; one squashed commit at the end is also fine. User preference: small descriptive commits, do not push without explicit ask.

**Remaining decisions for the user:**

None. All product decisions (3-way action set, per-field merge, in-memory ETag, simpler-stale-path on idle, telemetry as logger-only) were locked before this spec was written. Spec is ready for `spec-implementer`.

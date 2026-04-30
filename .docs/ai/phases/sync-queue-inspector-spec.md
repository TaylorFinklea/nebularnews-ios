# Phase Spec: Sync Queue Inspector (Settings → Advanced → Sync queue)

**Status:** Draft (2026-04-29)
**Tier:** Haiku — pure SwiftUI surface over an existing model. No new networking, no protocol changes.
**Sibling spec:** `.docs/ai/phases/feed-settings-conflict-spec.md` (412 conflict resolver — produces the `conflict` row state consumed here).

---

## Product Overview

Give users a transparent, calm view of the offline mutation queue so they can answer the only two questions that matter when something they tapped didn't appear to take effect:

1. **"Is it queued, or did it fail?"** — answered by the read-only Pending list.
2. **"It failed forever — what now?"** — answered by the Dead-letter triage section, with retry / discard / report actions.

This is an *operator-grade trust surface*, not a power tool. Pending items already self-resolve via the existing 10-retry policy in `SyncManager`; surfacing them to the user is purely informational and reassures them that taps weren't dropped. All actions are concentrated in the dead-letter section, where the queue has given up and the user genuinely needs to choose.

The screen is hidden behind Settings → Advanced and shows a count badge (pending or dead-letter, whichever is non-zero) so that a healthy queue is invisible and an unhealthy one is visible without nagging.

**Audience:** Power users who hit network flakiness, the TestFlight cohort doing airplane-mode device verification on M12 Track A, and (most importantly) us when triaging support reports.

---

## Current State

### Already shipped (M12 Track A — `current-state.md` lines 96–127)

- `Services/SyncManager.swift` (`@MainActor @Observable`) is the offline mutation queue.
  - `maxRetries = 10`, FIFO replay on `NWPath` restoration.
  - Pending vs dead-letter is partitioned by `retryCount < 10` vs `>= 10`.
  - Helpers exist: `fetchPendingActions()`, `fetchDeadLetterActions()`, `retryDeadLetter(_:)`, `discardDeadLetter(_:)`, `pendingActionCount`, `deadLetterActionCount`, `hasPendingAction(forResource:)`.
  - Post-sync `WidgetCenter.reloadAllTimelines()` already wired.
- `Models/PendingAction.swift` has: `id`, `actionType`, `articleId` (overloaded as resource id — feed id / article id / feed URL for `subscribe_feed`), `payload` (JSON string), `createdAt`, `retryCount`, `lastError`.
- Action types currently in flight: `read`, `save`, `reaction`, `tag_add`, `tag_remove`, `feed_settings`, `subscribe_feed`, `unsubscribe_feed`, `reading_position`.
- `App/AppState.swift` exposes `syncManager: SyncManager?` (line 30).

### Not yet shipped — this spec

- No UI exists for the user to see, retry, discard, or report queued items.
- No "Advanced" section in `SettingsView.swift` (`Features/Settings/SettingsView.swift`).
- No `conflict` flag on `PendingAction` yet — the sibling 412 spec adds it; this spec's row UI assumes a `lastError` string contains a sentinel substring (`"412 Precondition Failed"` or a typed `lastConflict: Bool` field, whichever the sibling spec settles on). Implementer must consult the sibling spec at implementation time and pick the same source of truth.

### Sibling spec dependency

`.docs/ai/phases/feed-settings-conflict-spec.md` introduces a row state where a queued `feed_settings` action collides with newer server state. This inspector renders such rows with a special "conflict" icon and a tap-to-resolve CTA that opens the conflict diff sheet that the sibling spec owns. **This spec does not own the diff sheet** — only the row treatment and routing into it.

---

## Architecture

### File layout (new)

```
NebularNews/NebularNews/Features/Settings/
  ├── AdvancedSettingsView.swift                (new — Settings → Advanced root)
  ├── SyncQueueInspectorView.swift              (new — full-screen list)
  ├── SyncQueuePendingRow.swift                 (new — read-only row)
  ├── SyncQueueDeadLetterRow.swift              (new — actionable row)
  └── SyncQueueRowDescriptor.swift              (new — view-model for both row types)
```

### Data flow

1. `SettingsView` gains a new `Advanced` section with a `NavigationLink` to `AdvancedSettingsView`. Trailing badge shows count.
2. `AdvancedSettingsView` is a small `List` that has at minimum a `Sync queue` row (also badged) navigating to `SyncQueueInspectorView`. Future advanced settings can live alongside it.
3. `SyncQueueInspectorView` reads from `appState.syncManager` via `@Environment(AppState.self)`.
   - Calls `fetchPendingActions()` and `fetchDeadLetterActions()` at `.task` and refreshes:
     - on `.refreshable` (pull-to-refresh),
     - whenever `syncManager.pendingActionCount` or `deadLetterActionCount` changes (Observable triggers re-render),
     - via a 5-second `Timer.publish` so the "next attempt in" countdown stays live while the screen is open. Cancel the timer on disappear.
4. Each row maps a `PendingAction` to a `SyncQueueRowDescriptor` (see Interfaces) that exposes pre-formatted fields (human-readable target, age string, retry count, next-attempt countdown, last-error tail, conflict flag).
5. Resource-name resolution uses `appState.articleCache`:
   - Article-scoped actions (`read`, `save`, `reaction`, `tag_add`, `tag_remove`, `reading_position`) → look up `CachedArticle.title` by `articleId`. Fall back to `"Article \(shortened-id)"` if not cached.
   - Feed-scoped actions (`feed_settings`, `unsubscribe_feed`) → look up `CachedFeed.title` from `appState.articleCache.getCachedFeeds()`. Fall back to `"Feed \(shortened-id)"`.
   - `subscribe_feed` → use the URL stored in `articleId` directly (already human-readable).

### View hierarchy

```
SyncQueueInspectorView
├── (empty state) — when both lists are empty
├── Section "Pending" (read-only)
│   └── ForEach pendingDescriptors → SyncQueuePendingRow
├── Section "Needs attention" (dead-letter triage; only rendered when non-empty)
│   └── ForEach deadLetterDescriptors → SyncQueueDeadLetterRow
└── Section "About this queue" (footer, always present)
    └── small explanatory paragraph + last-synced timestamp
```

---

## Files Touched

**New (5):**

- `NebularNews/NebularNews/Features/Settings/AdvancedSettingsView.swift`
- `NebularNews/NebularNews/Features/Settings/SyncQueueInspectorView.swift`
- `NebularNews/NebularNews/Features/Settings/SyncQueuePendingRow.swift`
- `NebularNews/NebularNews/Features/Settings/SyncQueueDeadLetterRow.swift`
- `NebularNews/NebularNews/Features/Settings/SyncQueueRowDescriptor.swift`

**Modified (2):**

- `NebularNews/NebularNews/Features/Settings/SettingsView.swift` — add an `Advanced` section above the existing `Account` section (or directly above `About`, implementer's choice — keep `Sign Out` as the final destructive entry). The new section contains exactly one row: `NavigationLink("Advanced") { AdvancedSettingsView() }` with a trailing badge showing combined queue count when non-zero.
- `NebularNews/NebularNews/Xcode project file` — add the 5 new files to the `NebularNews` target. (Use Xcode's "Add Files…" or edit `project.pbxproj` per the repo's existing pattern; do not create a new framework target.)

**NOT modified — out of scope:**

- `Services/SyncManager.swift` — already exposes everything needed.
- `Models/PendingAction.swift` — only the sibling 412 spec may add a `lastConflict` flag; this spec consumes whatever it produces.
- Any networking, scoring, widget, or AI code.

---

## Interfaces and Data Flow

### `SyncQueueRowDescriptor` (new value type)

```swift
struct SyncQueueRowDescriptor: Identifiable, Hashable {
    let id: String                      // PendingAction.id
    let actionType: String              // raw — e.g. "feed_settings"
    let actionLabel: String             // localized — e.g. "Pause feed"
    let actionIcon: String              // SF Symbol name
    let targetTitle: String             // human-readable: feed/article title or fallback
    let targetSubtitle: String?         // optional second line: e.g. "Tag: evergreen"
    let enqueuedAge: String             // e.g. "2 min ago"
    let retryCount: Int                 // 0…maxRetries
    let nextAttemptCountdown: String?   // nil for dead-letter; e.g. "in 12s" otherwise
    let lastErrorTail: String?          // truncated error message (max 80 chars)
    let isConflict: Bool                // sibling-spec sourced
    let rawPayloadJSON: String          // for "Report" debug log
}
```

### Action-type → label / icon mapping (locked)

| `actionType`         | Label                  | SF Symbol                     |
| -------------------- | ---------------------- | ----------------------------- |
| `read`               | "Mark read"            | `checkmark.circle`            |
| `save`               | "Save article"         | `bookmark`                    |
| `reaction`           | "Set reaction"         | `hand.thumbsup`               |
| `tag_add`            | "Add tag"              | `tag`                         |
| `tag_remove`         | "Remove tag"           | `tag.slash`                   |
| `feed_settings`      | "Update feed settings" | `slider.horizontal.3`         |
| `subscribe_feed`     | "Add feed"             | `plus.rectangle.on.rectangle` |
| `unsubscribe_feed`   | "Remove feed"          | `minus.rectangle`             |
| `reading_position`   | "Save reading position"| `book`                        |
| (unknown / fallback) | The raw `actionType`   | `questionmark.circle`         |

The label must use the *natural* phrasing for that mutation, not the verb form. Examples:

- `read` → "Mark read" (not "Set isRead = true").
- `save` payload `saved=false` → "Unsave article". Decode payload to choose label when boolean state changes the verb. Same for `reaction` (negative value → "Set reaction" still — don't try to be clever).

### Pending row layout (read-only)

```
[icon]   Pause feed                                    2 min ago
         The Verge · attempt 3 of 10                   in 12 s
         [error tail, 1 line, .secondary, optional]
```

- Two lines (HStack of icon + VStack of three Text rows). Trailing column shows enqueued-age top, next-attempt countdown bottom.
- `attempt N of 10` is shown only when `retryCount > 0`, otherwise show only `enqueuedAge`.
- `nextAttemptCountdown` text:
  - When `syncManager.isOffline` → render `Waiting for network` (with `wifi.exclamationmark` icon prefix).
  - When online and `retryCount == 0` → render `Sending…`.
  - When online and `retryCount > 0` → render `in Xs` derived from a backoff schedule. **Backoff is approximate** — the current `SyncManager` retries the *whole queue* on next `NWPath` event, not on a per-row timer. So show: `in <60s` while `Date().timeIntervalSince(action.createdAt) < 60`, otherwise `Pending next sync`. No fake precision.
- Conflict state: when `isConflict`, prepend `exclamationmark.triangle.fill` (`.orange`), replace the bottom-right column with text `Tap to resolve`, and make the entire row tappable → opens the conflict diff sheet from the sibling spec via `.sheet(item:)` bound to a `@State var resolvingAction: PendingAction?`. Non-conflict pending rows are NOT tappable (no chevron, no `NavigationLink`).
- No swipe actions on pending rows. No edit mode.

### Dead-letter row layout

Same visual top line as pending row, but:

- `attempt 10 of 10 — failed` in red `.secondary`.
- Last-error tail shown unconditionally (one line, truncated, `.callout` `.secondary`).
- Trailing chevron — row tap pushes a detail sheet `SyncQueueDeadLetterDetailSheet` showing:
  - Action type (raw + label)
  - Target (human-readable + raw id)
  - Enqueued (full date)
  - Attempts: 10
  - Full last error (no truncation)
  - Decoded payload (pretty JSON, monospaced, scrollable, max 200pt height)
  - Three primary buttons (vertical `Button` stack):
    1. **Retry now** — calls `syncManager.retryDeadLetter(action)` then `await syncManager.syncPendingActions()`. Dismiss sheet on success.
    2. **Discard** — `.destructive`, opens confirmation alert (see "Discard confirmation copy" below).
    3. **Report** — see "Report action" below.

Swipe actions on the dead-letter row (List context, no need to enter the detail sheet for fast triage):

- `.swipeActions(edge: .trailing)` → "Retry" (`.tint(.blue)`), "Discard" (`.destructive`).
- `.swipeActions(edge: .leading)` → "Report" (`.tint(.indigo)`).

### Discard confirmation copy

Use a SwiftUI `.alert` with title "Discard this action?" and a body that *enumerates what's lost*. The body is built per action type:

| `actionType`         | Body line                                                                  |
| -------------------- | -------------------------------------------------------------------------- |
| `read`               | "The unread/read change for *<article title>* will be lost."               |
| `save`               | "The save/unsave change for *<article title>* will be lost."               |
| `reaction`           | "Your reaction on *<article title>* will be lost."                         |
| `tag_add`            | "The tag *<tag name>* will not be added to *<article title>*."             |
| `tag_remove`         | "The tag will not be removed from *<article title>*."                      |
| `feed_settings`      | "Your settings change for *<feed title>* will be lost (\<diff summary\>)." |
| `subscribe_feed`     | "*<feed URL>* will not be added to your feeds."                            |
| `unsubscribe_feed`   | "*<feed title>* will not be removed."                                      |
| `reading_position`   | "Your reading position for *<article title>* will be lost."                |

Buttons: `Discard` (`.destructive`) and `Cancel`. Italics in the table above are markdown emphasis only — render plain text via `Text(verbatim:)` or interpolation; do not invoke AttributedString.

Bulk discard: provide a `Discard all` button in the dead-letter section header (right side) when count > 1. Same alert pattern, body text: `"\(count) actions will be permanently discarded. Their changes will not be applied."`.

### Report action

Pure local — no server upload (the server-side `debug_log` table from M12 is for AI tool errors, not iOS client errors).

1. Build a redacted JSON document:
   ```json
   {
     "schemaVersion": 1,
     "capturedAt": "<ISO8601>",
     "appVersion": "<CFBundleShortVersionString> (<CFBundleVersion>)",
     "actionType": "<raw>",
     "resourceId": "<articleId field>",
     "createdAt": "<ISO8601>",
     "retryCount": <int>,
     "lastError": "<full string>",
     "payload": <decoded JSON object — see redaction rules>
   }
   ```
2. Redaction rules (apply to the `payload` field before serializing):
   - Strip any string ≥ 256 chars (replace with `"<redacted: length=N>"`).
   - For `subscribe_feed`, drop the URL's query string (keep host + path).
   - Never include the bearer token, keychain values, or any `x-user-api-key` header — none of these are stored in `PendingAction` so this is a defense-in-depth comment.
3. Log via existing `os.Logger`:
   ```swift
   logger.error("sync-queue-report \(redactedJSON, privacy: .public)")
   ```
   using the SyncManager's existing `Logger(subsystem: "com.nebularnews", category: "SyncManager")` *or* a new dedicated `category: "SyncQueueInspector"` — implementer pick whichever lets the user run `log show --predicate 'subsystem == "com.nebularnews" AND category == "SyncQueueInspector"' --last 1h` cleanly. Recommendation: new category.
4. Surface a share sheet (`ShareLink`) populated with the same JSON, plain text, so the user can paste into a TestFlight feedback message or email it to support.
5. After the share sheet dismisses, do NOT auto-discard the action. Report is observation-only.

### Empty state

When `pendingActions.isEmpty && deadLetterActions.isEmpty`:

- Use `ContentUnavailableView` with:
  - System image: `checkmark.icloud`
  - Title: "All caught up"
  - Description: "There's nothing waiting to sync. Edits you make offline will appear here until they reach the server."

### "Sync queue" link badge (in `AdvancedSettingsView`)

Show a SwiftUI `.badge(_:)` on the `Sync queue` `NavigationLink` row when **either** list is non-empty:

- `pendingCount > 0 && deadLetterCount == 0` → `.badge(pendingCount)` with default tint.
- `deadLetterCount > 0` → `.badge(deadLetterCount)` AND tint the badge text red via `.tint(.red)` on the row, **and** prefix the row label with a small `exclamationmark.triangle.fill` SF Symbol so the dead-letter case stands out from the merely-pending case.

Same badge logic applies to the Settings root → Advanced row, but using **only** dead-letter count (we don't want a permanent badge on Settings just because the user tapped something half a second ago — pending counts settle on their own; dead-letter counts don't).

### Telemetry

Yes, log via `os.Logger` when the screen appears, with the current counts:

```swift
logger.info("sync-queue-inspector opened pending=\(pendingCount) deadLetter=\(deadLetterCount)")
```

This is local-only (Console.app / `log show`), no network. Useful for support triage and confirming the screen is being discovered. No analytics pipeline.

---

## Edge Cases and Failure Modes

1. **Action completes while detail sheet is open.** The `PendingAction` is `modelContext.delete`d by `SyncManager.syncPendingActions()`. SwiftData property access on a deleted model crashes. Mitigation: detail sheet binds to a *snapshot copy* of the descriptor (already a struct), not to the live `PendingAction`. Resolve `.retryNow` / `.discard` by re-fetching by `id` at action time and no-op-with-toast if not found ("This action already synced").
2. **`syncManager` is nil.** Pre-auth or pre-modelContext setup. Render the empty state with subtitle "Queue not ready yet — try again in a moment." instead of crashing on force-unwrap.
3. **Dead-letter retry succeeds but pending count goes UP** because user kept tapping during sync. Expected — counts are live and Observable. No special handling.
4. **Unknown action type.** A future `actionType` value not in the mapping table. Render with the fallback label (raw string) and `questionmark.circle` icon, gray tint. Discard works; retry works (it'll just hit the `default` branch in `SyncManager.executeAction` and log a warning); report captures the raw payload.
5. **Resource title resolution fails.** Article was evicted from `ArticleCache` after the action was queued. Fall back to `"Article <prefix(8)>"` and shorten the article id. Don't block — the user still sees what type of action it is.
6. **Action with same id appears twice in fetch.** Should not happen given unique-id constraint on `PendingAction.id`, but if it does, dedupe in the descriptor mapping by `Set<String>` before rendering.
7. **Rapid retry tap.** Disable the Retry button for ~1s after tap (or until `syncPendingActions()` returns) to prevent double-fire.
8. **Conflict row tapped while offline.** Conflict resolution requires a server roundtrip. Show inline alert "Connect to the internet to resolve conflicts." Do not open the diff sheet.
9. **Discard during sync.** `modelContext.delete` of an action that `syncPendingActions()` is concurrently iterating is racy. Both code paths run on `@MainActor`, so they serialize, but the iteration cursor is over an array snapshot taken at function start — a deletion during iteration is safe. No mitigation needed; documenting for the implementer's awareness.
10. **VoiceOver.** Each row's `accessibilityLabel` should read: `"<actionLabel>. <targetTitle>. <retryDescription>. \(isConflict ? "Conflict — double-tap to resolve." : "")"`. Pending rows are `.accessibilityElement(children: .combine)`. Dead-letter rows expose three `.accessibilityActions`: Retry, Discard, Report.
11. **Dynamic Type / largest accessibility size.** The row layout is two-line with trailing column — at AX5, trailing column should wrap below instead of truncating. Use `ViewThatFits` or move trailing column into the VStack at compact sizes.
12. **Mac Catalyst.** No `WidgetKit` reload occurs there but the inspector itself works identically. No separate code path.

---

## Test Plan

### Build verification

```
xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Build must succeed with zero new warnings. Implementer must mention if any pre-existing warnings can't be avoided.

### Unit tests (preferred — Swift Testing)

Add to `NebularNewsKitTests` or a new `NebularNewsTests` target if none exists. **Required cases:**

- [ ] `SyncQueueRowDescriptor.from(_:cache:)` produces correct label + icon for every `actionType` listed in the mapping table, including the fallback for unknown types.
- [ ] `save` payload `saved=false` produces label `"Unsave article"`.
- [ ] Resource title resolution falls back to `"Article <prefix>"` when the cache returns nil.
- [ ] Discard confirmation body string matches the table for each `actionType` (snapshot tests acceptable).
- [ ] Redaction: a payload with a 1000-char string is replaced with `"<redacted: length=1000>"`.
- [ ] Redaction: `subscribe_feed` URL `https://example.com/path?token=abc` becomes `https://example.com/path` (query stripped) in the report JSON.

### Manual / on-device acceptance

Run on a real device (TestFlight or local install) — Simulator does not faithfully reproduce `NWPath` transitions:

- [ ] Open Settings → Advanced → Sync queue with **online, healthy queue** → empty state renders with `checkmark.icloud` and "All caught up" copy.
- [ ] Settings root → Advanced row shows **no badge** when dead-letter count is 0 (even if pending count > 0).
- [ ] Inside Advanced view, the Sync queue row **does** show a numeric badge when pending count > 0 (gray/default tint), and a **red** badge with leading `exclamationmark.triangle` when dead-letter count > 0.
- [ ] **Airplane Mode flow:**
  - [ ] Enable airplane mode, perform 4 mutations: mark one article read, save another, pause one feed, add a tag.
  - [ ] Open inspector → 4 rows in Pending section, each with the right label, target name (article/feed title resolved), age string, "Waiting for network" indicator.
  - [ ] Disable airplane mode → within 5 seconds the list empties and you land in the empty state without leaving the screen.
  - [ ] Widget reflects new unread/saved counts within 15 s of sync without app relaunch (this re-tests the existing Track A criterion through the inspector's surface).
- [ ] **Force-quit persistence:** repeat the airplane-mode flow, then force-quit the app *before* re-enabling network. Re-launch with network on → inspector starts empty (all 4 actions replayed during cold launch).
- [ ] **Dead-letter triage:**
  - [ ] Manually inject a `PendingAction` with `retryCount=10` via Xcode debugger or a debug-only seeding affordance (do not commit the seeding affordance).
  - [ ] Inspector shows it under "Needs attention" with red-tinted text and full error.
  - [ ] Swipe right → Discard → confirmation alert body lists the correct lost-state line for the action type → Discard confirms → row disappears.
  - [ ] Swipe right → Retry → row moves back to Pending and either succeeds or re-fails.
  - [ ] Tap row → detail sheet shows decoded payload, three buttons. Report button opens share sheet with redacted JSON. The same JSON appears in `log show --predicate 'subsystem == "com.nebularnews" AND category == "SyncQueueInspector"' --last 5m`.
  - [ ] Section header shows "Discard all" when count > 1; tapping triggers bulk-discard alert with "N actions will be permanently discarded." copy.
- [ ] **Conflict row (depends on sibling 412 spec being merged first):**
  - [ ] A queued `feed_settings` action that returns 412 displays with `exclamationmark.triangle.fill` (orange) and `Tap to resolve` instead of countdown text.
  - [ ] Tapping the row opens the conflict diff sheet owned by the sibling spec.
  - [ ] Tapping while offline shows the "Connect to the internet to resolve conflicts." alert and does **not** open the sheet.
- [ ] **Accessibility:**
  - [ ] VoiceOver reads each row's combined label correctly.
  - [ ] At AX5 Dynamic Type, no row's text is truncated; trailing-column data wraps below the title row.
- [ ] **Telemetry log:** `log show --predicate 'subsystem == "com.nebularnews" AND category == "SyncQueueInspector"' --last 5m` shows one `sync-queue-inspector opened ...` line per screen open.

### Acceptance criteria summary

- [ ] iOS macOS-destination build is clean.
- [ ] Pending list is read-only — no swipe actions, no buttons, no chevrons (except conflict rows).
- [ ] Dead-letter section never shows for an empty dead-letter list.
- [ ] Discard confirmation enumerates per-action-type lost state per the table.
- [ ] Report writes redacted JSON to `os.Logger` AND offers a `ShareLink` with the same JSON.
- [ ] Settings → Advanced badge is dead-letter-only; Sync queue row badge shows pending-or-dead-letter.
- [ ] All required unit tests in the table above pass.
- [ ] Airplane-mode device flow passes end-to-end.
- [ ] Force-quit persistence flow passes.

---

## Hand-off

**Tier:** Haiku (Mechanical → Implementation hybrid). Pure SwiftUI surface. No protocol changes, no networking, no schema changes, no AI work, no entitlements. Reuses existing `SyncManager` API surface.

**Files likely touched:** 5 new SwiftUI files + 1 modified Settings file + 1 Xcode project file change. ≈400–600 net new lines including unit tests. No deletions.

**Constraints for the implementer:**

1. Do **not** add any new public API to `SyncManager`. Everything you need is already exposed (`fetchPendingActions`, `fetchDeadLetterActions`, `retryDeadLetter`, `discardDeadLetter`, `pendingActionCount`, `deadLetterActionCount`, `isOffline`, `syncPendingActions`).
2. Do **not** change `PendingAction`'s schema. The sibling 412 spec owns whatever conflict marker it needs; consume it via `lastError` substring match if no typed property is available at implementation time.
3. Do **not** create the conflict diff sheet — that's the sibling spec's deliverable. Just route into it via `.sheet(item:)`. If the sibling sheet view doesn't exist yet, leave a `// TODO(conflict-sheet): wire to ConflictResolverSheet from feed-settings-conflict-spec` placeholder so wiring is one-line trivial later.
4. Keep the screen single-file-per-view per the repo's existing pattern in `Features/Settings/`. Don't introduce a ViewModel layer — the data is already an Observable on `SyncManager`.
5. Use `ContentUnavailableView`, `ShareLink`, `.swipeActions`, `.badge`, `.alert`, and `.confirmationDialog` — these are all available at the project's deployment target. No third-party libraries.
6. Commit message convention from CLAUDE.md: small descriptive commit per the repo's style. Recommended single commit titled `feat(settings): add Sync queue inspector under Advanced`.

### Verification commands

```
# Build (macOS destination, no signing)
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO

# Unit tests (if a test target exists for the main app — implementer to confirm)
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO

# Read telemetry from device after manual test (run on the device-connected Mac)
log show --predicate 'subsystem == "com.nebularnews" AND category == "SyncQueueInspector"' --last 1h
```

If a test target doesn't exist for the main app, implementer should put unit tests in `NebularNewsKitTests` if the descriptor type can live in `NebularNewsKit`, or note the gap and ship the tests as targeted XCTest files in a future tooling pass.

---

## Open Questions

None blocking. Two notes for the user:

1. The "report" capture is **local-only** (`os.Logger` + `ShareLink`). If you'd later prefer a server upload to a `client_debug_log` table, that's a separate spec — keeping it local for now matches the privacy/cost posture of M12.
2. The "next attempt countdown" is **approximate** because `SyncManager` retries the whole queue on `NWPath` events, not on a per-row timer. The UI shows `Sending…` / `in <60s` / `Pending next sync` rather than fake-precise seconds. If you want true per-row backoff, that requires a small `SyncManager` change (per-row `nextAttemptAt`) and is out of scope here — flag if you want it, and I'll spec it as a follow-up.

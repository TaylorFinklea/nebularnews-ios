# Phase Spec: M10 — Platform Polish

## Goal

Make NebularNews feel native on every Apple surface the user can hold or glance at: iPad in portrait + landscape, Lock Screen widgets, on-device Live Activities, and an Apple Watch glance. M1–M9 shipped a great phone + Mac app. M10 is about *being everywhere the user already is* without making them open the app.

## Why now

- Phone + macOS feature parity is done (M5).
- Widgets are scaffolded (`NebularNews/NebularNewsWidgets/`) but only Stats supports Lock Screen sizes; the other two are home-screen-only.
- Live Activities are a 30-second visibility win for on-demand brief generation, which already takes 5–15 s and currently shows only an in-app spinner.
- The TestFlight cohort skews iPad-heavy (per user observation); iPad currently runs as a scaled iPhone.
- Watch is the only Apple surface with zero presence — even a thumbnail unread count would close the loop.

## Scope

### Tier 1 — Must ship

1. **iPad layout** — proper `NavigationSplitView` two/three-column behavior, regular size class detection, sheet-vs-popover policy, sidebar collapse/expand.
2. **Lock Screen widget completion** — extend `TopArticleWidget` and `ReadingQueueWidget` with `accessoryRectangular` + `accessoryInline`. Stats already has these.
3. **Live Activity for on-demand brief** — start when `/brief/generate` POSTs, end when SSE completes (or after 60 s timeout). Single attribute model: progress + first bullet preview.

### Tier 2 — Stretch (defer if time runs out)

4. **Apple Watch glance** — new watchOS target, single complication (`accessoryCircular` unread count), simple list view of top 5 articles (read-only). No reader, no actions.

### Explicitly out of scope

- Live Activity for feed polling (poll is server-side cron — no user-triggered surface to attach to).
- Watch authentication flow — Watch reads from a shared App Group keychain populated by the phone's pairing handshake; no QR code or independent sign-in.
- iPad keyboard shortcuts beyond the existing macOS set.
- iPad pencil/scribble for highlights (M8 highlights still use paste-alert MVP).
- StandBy mode customization (uses default widget rendering).

---

## Approach

### Workstream 1 — iPad layout (`NebularNews/NebularNews/`)

**Current state:** App uses `NavigationStack` on iOS and `NavigationSplitView` on macOS (M5). On iPad it falls back to the iOS path → scaled phone.

**Changes:**

1. **Detect iPad regular size class** in `NebularNewsApp.swift` or a top-level container. Use `@Environment(\.horizontalSizeClass)` to switch root layout: compact → existing iOS stack, regular → split view (same component already used for macOS).
2. **Reuse macOS `NavigationSplitView` layout** — the existing 3-column layout (sidebar / article list / detail) should drop in unchanged on iPad regular. Verify `NavigationSplitViewVisibility` defaults look right on iPad portrait (probably `.doubleColumn`) vs landscape (`.all`).
3. **Sheet → popover** policy in regular size class: `AddFeedSheet`, `FeedSettingsSheet`, AI assistant FAB sheet should present as popover anchored to the trigger button, not full-screen modal. Use `.popover(isPresented:)` gated on size class.
4. **Article reader**: ensure `.frame(maxWidth: 720)` on the body content so text columns don't sprawl across the iPad detail pane.
5. **AI assistant FAB position** — currently bottom-right; on iPad regular, anchor to the detail pane's bottom-right, not the window's, so it doesn't overlap the article list.
6. **Test matrix**: iPad mini portrait, iPad Pro 13" landscape, Slide Over, Stage Manager.

**Critical files:**
- `NebularNews/NebularNews/NebularNewsApp.swift` — root layout switch
- `NebularNews/NebularNews/SharedViews/RootContainerView.swift` (or equivalent) — split-view selector
- `NebularNews/NebularNews/Features/Feeds/AddFeedSheet.swift` — popover gating
- `NebularNews/NebularNews/Features/Companion/CompanionArticleDetailView.swift` — reader max-width
- `NebularNews/NebularNews/Features/AI/AIAssistantFAB.swift` (or equivalent) — anchor position

### Workstream 2 — Lock Screen widgets (`NebularNews/NebularNewsWidgets/`)

**Current state:** `StatsWidget` already supports `accessoryRectangular`/`accessoryCircular`/`accessoryInline`. `TopArticleWidget` and `ReadingQueueWidget` are home-screen only.

**Changes:**

1. **`TopArticleWidget`** — add `accessoryRectangular` (top headline + source name in 2 lines) and `accessoryInline` (just headline truncated to ~30 chars).
2. **`ReadingQueueWidget`** — add `accessoryRectangular` (top 1 saved article + count). `accessoryInline` is overkill for queue.
3. **Widget data freshness**: today, `WidgetDataWriter` writes on app foreground/background. Add a write trigger after `POST /brief/generate` so the brief-bullet content reflects the latest brief. Also add a write trigger after `markRead`/`save` mutations so unread/saved counts stay accurate.
4. **Privacy**: Lock Screen widgets render in redacted state when device is locked and lock-screen-data setting is off. Use `.privacySensitive()` on article titles so they hide when privacy mode is on.
5. **Localization-friendly truncation**: use `.lineLimit(1)` + `.truncationMode(.tail)` rather than manual character counts.

**Critical files:**
- `NebularNews/NebularNewsWidgets/TopArticleWidget.swift` — add accessory family cases
- `NebularNews/NebularNewsWidgets/ReadingQueueWidget.swift` — add accessory family cases
- `NebularNews/NebularNews/Services/WidgetDataWriter.swift` — add post-brief/post-mutation triggers
- `NebularNews/NebularNewsWidgets/NebularNewsWidgets.swift` — declare new families in `supportedFamilies`

### Workstream 3 — Live Activity for brief generation

**Current state:** No ActivityKit usage. Brief generation shows a `ProgressView` in `BriefView`.

**Changes:**

1. **New ActivityAttributes model** in a shared file the main app and Widget extension both link:
   ```swift
   struct BriefActivityAttributes: ActivityAttributes {
       struct ContentState: Codable, Hashable {
           var stage: String        // "fetching" | "summarizing" | "done"
           var firstBullet: String? // populated as soon as SSE delivers first bullet
           var progress: Double     // 0.0 → 1.0
       }
       let editionLabel: String     // "Morning Brief" / "Evening Brief"
   }
   ```
2. **Live Activity widget** in `NebularNewsWidgets/` — implement `ActivityConfiguration` with three layouts (lock screen, dynamic island compact, dynamic island expanded).
3. **iOS BriefView trigger** — when user taps Generate Brief:
   - Start `Activity<BriefActivityAttributes>.request(...)` immediately with progress 0.0.
   - Update activity state from SSE events as bullets stream in.
   - End the activity with `.end(state, dismissalPolicy: .after(.now + 30))` once the brief is rendered, or after 60-s no-progress timeout.
4. **No remote push** — keep this purely local (`pushType: nil`). Skip APNs Live Activity push tokens for this milestone; brief generation completes within seconds, no need for backend push updates.

**Critical files:**
- `NebularNews/NebularNewsShared/BriefActivityAttributes.swift` — new shared file (may need to create a Shared framework or use `Target Membership` on both app + widget extension)
- `NebularNews/NebularNewsWidgets/BriefLiveActivity.swift` — new file
- `NebularNews/NebularNews/Features/Brief/BriefView.swift` (or wherever generate-brief lives) — start/update/end activity
- `NebularNews/NebularNews/Services/EnrichmentService.swift` (or `BriefService.swift`) — extend SSE handler to surface stage transitions

### Workstream 4 — Apple Watch glance (Tier 2 / stretch)

**Current state:** No watchOS target.

**Changes:**

1. **New watchOS app target** `NebularNewsWatch` in the Xcode project. SwiftUI lifecycle, watchOS 10+, share App Group + Keychain access group with iPhone app.
2. **Data path:** Watch reads from the same App Group container the widgets use (`WidgetDataProvider.loadStats()`, `loadTopArticles()`). No direct API calls from Watch — it mirrors what the iPhone last wrote.
3. **Single screen:** title bar shows unread count, list shows top 5 articles by score (title + source). Tap → opens article on iPhone via Handoff (`NSUserActivity`). No reader on Watch.
4. **Complication:** `accessoryCircular` showing unread count, deep-links to the Watch app.
5. **No standalone sign-in.** If App Group is empty (unpaired or never opened iPhone app), show a "Open NebularNews on your iPhone" empty state.

**Critical files:**
- New `NebularNewsWatch/` directory + Xcode target
- `NebularNewsWatch/WatchApp.swift`
- `NebularNewsWatch/TopArticlesListView.swift`
- `NebularNewsWatch/UnreadCountComplication.swift`
- App Group entitlement updates on both iPhone app and Watch app

---

## Acceptance criteria

### Must-ship (Tier 1)
- [ ] On iPad Pro 13" landscape, app shows 3-column split (sidebar | articles | detail). Tapping an article fills the detail pane without modal navigation.
- [ ] On iPad mini portrait, app shows sidebar collapsed by default, swipe-from-left reveals it.
- [ ] AddFeedSheet appears as a popover on iPad regular, not a full-screen modal.
- [ ] Lock Screen `accessoryRectangular` widget for top article shows headline + source.
- [ ] Lock Screen `accessoryInline` widget shows top headline as a single line above the time.
- [ ] Generating a news brief shows a Live Activity in the Dynamic Island (iPhone 15+) and on the Lock Screen, with progress, then the first bullet, then auto-dismisses 30 s after completion.

### Stretch (Tier 2)
- [ ] Apple Watch app shows unread count + top 5 articles, with `accessoryCircular` complication.
- [ ] Tapping a Watch article handoffs to the iPhone reader.

### Quality bars (apply to all)
- [ ] No regression in compact iPhone layout — single-column NavigationStack still works.
- [ ] No regression in macOS layout — split view unchanged.
- [ ] Widget extension still builds with no warnings.
- [ ] Privacy: Lock Screen widgets respect the system "Hide sensitive content" setting via `.privacySensitive()`.

---

## Verification

1. **Build matrix:**
   - `xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
   - `xcodebuild ... -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
   - `xcodebuild ... -destination 'generic/platform=watchOS Simulator' build CODE_SIGNING_ALLOWED=NO` (Tier 2)
2. **iPad simulator manual test:** iPad Pro 13" landscape + iPad mini portrait. Walk through AddFeed, open article, generate brief, FAB chat.
3. **Lock Screen widget:** add to Lock Screen on simulator (long-press lock screen → Customize), confirm rendering of all three accessory families per widget.
4. **Live Activity:** generate brief, observe Dynamic Island morphing (compact → minimal → expanded), Lock Screen presentation, auto-dismiss timing.
5. **Watch (Tier 2):** pair watchOS simulator, install companion, confirm complication updates after iPhone foregrounds.

---

## Risks & open questions

- **Shared file across app + widget extension** for `BriefActivityAttributes` — may require a new Shared framework target or careful `Target Membership` toggling. If it breaks the project file, fall back to duplicating the file in both targets (low cost — it's ~20 lines of model code).
- **Stage Manager edge case** on iPad — narrow window can re-trigger compact size class mid-session; ensure layout transitions don't flash or lose state.
- **Widget timeline budget** — adding new families increases the timeline reload cost. Confirm `getTimeline` for accessory families uses the same 30-min refresh interval, not per-minute.
- **Watch pairing UX** — first install will show empty state until iPhone app foregrounds and writes to App Group. Acceptable for stretch tier, but worth a one-line "Open the iPhone app to sync" message.
- **Renaming:** the roadmap calls this `M9: Platform Polish` (pre-deep-fetch numbering). Update `roadmap.md` to renumber to M10 + add a new M11 placeholder for the next horizon (likely AI assistant tool-calling, per `next-steps.md` deferred list).

---

## Follow-up (not this milestone)

- Live Activity remote push from server when scheduled brief cron generates the morning/evening brief — requires APNs Live Activity push token plumbing.
- Watch reader (read article body on Watch) — requires text rendering work + a separate scroll model.
- iPad multi-window / scene-based article opening (open multiple articles in separate windows).
- Carplay glance — out of product scope for now.
- StandBy mode custom layout for Lock Screen widgets when the iPhone is on a charger sideways.

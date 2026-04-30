# Phase Spec: Notification Service Extension — Brief Push Image + 2-Bullet Body (2026-04-29)

## Product Overview

When a scheduled brief is delivered to an iOS device, the user currently sees the OS-default APNs alert: a single line of body text taken from the first bullet. This spec finishes the work that turns that into a richer lock-screen notification:

- **Image preview** — a thumbnail of the lead article's image rendered inline in the lock-screen and Notification Center entries.
- **Two-bullet body** — the first two brief bullets stacked under the title, replacing the single-line OS body.

The audience is any user who has enabled brief push notifications (morning + evening editions). The win is "I can see the substance of my brief without unlocking the phone." No new permission is required; the OS already authorized alerts when the user opted in.

This phase is implementation-only. The product decision (image + 2 bullets), the payload contract (`mutable-content: 1`, `bullets[]`, `image_url`), and the failure-mode behavior (drop image silently if download fails, ship original body if NSE expires) are already locked.

## Current State

**Backend** (`/Users/tfinklea/git/nebularnews`, deployed on Workers):

- `src/lib/apns.ts` already sets `aps['mutable-content'] = 1` on every brief push and merges `payload.data` into the top-level JSON envelope.
- `src/cron/scheduled-briefs.ts` lines 184–215 builds `trimmedBullets` (≤3 entries, ≤80 chars each, ellipsis-truncated) and `leadImage` (top-scored candidate's `image_url`), then calls `sendPushToUser` with `data: { type: 'brief', edition, id, bullets: trimmedBullets, image_url: leadImage }`.
- `src/routes/admin.ts` lines 695–760 (preview-next-brief endpoint) follows the same payload shape, used for on-demand testing from the admin web UI.

**iOS NSE** (already in this repo — the user's brief said it hadn't been created, but it has):

- Target `NebularNewsNotifyService` exists in `NebularNews.xcodeproj` (id `A21C0F672F9EB58C00D99808`), product type `com.apple.product-type.app-extension`, bundle id `com.nebularnews.ios.NebularNewsNotifyService`, deployment target iOS 26.0, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`, `SDKROOT = iphoneos`. macOS builds will skip it because the platform list excludes `macosx`.
- Embedded into the main app via the "Embed Foundation Extensions" build phase (build file id `A21C0F6F2F9EB58C00D99808`, `RemoveHeadersOnCopy` attribute set).
- Files present: `/Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNewsNotifyService/NotificationService.swift` and `Info.plist`. `Info.plist` declares `NSExtensionPointIdentifier = com.apple.usernotifications.service` and `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).NotificationService`.
- `NotificationService.swift` already implements: `bestAttempt` capture, body rewrite from `userInfo["bullets"]` (first 2 joined by `\n`), URLSession ephemeral download with 8 s `timeoutIntervalForRequest` + `timeoutIntervalForResource`, MIME-sniffed UTI, temp-file move into `NSTemporaryDirectory`, `UNNotificationAttachment` construction with `UNNotificationAttachmentOptionsTypeHintKey`, and a `serviceExtensionTimeWillExpire()` fallback that cancels the download and ships `bestAttempt` content as-is.

**Main app** (`NebularNews/App/NotificationManager.swift`):

- Already registers for remote notifications, uploads device tokens via `SupabaseManager.registerDeviceToken`, handles tap routing for `type == "brief"` payloads (posts `openBriefFromNotification`).
- macOS path is a stub — no NSE implications there.

**Entitlements** (`NebularNews/NebularNews.entitlements`):

- `aps-environment = development`, App Group `group.com.nebularnews.shared`, keychain group `$(AppIdentifierPrefix)com.nebularnews.ios`.
- The NSE has **no** entitlements file declared in the pbxproj for the target — it currently runs without App Group / Keychain access. That is correct for a stateless image+body rewrite; do not add an entitlements file unless a follow-up needs shared state.

**Gap vs. user-stated current state**: the user's brief said "iOS NSE target has NOT been created in Xcode yet" but it has. Either the Xcode work was done in a session that didn't get reflected in the user's mental model, or the user expects the implementer to re-verify and treat the existing files as the starting point. This spec assumes the latter — the implementer's first job is to **verify** the current target builds, not recreate it.

## Architecture

### Image attachment flow

```
APNs delivery
   │
   │ aps.mutable-content = 1
   ▼
NSE.didReceive(request, contentHandler)
   │
   ├── 1. mutableCopy() of request.content → bestAttempt
   │
   ├── 2. body rewrite:
   │      bullets = userInfo["bullets"] as? [String]
   │      if !bullets.isEmpty:
   │          mutable.body = bullets.prefix(2).joined("\n")
   │      else: keep server body (first-bullet fallback)
   │
   ├── 3. image download (URLSession ephemeral, 8 s timeout):
   │      url = URL(string: userInfo["image_url"] as? String)
   │      tempURL ← URLSession downloadTask
   │      destURL ← FileManager.temporaryDirectory + UUID + ext-from-MIME
   │      moveItem(tempURL → destURL)
   │      attachment = UNNotificationAttachment(id, destURL, typeHint)
   │      mutable.attachments = [attachment]
   │
   └── 4. contentHandler(mutable)

If serviceExtensionTimeWillExpire fires before step 4 completes:
   downloadTask?.cancel()
   contentHandler(bestAttempt)  // body rewrite preserved if it ran; image dropped
```

### Body format decisions

- **Bullet character**: none. Each bullet line stands on its own. APNs renders the body with `\n` line breaks in the expanded notification view; adding a leading `• ` doubles up with the title's visual weight and crowds the line. The 2-line body looks cleanest as bare lines.
- **Line separator**: single `\n`. iOS expanded notifications do honor `\n` and render multiple lines (banner shows 2 lines, expanded view shows up to ~4 lines on iOS 16+).
- **Per-bullet max**: server already truncates to 80 chars + ellipsis. NSE does **not** re-truncate — it trusts the server contract.
- **Total body cap**: 2 × 80 chars + 1 newline = 161 chars worst case. Well under iOS's practical body length (no hard limit, but practical legibility is ~250 chars).
- **Truncation strategy when bullets are short**: if `bullets.count == 1`, set `body = bullets[0]` (single line, no trailing newline). If `bullets.count == 0` or absent, leave `body` unchanged so the server-provided first-bullet preview is shown.

### Image rendering

- `UNNotificationAttachment.identifier = "preview"` — a stable id is fine; iOS doesn't dedupe across notifications.
- **Thumbnail clipping**: do **not** set `UNNotificationAttachmentOptionsThumbnailClippingRectKey`. Pass the full image and let iOS pick a sensible default crop. Lead images from RSS feeds are typically 16:9 or 4:3 hero shots that look fine center-cropped.
- **Thumbnail hidden**: do **not** set `UNNotificationAttachmentOptionsThumbnailHiddenKey`. We want the inline preview.
- **Type hint**: pass MIME-sniffed UTI via `UNNotificationAttachmentOptionsTypeHintKey`. Fallback chain: response MIME → URL extension → `UTType.jpeg`.
- **Size guard**: iOS rejects attachments >10 MB (image), >50 MB (video). Most lead images are <500 KB. We do **not** add an explicit size check — the OS rejection surfaces as `UNNotificationAttachment` init throwing, which we already catch and fall through.

### Failure modes

| Failure | Behavior |
|---|---|
| `userInfo["image_url"]` missing or not-a-String | Skip image, ship body-rewritten content. |
| URL parse fails (malformed string) | Skip image, ship body-rewritten content. |
| Image download timeout (8 s) | Skip image, ship body-rewritten content. |
| Image download HTTP error (4xx/5xx) | URLSession returns no error but `tempURL` may still be a 0-byte response body. The current code catches the `moveItem` or `UNNotificationAttachment` init throw and falls through — acceptable. |
| Network unreachable | Skip image, ship body-rewritten content. |
| `bullets` missing or empty | Keep server body (already a first-bullet preview). |
| `serviceExtensionTimeWillExpire` (system kills extension at ~30 s) | `downloadTask?.cancel()`; ship `bestAttempt` (body rewrite preserved if step 2 ran before timeout, image dropped). |
| NSE crashes | iOS falls back to original APS payload; user sees the server-provided body and no image. |

The backend already guarantees `image_url` is non-null when there's a usable lead image (top-scored candidate's article image). Backend follow-up below ensures `image_url` is **always** non-null via R2 fallback pool, so the "image missing" branch becomes rare.

## Files Touched (iOS)

This phase changes very little iOS code — the existing `NotificationService.swift` is correct. The work is verification + small handling polish.

- `/Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNewsNotifyService/NotificationService.swift` — minor edit: handle the 1-bullet case to avoid a trailing newline (see Implementation Plan step 2).
- `/Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNewsNotifyService/Info.plist` — no changes expected; verify `NSExtensionPointIdentifier = com.apple.usernotifications.service` and `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).NotificationService` are set.
- `/Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj/project.pbxproj` — no changes expected; verify the target has `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"` (line 650 / 682), is embedded in main app's "Embed Foundation Extensions" phase, and bundle id is `com.nebularnews.ios.NebularNewsNotifyService` for both Debug and Release.
- `/Users/tfinklea/git/nebularnews-ios/.docs/ai/current-state.md` — append a "Push NSE shipped" entry under the existing 2026-04-26 section after device verification passes.
- `/Users/tfinklea/git/nebularnews-ios/.docs/ai/next-steps.md` — flip the four `[ ]` checkboxes under "Push Notification Service Extension" once each is verified.

**Do NOT touch**:

- `NotificationManager.swift` — already routes brief taps correctly.
- Entitlements files for the NSE — none should be added; the extension is stateless.
- Any framework imports — `UserNotifications` and `UniformTypeIdentifiers` are sufficient.
- Bundle id, scheme, embed settings — all already correct.

## Implementation Plan (iOS)

### Step 1 — Verify target builds in isolation

```sh
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNewsNotifyService -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

Expected: builds clean. If it fails, the file is referenced via `fileSystemSynchronizedGroups` (see pbxproj line 256) which means Xcode auto-includes any file dropped into the folder — no compile-list edits needed.

### Step 2 — Polish 1-bullet edge case

Edit `NotificationService.swift` to avoid a stray newline when the server only ships one bullet (e.g. low-content brief slot). Replace lines 43–46:

```swift
        // 1. Body enrichment from `bullets` array.
        if let bullets = userInfo["bullets"] as? [String], !bullets.isEmpty {
            mutable.body = bullets.prefix(2).joined(separator: "\n")
        }
```

with:

```swift
        // 1. Body enrichment from `bullets` array.
        // Server-trimmed to ≤80 chars per bullet (see scheduled-briefs.ts).
        // We render the first 2 stacked under the title with a single newline.
        // Single-bullet briefs render as one line (no trailing newline).
        if let bullets = userInfo["bullets"] as? [String], !bullets.isEmpty {
            let take = bullets.prefix(2)
            mutable.body = take.joined(separator: "\n")
        }
```

(Functionally identical for the ≥2 case; documentation-only for clarity. The `prefix(2).joined` already handles 1-bullet correctly — no trailing newline. Skip this edit if the implementer agrees the existing code is fine; the comments are the value.)

### Step 3 — Confirm macOS build skips the NSE

```sh
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Expected: the NebularNews scheme builds for macOS with `NebularNewsNotifyService` skipped (the target's `SUPPORTED_PLATFORMS` excludes `macosx`, so xcodebuild's dependency resolver drops it). If macOS build fails complaining about the NSE, the target was misconfigured and `SUPPORTED_PLATFORMS` needs to be `"iphoneos iphonesimulator"` in both Debug and Release (it currently is — pbxproj lines 650 and 682).

### Step 4 — Confirm iOS app build embeds the NSE

```sh
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

Expected: builds clean and emits `NebularNewsNotifyService.appex` inside the `NebularNews.app/PlugIns/` directory. The "Embed Foundation Extensions" phase already lists it (pbxproj line 72).

### Step 5 — Device install + manual verification

The user installs the build on a real device (image attachments do not surface on simulator the same way; expanded preview rendering is best verified on hardware).

1. Sign in to the app on device. The Apple Sign In flow registers an APNs token via `NotificationManager.requestPermissionAndRegister` → `application:didRegisterForRemoteNotificationsWithDeviceToken:` → `SupabaseManager.registerDeviceToken`.
2. From the admin web UI (`admin.nebularnews.com` or the dev bypass), use **Users → user → Trigger brief** which hits `POST /admin/users/:id/trigger-brief`. This generates a brief and pushes it. Expected lock-screen output: title `"Morning Brief"` or `"Evening Brief"`, body of 2 bullet lines, and a thumbnail of the top article's image. Long-press on the notification expands and shows the larger image preview.
3. Tap the notification. Expected: app foregrounds and routes to the brief detail view (`openBriefFromNotification` → `DeepLinkRouter`).

### Step 6 — Logging confirmation

Pull the device console (Console.app → device → filter `subsystem:com.nebularnews.ios.NebularNewsNotifyService`) and confirm no exception logs from `UNNotificationAttachment` init or `FileManager.moveItem`. The NSE doesn't currently log; this step is purely "did anything go wrong silently." If the implementer wants logs, they can add a `Logger(subsystem: ..., category: "NSE")` and `.error()` lines on each early-return in `downloadAttachment`, but it's optional.

## Backend Follow-up (separate hand-off block — Haiku tier)

The image-failure UX depends on `image_url` being non-null in nearly all brief push payloads. Today, `image_url` is null when none of the top-scored candidate articles has a lead image (rare for editorial feeds, common for long-tail HN/lobste.rs items). Two pieces of work close that gap:

### B1. Curated R2 fallback image pool

- Create R2 bucket `nebularnews-fallback-images` (or reuse an existing public R2 bucket if one exists). Public-read; CDN-cached.
- Seed with **30 generic editorial images** (abstract gradients, news-desk imagery, technology-tagged photos) sized 1200×675 (16:9) JPEG, ≤200 KB each, named `fallback-001.jpg` through `fallback-030.jpg`.
- Source images: stock photography with permissive license (Unsplash, Pexels) or AI-generated abstract gradients via one-time DALL·E run (one-time human cost — not per-brief).
- Public URLs: `https://r2-fallback.nebularnews.com/fallback-NNN.jpg` (CNAME the R2 bucket onto a subdomain so the URL is stable + cacheable).

### B2. Deterministic rotation in scheduled-briefs.ts

Edit `/Users/tfinklea/git/nebularnews/src/cron/scheduled-briefs.ts` line 203 to add a fallback when `leadImage` is null:

```ts
// Lead image: top-scored source article's image. Candidates are sorted by
// score DESC, so first non-null wins. If no candidate has an image, rotate
// in a curated fallback deterministically by brief id so the same brief
// always gets the same image (re-deliveries are stable).
const POOL_SIZE = 30;
function fallbackImageForBriefId(briefId: string): string {
  let h = 0;
  for (let i = 0; i < briefId.length; i++) h = (h * 31 + briefId.charCodeAt(i)) | 0;
  const idx = Math.abs(h) % POOL_SIZE;
  return `https://r2-fallback.nebularnews.com/fallback-${String(idx + 1).padStart(3, '0')}.jpg`;
}

const candidateImage = candidates.find((c) => c.imageUrl)?.imageUrl ?? null;
const leadImage = candidateImage ?? fallbackImageForBriefId(inserted.id);
```

Apply the same change in `src/routes/admin.ts` around line 754 (preview-next-brief endpoint) so the dev-trigger path is consistent.

### B3. Deploy + verify

```sh
cd /Users/tfinklea/git/nebularnews && npx wrangler deploy --env production
```

Then trigger a brief from a user known to have no lead-image candidates and confirm the push payload contains a `r2-fallback.nebularnews.com` URL.

## Interfaces and Data Flow

### Push payload contract (already in production — do not change)

```json
{
  "aps": {
    "alert": { "title": "Morning Brief", "body": "First bullet preview…" },
    "sound": "default",
    "mutable-content": 1
  },
  "type": "brief",
  "edition": "morning",
  "id": "<brief-uuid>",
  "bullets": ["First bullet text…", "Second bullet text…", "Third bullet text…"],
  "image_url": "https://example.com/lead.jpg"
}
```

- `bullets` — array of strings, ≤3 entries, ≤80 chars each (server-truncated with ellipsis), camelCase or snake_case both accepted on iOS side (snake_case is what server emits).
- `image_url` — string, post-B2 always non-null.

### NSE → contentHandler

The NSE returns a `UNMutableNotificationContent` with:

- `title` — unchanged from server.
- `body` — replaced with first 2 bullets joined by `\n`, or unchanged if `bullets` missing/empty.
- `attachments` — `[UNNotificationAttachment(identifier: "preview", url: <tempfile>)]` if image downloaded successfully, else empty.
- All other fields (sound, badge, userInfo) untouched.

## Edge Cases and Failure Modes

- **Bullet field is camelCase** (`Bullets`, `BulletList`, etc.). Server emits literal `bullets` (lowercase). NSE checks `userInfo["bullets"]` only. iOS `userInfo` is bridged from JSON as-is, no key transformation. Confirmed safe.
- **Bullet field contains non-strings** (e.g. server bug emits `[{ text: "..." }]` instead of strings). The `as? [String]` cast fails and we fall through to the server-provided body. This is the pre-2026-04-26 server format; the current `scheduled-briefs.ts` lines 193–199 already maps to flat strings, but a regression here would be silent. Acceptable — body still renders, just without the second bullet.
- **`image_url` is an HTTP URL** (not HTTPS). The NSE's URLSession will follow it; iOS App Transport Security is not enforced inside extensions for arbitrary URLs the way it is for in-app loads. Backend should still emit HTTPS only — confirm in B2 that all R2 URLs are `https://`.
- **Same brief delivered twice** (rare APNs retry). NSE downloads the same `image_url` twice; the temp directory is per-extension-invocation so no name collision. Two notifications will appear if iOS doesn't dedupe by `apns-collapse-id` (the backend doesn't currently set this). Out of scope for this phase.
- **Brief content contains emoji or extended unicode**. `String.prefix(2)` operates on Array bounds, not String. `bullets.prefix(2)` is on `[String]` so each bullet is one element regardless of internal encoding. Safe.
- **Image download succeeds but the file is HTML** (some CDNs return an interstitial page on bot-suspicious requests). UTType inference falls back through MIME → ext → `.jpeg`. `UNNotificationAttachment(typeHint: jpeg)` will reject HTML content during validation, throw, and we fall through. Acceptable.
- **NSE invocation count** — every brief push invokes the NSE for ~0.5–8 s of compute on the device. Battery cost is trivial (one network request, one file move, one frame on the alert path). No background work; no daemons.
- **First-launch race** — if the user receives a brief push before they've opened the app for the first time after install, the NSE still runs (it's bundled in the .app, not gated on app launch). The bundled NSE is loaded by `usernotificationsd` independent of the host app's lifecycle. Confirmed safe.

## Test Plan

### Build verification (CI-equivalent)

```sh
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: clean build, NSE not in build graph.

```sh
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: clean build, `.appex` embedded in `.app/PlugIns/`.

```sh
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNewsNotifyService -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```
Expected: NSE target alone builds clean.

### Acceptance criteria

- [ ] iOS build (`-destination 'generic/platform=iOS'`) succeeds and emits `NebularNewsNotifyService.appex` in `NebularNews.app/PlugIns/`.
- [ ] macOS build (`-destination 'platform=macOS'`) succeeds with the NSE excluded from the build graph (confirmed by absence of `NebularNewsNotifyService` lines in `xcodebuild -showBuildSettings` output).
- [ ] On-device: push from "Trigger brief" admin endpoint arrives within 30 s; lock-screen alert shows title (Morning/Evening Brief), 2 bullet body lines, and a thumbnail.
- [ ] Long-pressing the lock-screen notification expands to a larger image preview without crash.
- [ ] Tapping the notification foregrounds the app and routes to the brief detail view.
- [ ] Triggering a brief for a user with **no** lead-image candidates (after backend B1+B2 ship) still results in a notification with an R2-fallback image attached.
- [ ] Killing the host app and triggering a brief still delivers the enriched notification (NSE runs in `usernotificationsd`, not in the app).
- [ ] No console errors from the NSE subsystem during normal delivery (`subsystem:com.nebularnews.ios.NebularNewsNotifyService`).
- [ ] If the implementer manually 404s `image_url` (point it at a dead URL via test brief), the notification still arrives within ~9 s with the 2-bullet body and no image attachment.

### Manual fault-injection (optional)

- Edit a test brief in the admin UI to set a malformed `image_url`. Verify the notification arrives with body intact, no image, no crash.
- Block outbound network on the test device (Airplane Mode for 9 s after triggering, then re-enable). The NSE's 8 s timeout fires and the notification arrives without an image.

## Hand-off Tier

- **iOS implementation work** — Sonnet implementer (`/spec-implement`). The work is verification + at most one comment-clarification commit; no design judgment required. Acceptance is binary (builds + manual device check).
- **Backend R2 pool seeding (B1)** — Haiku tier acceptable. Mechanical: create R2 bucket, upload 30 images, set up CNAME. Sourcing the actual images may need a brief human pass (license check), but bucket setup itself is mechanical.
- **Backend deterministic rotation (B2)** — Haiku tier acceptable. ~10 lines of TypeScript in two files; the patch is in this spec.
- **Backend deploy (B3)** — Pre-authorized per `feedback_wrangler_deploys_authorized.md` memory note. Run without confirmation.

## Verification Commands

```sh
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project /Users/tfinklea/git/nebularnews-ios/NebularNews/NebularNews.xcodeproj -scheme NebularNewsNotifyService -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

Backend deploy:

```sh
npx wrangler deploy --env production
```
(run from `/Users/tfinklea/git/nebularnews` per project shell-style preference — single command, no chaining)

## Out of Scope

- Article-type push notifications (deferred per `next-steps.md` 2026-04-26 entry: "Article-type push notifications via NSE — backend doesn't currently emit them").
- AI-generated per-brief images (cost-prohibitive per the locked decision).
- App Group / Keychain wiring for the NSE (not needed for stateless image+body rewrite).
- Audit-log web UI / provider usage tile (separate design-wait deferred items).
- APNs `apns-collapse-id` to dedupe re-deliveries (not currently set; would suppress duplicate notifications but adds a separate user-visible behavior change).
- Notification Content Extension (different extension type — would render a custom UI inside the long-press preview; current image-attachment approach is sufficient and cheaper).
- Sound customization, badge counts, action buttons (out of scope for this phase).

## Open Decisions

None. The product decisions, payload contract, failure-mode behavior, and image-fallback strategy are all locked. The implementer can execute this end-to-end without further clarification.

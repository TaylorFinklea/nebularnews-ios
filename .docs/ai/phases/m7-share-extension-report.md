# Phase Report: M7 — Safari Share Extension Target

## Status: Complete (code)

## What Was Done

1. **Xcode target created** — `NebularNewsShareExtension` added to `NebularNews.xcodeproj` as `com.apple.product-type.app-extension` with Debug/Release build configurations matching the main app.

2. **Source files wired** — `ShareViewController.swift` and `Info.plist` linked to the extension target. The extension reads the session token from shared Keychain and POSTs the shared URL to `POST /articles/clip`.

3. **Shared Keychain** — Both the main app and extension share the `$(AppIdentifierPrefix)com.nebularnews.ios` Keychain access group via entitlements.

4. **Build verified** — `xcodebuild -scheme NebularNews -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` succeeds with the extension embedded.

5. **Xcode shared data** — Added scheme shared data and extension temp directory to git.

## Commits

- `1af0aef` build: configure Safari Share Extension target in Xcode project
- `0b22cc9` feat: wire Share Extension with shared Keychain and platform-correct build settings
- `42a614a` fix: rename Share Extension from duplicated name to NebularNewsShareExtension
- `187d31d` build: add Xcode shared data and Share Extension temp directory

## Remaining (Manual)

- **CF Email Routing**: Configure `read.nebularnews.com` in Cloudflare Dashboard, enable Email Routing, set catch-all rule → nebular-news worker
- **End-to-end testing**: Forward a real newsletter, clip a URL from Safari on device/TestFlight
- **M7 acceptance**: Both newsletter and clipper work on-device via TestFlight

## Acceptance Criteria

- [x] `xcodebuild -scheme NebularNews` builds both the app and the share extension
- [ ] The extension appears in Safari's share sheet (requires device/TestFlight)
- [ ] Tapping "NebularNews" sends the URL to `POST /articles/clip` (requires device testing)
- [ ] The clipped article appears in the Articles list under "Web Clips" (requires e2e)

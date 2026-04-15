# Phase Spec: M7 — Safari Share Extension Target

## Goal

Wire the existing `ShareViewController.swift` and `Info.plist` into a working Xcode Share Extension target so users can clip any URL from Safari (or any app) into NebularNews.

## Scope

- Add `NebularNewsShareExtension` target to the Xcode project
- Configure shared Keychain access group so the extension can read the session token
- Ensure the extension builds and runs alongside the main app
- Test: share a URL from Safari → article appears in NebularNews

## Approach

1. **Xcode target creation** — This requires modifying `NebularNews.xcodeproj/project.pbxproj` to add:
   - A new native target (`NebularNewsShareExtension`, type `com.apple.product-type.app-extension`)
   - Build configurations (Debug/Release) matching the main app
   - Source file references (ShareViewController.swift, Info.plist)
   - Link frameworks (UIKit, UniformTypeIdentifiers)
   - Embed the extension in the main app target

2. **Keychain sharing** — Add `keychain-access-groups` entitlement to both the main app and extension entitlements files pointing to `$(AppIdentifierPrefix)com.nebularnews.ios`

3. **Build verification** — The extension compiles and the main app includes it

## Acceptance Criteria

- [ ] `xcodebuild -scheme NebularNews` builds both the app and the share extension
- [ ] The extension appears in Safari's share sheet when running on a device/simulator
- [ ] Tapping "NebularNews" in the share sheet sends the URL to `POST /articles/clip`
- [ ] The clipped article appears in the Articles list under "Web Clips"

## Assumptions

- The `ShareViewController.swift` and `Info.plist` already written are correct and complete
- The `POST /articles/clip` endpoint is deployed and working
- The user has a valid session token in the Keychain from the main app

## Out of Scope

- Tag selection in the extension UI (future polish)
- Offline queuing for clips (future)
- Chrome extension (deferred until web app exists)
- CF Email Routing dashboard setup (manual, separate from this phase)

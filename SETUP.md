# Nebular News iOS

Nebular News iOS now supports two modes:

- **Companion mode**: connects to your Nebular News web server and uses it as the source of truth for dashboard data, News Brief, articles, read state, reactions, and tags
- **Standalone mode**: keeps local feeds and local provider keys on-device

Companion mode is the primary production path. Standalone mode remains available for local-only use.

## Requirements

- Xcode 16 or newer with an iOS 18 simulator/runtime
- macOS 14 or newer
- Apple Developer Program membership (required for CloudKit sync and TestFlight)

## Repo defaults

The checked-in project is intentionally generic:

- bundle identifiers default to `com.example.*`
- CloudKit sync is enabled via xcconfig (see iCloud setup below)
- the default mobile OAuth callback is `nebularnews://oauth/callback`
- the onboarding server field falls back to `https://api.example.com` unless you set a different default

See [NebularNews/Config/AppConfig.example.xcconfig](NebularNews/Config/AppConfig.example.xcconfig) for all override keys.

## Build and run

1. Open [NebularNews/NebularNews.xcodeproj](NebularNews/NebularNews.xcodeproj) in Xcode.
2. Select the `NebularNews` scheme.
3. Choose an iOS 18 simulator.
4. Build and run.

The first launch shows onboarding with:

- `Connect to existing Nebular News server`
- `Use standalone mode`

## Companion mode setup

Your web deployment must expose a separate public mobile host, for example:

- protected app host: `https://news.example.com`
- public mobile host: `https://api.example.com`

The web app must be configured with:

- `MOBILE_PUBLIC_ENABLED=true`
- `MOBILE_PUBLIC_BASE_URL=https://api.example.com`
- `MOBILE_OAUTH_CLIENT_ID=nebular-news-ios`
- `MOBILE_OAUTH_CLIENT_NAME=Nebular News iOS`
- `MOBILE_OAUTH_REDIRECT_URIS=nebularnews://oauth/callback`

Companion login uses first-party OAuth Authorization Code + PKCE with `ASWebAuthenticationSession`.

## Optional local config overrides

The app already builds with the checked-in defaults. If you want environment-specific values without editing shared project files:

1. Copy the values you need from [NebularNews/Config/AppConfig.example.xcconfig](NebularNews/Config/AppConfig.example.xcconfig) into a local xcconfig such as `NebularNews/Config/AppConfig.local.xcconfig`.
2. In Xcode, set that local file as the base configuration for the `NebularNews` target.

Useful overrides:

- `PRODUCT_BUNDLE_IDENTIFIER`
- `KEYCHAIN_SERVICE`
- `BACKGROUND_REFRESH_TASK_IDENTIFIER`
- `CLOUDKIT_CONTAINER_IDENTIFIER`
- `MOBILE_OAUTH_CLIENT_ID`
- `MOBILE_OAUTH_CLIENT_NAME`
- `MOBILE_OAUTH_REDIRECT_URI`

## Testing

### Swift package tests

```bash
cd NebularNewsKit
swift test
```

### Simulator build

```bash
xcodebuild \
  -project NebularNews/NebularNews.xcodeproj \
  -scheme NebularNews \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Device-style build validation

```bash
xcodebuild \
  -project NebularNews/NebularNews.xcodeproj \
  -scheme NebularNews \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### App unit tests

```bash
xcodebuild \
  -project NebularNews/NebularNews.xcodeproj \
  -scheme NebularNews \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:NebularNewsTests \
  test
```

## CI

GitHub Actions runs:

- `swift test` for `NebularNewsKit`
- unsigned simulator build validation
- unsigned generic iOS device build validation
- `NebularNewsTests` on an automatically selected iPhone simulator

The workflow lives at [.github/workflows/ios.yml](.github/workflows/ios.yml).

## iCloud / CloudKit sync

CloudKit sync lets standalone-mode data (feeds, articles, read state, tags) stay in sync across all of a user's devices automatically via iCloud. Companion mode does not use CloudKit — it syncs through the web server instead.

### How it works

SwiftData's `.automatic` CloudKit mode handles everything for the synced store:
- Schema mirroring: SwiftData models are automatically mapped to CloudKit record types
- Conflict resolution: last-writer-wins with automatic merge for non-conflicting fields
- Push sync: changes propagate to other devices within seconds when online
- Offline support: changes queue locally and sync when connectivity returns

The infrastructure is already built into the codebase — `ModelContainerSetup.swift` accepts a `cloudKitEnabled` flag and `AppConfiguration` reads it from your xcconfig.

NebularNews uses two SwiftData configurations:
- a CloudKit-synced store for user data such as feeds, articles, read state, tags, chat threads, and app settings
- a local-only store for operational/read-model data such as article processing jobs, Today snapshots, and personalization tables that rely on uniqueness constraints unsupported by CloudKit

### Setup steps

1. **Create a CloudKit container** in the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list/cloudContainers):
   - Identifier: `iCloud.com.nebularnews.ios` (or matching your bundle ID)

2. **Enable iCloud capability** in Xcode:
   - Select the `NebularNews` target → Signing & Capabilities
   - Click `+ Capability` → select `iCloud`
   - Check `CloudKit`
   - Select your container (`iCloud.com.nebularnews.ios`)

3. **Set xcconfig values** in your local `AppConfig.local.xcconfig`:
   ```
   CLOUDKIT_ENABLED = YES
   CLOUDKIT_CONTAINER_IDENTIFIER = iCloud.com.nebularnews.ios
   ```

4. **Verify the entitlements file** was generated by Xcode with:
   ```xml
   <key>com.apple.developer.icloud-services</key>
   <array>
       <string>CloudKit</string>
   </array>
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array>
       <string>iCloud.com.nebularnews.ios</string>
   </array>
   ```

5. **Build and run** on a device signed into iCloud. Open the [CloudKit Console](https://icloud.developer.apple.com/) to inspect synced records in the Development environment.

### Important notes

- All `@Model` properties must be optional or have default values (ours already do) — CloudKit requires this for schema compatibility
- CloudKit uses the **Development** environment during debug builds and **Production** after you deploy the schema (CloudKit Console → Deploy to Production)
- The first launch with CloudKit enabled creates the schema automatically; subsequent model changes require schema migration
- Background push notifications (`remote-notification` in `UIBackgroundModes`) are already configured in Info.plist for silent sync updates
- CloudKit has rate limits (~40 requests/second per user) — the exponential backoff in `FeedPoller` keeps polling well within bounds

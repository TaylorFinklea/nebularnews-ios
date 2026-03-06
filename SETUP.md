# Nebular News iOS

Nebular News iOS now supports two modes:

- **Companion mode**: connects to your Nebular News web server and uses it as the source of truth for dashboard data, News Brief, articles, read state, reactions, and tags
- **Standalone mode**: keeps local feeds and local provider keys on-device

Companion mode is the primary production path. Standalone mode remains available for local-only use.

## Requirements

- Xcode 16 or newer with an iOS 18 simulator/runtime
- macOS 14 or newer
- no CloudKit or iCloud setup required for a default build

## Repo defaults

The checked-in project is intentionally generic:

- bundle identifiers default to `com.example.*`
- CloudKit is disabled by default
- the default mobile OAuth callback is `nebularnews://oauth/callback`
- the onboarding server field falls back to `https://api.example.com` unless you set a different default

See [NebularNews/Config/AppConfig.example.xcconfig](NebularNews/Config/AppConfig.example.xcconfig) for the optional override keys.

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

## CloudKit note

CloudKit is optional and off by default. Companion mode does not depend on iCloud. If you want standalone sync or CloudKit-backed experiments later, enable that explicitly in your own app configuration and entitlements.

# Nebular News iOS — Setup Guide

## Prerequisites

- **Xcode 26 beta** (or later) — required for iOS 26 SDK and Liquid Glass APIs
- **iOS 26 simulator** or device
- **Apple Developer account** with iCloud/CloudKit entitlements
- macOS 15+ (Sequoia or later)

## Step 1: Create the Xcode Project

1. Open Xcode 26
2. **File → New → Project**
3. Choose **iOS → App**
4. Configure:
   - **Product Name**: `NebularNews`
   - **Organization Identifier**: `com.nebularnews` (or your own)
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None (we use the package's SwiftData setup)
   - **Testing System**: Swift Testing
5. Save into the `nebularnews-ios/` directory (alongside the existing `NebularNewsKit/` folder)
6. **Delete** the auto-generated `ContentView.swift` and `NebularNewsApp.swift` — we have our own in `NebularNews/App/`

## Step 2: Add the Local Swift Package

1. In Xcode, **File → Add Package Dependencies...**
2. Click **Add Local...** and select the `NebularNewsKit/` directory
3. Xcode will detect the `Package.swift` — add it
4. Ensure `NebularNewsKit` library is linked to the `NebularNews` app target

## Step 3: Add Source Files to the App Target

The `NebularNews/` directory contains the app-level SwiftUI code. Add these folders to the Xcode project:

- `NebularNews/App/` — Entry point, tab view, app state
- `NebularNews/Features/` — All feature screens (Feeds, Onboarding, etc.)
- `NebularNews/SharedViews/` — Reusable glass components

Drag them into the Xcode navigator under the `NebularNews` app target.

## Step 4: Configure iCloud + CloudKit

1. Select the `NebularNews` target → **Signing & Capabilities**
2. Click **+ Capability** and add:
   - **iCloud** — check **CloudKit**, create a container `iCloud.com.nebularnews.ios`
   - **Background Modes** — check **Remote notifications** (required for CloudKit sync)
3. Ensure the CloudKit container is created in your Apple Developer portal

## Step 5: Set Deployment Target

1. Select the `NebularNews` target → **General**
2. Set **Minimum Deployments → iOS 26.0**

## Step 6: Build & Run

1. Select an iOS 26 simulator (e.g., iPhone 16 Pro)
2. **Cmd+R** to build and run
3. The onboarding flow should appear on first launch
4. Add a feed, skip or enter an AI API key, and you're in

## Project Structure

```
nebularnews-ios/
├── NebularNewsKit/              ← Swift Package (core logic)
│   ├── Package.swift
│   ├── Sources/NebularNewsKit/
│   │   ├── Models/              ← SwiftData @Model types
│   │   ├── Repositories/        ← Data access layer
│   │   ├── Ingestion/           ← RSS fetching (Phase 2)
│   │   ├── AI/                  ← LLM integration (Phase 4)
│   │   ├── Keychain/            ← Secure storage
│   │   └── Extensions/          ← Date, Color helpers
│   └── Tests/
│
├── NebularNews/                 ← App target (SwiftUI views)
│   ├── App/                     ← Entry point, tab view
│   ├── Features/                ← Screen modules
│   │   ├── Onboarding/
│   │   ├── Dashboard/
│   │   ├── Articles/
│   │   ├── Chat/
│   │   ├── Feeds/
│   │   ├── Tags/
│   │   └── Settings/
│   ├── SharedViews/             ← GlassCard, ScoreBadge, TagPill
│   └── Resources/
│
├── NebularNews.xcodeproj        ← Created in Step 1
└── SETUP.md                     ← This file
```

## Running Tests

The `NebularNewsKit` package has its own test target:

```bash
cd NebularNewsKit
swift test
```

Or in Xcode: select the `NebularNewsKitTests` scheme and press **Cmd+U**.

## Next Phases

The scaffold is complete. Upcoming implementation:

- **Phase 2**: FeedKit integration, content extraction, background polling
- **Phase 3**: Article list with Liquid Glass cards, detail view, reactions
- **Phase 4**: AI summaries, scoring, key points (direct API calls)
- **Phase 5**: Chat with streaming AI responses
- **Phase 6**: Dashboard, polish, accessibility

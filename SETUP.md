# Nebular News iOS — Setup Guide

## Prerequisites

- **Xcode 26 beta** (or later) — required for iOS 26 SDK and Liquid Glass APIs
- **iOS 26 simulator** or device
- **Apple Developer account** with iCloud/CloudKit entitlements
- macOS 15+ (Sequoia or later)

## Step 1: Create the Xcode Project ✅

Already created at `NebularNews/NebularNews.xcodeproj`.

## Step 2: Add the Local Swift Package ✅

NebularNewsKit added as a local package dependency.

## Step 3: Add Source Files ✅

Source files are in `NebularNews/NebularNews/` using Xcode's filesystem-synchronized groups —
they are auto-discovered by the build system (no manual drag-and-drop needed).

## Step 4: Remove Auto-Generated Files ✅

Xcode 26 did not generate ContentView.swift or NebularNewsApp.swift stubs.
No cleanup needed.

## Step 5: Configure iCloud + CloudKit

1. Open `NebularNews/NebularNews.xcodeproj` in Xcode
2. Select the **NebularNews** target → **Signing & Capabilities**
3. Click **+ Capability** and add:
   - **iCloud** — check **CloudKit**, create a container `iCloud.com.nebularnews.ios`
   - **Background Modes** — check **Remote notifications** (required for CloudKit sync)
4. Ensure the CloudKit container is created in your Apple Developer portal

## Step 6: Build & Run

1. Install the iOS 26 simulator: **Xcode → Settings → Components → iOS 26**
2. Select an iOS 26 simulator (e.g., iPhone 16 Pro)
3. **Cmd+R** to build and run
4. The onboarding flow should appear on first launch
5. Add a feed, skip or enter an AI API key, and you're in

## Project Structure

```
nebularnews-ios/
├── NebularNews/                         ← Xcode project wrapper
│   ├── NebularNews.xcodeproj/           ← Xcode project file
│   ├── NebularNews/                     ← App target (filesystem-synced)
│   │   ├── App/                         ← Entry point, tab view, app state
│   │   ├── Features/                    ← Screen modules
│   │   │   ├── Onboarding/
│   │   │   ├── Feeds/
│   │   │   ├── Dashboard/  (Phase 6)
│   │   │   ├── Articles/   (Phase 3)
│   │   │   ├── Chat/       (Phase 5)
│   │   │   ├── Tags/       (Phase 3)
│   │   │   └── Settings/   (Phase 3)
│   │   ├── SharedViews/                 ← GlassCard, ScoreBadge, TagPill
│   │   └── Assets.xcassets/             ← App icons, accent color
│   ├── NebularNewsTests/
│   └── NebularNewsUITests/
│
├── NebularNewsKit/                      ← Swift Package (core logic)
│   ├── Package.swift
│   ├── Sources/NebularNewsKit/
│   │   ├── Models/                      ← SwiftData @Model types
│   │   ├── Repositories/                ← Data access layer
│   │   ├── Ingestion/                   ← RSS fetching (Phase 2)
│   │   ├── AI/                          ← LLM integration (Phase 4)
│   │   ├── Keychain/                    ← Secure storage
│   │   └── Extensions/                  ← Date, Color helpers
│   └── Tests/NebularNewsKitTests/
│
├── SETUP.md                             ← This file
└── .gitignore
```

> **Filesystem-Synced Groups**: Xcode 26 uses `PBXFileSystemSynchronizedRootGroup` —
> any `.swift` files placed in the `NebularNews/NebularNews/` folder are automatically
> compiled as part of the app target. No need to manually add file references.

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

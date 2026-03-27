# Current State

*Last updated: 2026-03-27*

## Active Branch

`main` (both repos)

## Recent Progress

### Web (nebularnews)
- Added Apple Sign In via Supabase OAuth PKCE (`/auth/apple` GET endpoint)
- Fixed CSP `form-action` issue by using GET redirect instead of form POST
- Added `/auth` to mobile host allowed paths
- Fixed V17 migration: ran missing ALTER TABLE for 7 tables on production D1
- Updated `schema.sql` to include `user_id` on all V17-affected tables
- Added guided onboarding page at `/onboarding` with curated feed catalog
- Added `/api/onboarding/subscribe` and `/api/mobile/onboarding/subscribe` endpoints
- Rejected deleted-user tokens in `requireMobileAccess` instead of falling back
- Updated dashboard "Get started" card to link to `/onboarding`

### iOS (nebularnews-ios)
- Added `FeedSelectionView` as second onboarding phase after server connection
- Three-phase routing: OnboardingView -> FeedSelectionView -> MainTabView
- Made server URL editable on onboarding screen
- Defaulted server URL to `api.nebularnews.com`
- Switched to ephemeral browser sessions for OAuth
- Added onboarding models and API methods to MobileAPIClient

## Changed Files (this session)

### Web
- `src/lib/server/supabase-auth.ts` — OAuth PKCE functions
- `src/routes/auth/apple/+server.ts` — Apple Sign In GET endpoint (new)
- `src/routes/auth/callback/+server.ts` — OAuth code exchange branch
- `src/routes/login/+page.svelte` — Apple Sign In button
- `src/hooks.server.ts` — `/auth` added to mobile host paths
- `schema.sql` — `user_id` columns on 5 tables
- `src/lib/server/onboarding-catalog.ts` — curated feed catalog (new)
- `src/routes/onboarding/` — onboarding page (new)
- `src/routes/api/*/onboarding/` — subscribe/suggestions endpoints (new)
- `src/lib/server/mobile/auth.ts` — reject deleted-user tokens
- `src/routes/+page.svelte` — updated "Get started" card

### iOS
- `Features/Onboarding/OnboardingView.swift` — editable server URL
- `Features/Onboarding/FeedSelectionView.swift` — feed selection UI (new)
- `App/AppState.swift` — `hasCompletedFeedSelection` phase
- `App/NebularNewsApp.swift` — three-phase routing
- `App/AppConfiguration.swift` — default URL to api.nebularnews.com
- `Services/MobileAPIClient.swift` — onboarding API methods
- `Services/MobileOAuthCoordinator.swift` — ephemeral sessions
- `Features/Companion/CompanionModels.swift` — onboarding models

## Blockers

None currently.

## Open Questions

- When to execute the D1 -> Supabase Postgres migration sprint?
- Web onboarding needs testing with a fresh account (CSRF token flow)
- Apple Sign In secret key expires ~September 2026 — needs rotation

## Validation

- Web: 256 tests passing
- iOS: builds locally, onboarding flow tested on device
- Production D1: V17 columns verified present

# Current State

*Last updated: 2026-03-27*

## Active Branch

`main` (both repos)

## Recent Progress

### Web (nebularnews)
- Auto-redirect: new users with no feed subscriptions get redirected from `/` to `/onboarding`
- Uses per-user `user_feed_subscriptions` count (not global feed count) for multi-user correctness

### iOS (nebularnews-ios)
- Added `ContentUnavailableView` empty states to 4 views:
  - **CompanionTodayView** — "No articles yet" when no hero or upNext
  - **CompanionFeedsView** — "No feeds" when feed list is empty
  - **CompanionArticlesView** — filter-aware: "No articles match your filters" vs "Articles will appear here once your feeds are polled"
  - **CompanionFilteredArticleListView** — "No articles found for this filter"

### Already Complete (earlier this session)
- Apple Sign In via Supabase OAuth PKCE
- Guided onboarding with curated feed catalog (web + iOS)
- V17 migration fixes on production D1
- Ephemeral OAuth browser sessions
- Rejected deleted-user tokens in mobile auth
- AI handoff docs (`docs/ai/`)

## Blockers

None.

## Open Questions

- Apple Sign In client secret expires ~September 2026 — needs rotation
- User admin already exists at `/settings/users` — may need mobile-facing admin later

## Validation

- Web: 256 tests passing, deployed to production
- iOS: builds locally, needs TestFlight release
- Production D1: stable after V17 column fixes

# Current State

*Last updated: 2026-03-29*

## Active Branch

`main` (both repos)

## Recent Progress

### iOS (nebularnews-ios) — Supabase Migration

Major architecture change: replaced `MobileAPIClient` (REST calls to SvelteKit backend) with `SupabaseManager` (direct Supabase Swift SDK calls).

**New files:**
- `Services/SupabaseManager.swift` — central service with PostgREST queries, Supabase Auth (Apple Sign In via ID token), and Edge Function calls

**Updated files (all wired to Supabase):**
- `App/AppState.swift` — added `supabase: SupabaseManager`, `hasSession`, `loadSession()`, `completeSignIn()`, `signOut()`; kept legacy `mobileAPI` for transition
- `App/NebularNewsApp.swift` — loads Supabase session on launch, falls back to legacy companion session
- `App/MainTabView.swift` — uses `appState.supabase.fetchArticles()`
- `App/BackgroundTaskManager.swift` — uses `SupabaseManager.shared` for background refresh
- `App/NotificationManager.swift` — added `uploadTokenIfNeeded(supabase:)` alongside legacy API method
- `Features/Onboarding/OnboardingView.swift` — Apple Sign In via `SignInWithAppleButton` + `supabase.signInWithApple(idToken:nonce:)`
- `Features/Onboarding/FeedSelectionView.swift` — uses `supabase.fetchOnboardingSuggestions()` and `supabase.bulkSubscribe()`
- `Features/Companion/CompanionTodayView.swift` — all API calls now via `appState.supabase`
- `Features/Companion/CompanionArticlesView.swift` — same
- `Features/Companion/CompanionArticleDetailView.swift` — same
- `Features/Companion/CompanionFeedsView.swift` — same
- `Features/Companion/CompanionDiscoverView.swift` — same
- `Features/Companion/CompanionReadingListView.swift` — same
- `Features/Companion/CompanionFilteredArticleListView.swift` — same
- `Features/Companion/CompanionSettingsView.swift` — replaced "Disconnect server" with "Sign Out", removed server URL field
- `Features/Companion/CompanionTagListView.swift` — same
- `Features/Companion/CompanionArticleChatView.swift` — same

**Auth flow:**
- Old: Custom OAuth PKCE flow via SvelteKit → keychain tokens → MobileAPIClient bearer auth
- New: Apple Sign In → Supabase `signInWithIdToken` → SDK manages JWT refresh automatically

**Data models unchanged:** `CompanionModels.swift` types are preserved. SupabaseManager maps Postgres rows to the same model types.

**Not changed:**
- `MobileAPIClient.swift` — kept for backward compatibility during transition
- `MobileOAuthCoordinator.swift` — kept for backward compatibility
- Xcode project file — user will add Supabase SPM package manually
- SharedViews — no changes needed

### Supabase Project

- Project ID: `vdjrclxeyjsqyqsjzjfj` (us-east-1)
- All tables have RLS enabled
- Edge functions available: `enrich-article`, `export-opml`, `import-opml`, `poll-feeds`, `process-jobs`, `send-notification`

## Blockers

- User must add `supabase-swift` SPM package in Xcode before building
- RLS policies need to be verified to allow the iOS app's queries
- Edge functions need to be deployed to the Supabase project

## Open Questions

- Apple Sign In client secret expires ~September 2026
- Need to configure Apple Sign In provider in Supabase Auth dashboard
- Chat AI responses depend on an edge function that is not yet deployed

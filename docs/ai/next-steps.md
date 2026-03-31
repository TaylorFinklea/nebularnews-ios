# Next Steps

*Last updated: 2026-03-29*

## Immediate

- [ ] Add `supabase-swift` SPM package in Xcode (URL: `https://github.com/supabase/supabase-swift`, version 2.x)
- [ ] Configure Apple Sign In provider in Supabase Auth dashboard
- [ ] Verify RLS policies allow iOS app queries (articles, feeds, tags, settings, etc.)
- [ ] Build and test the full sign-in flow: Apple Sign In → feed selection → Today tab
- [ ] Deploy edge functions to Supabase project (`poll-feeds`, `enrich-article`, `import-opml`, `export-opml`)

## Short-term

- [ ] Remove legacy `MobileAPIClient.swift` and `MobileOAuthCoordinator.swift` once migration is verified
- [ ] Remove legacy companion session code from `AppState` (keychain tokens, `companionServerURL`, etc.)
- [ ] Add proper count queries for saved articles and filtered article lists
- [ ] Wire up News Brief display (needs edge function or Postgres function)
- [ ] Test background refresh with Supabase session

## Planned

- [ ] Build and release to TestFlight with Supabase backend
- [ ] Test full end-to-end: new user Apple Sign In → onboarding → feed selection → articles populate
- [ ] Add real-time subscriptions for article updates (Supabase Realtime)
- [ ] Deploy chat AI edge function for article Q&A

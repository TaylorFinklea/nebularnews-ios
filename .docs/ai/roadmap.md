# Roadmap

> Durable goals and milestones. Updated when scope changes, not every session.

## Vision

NebularNews — iOS-first RSS reader with AI enrichment, powered by Supabase.

## Repos

- **iOS**: `/Users/tfinklea/git/nebularnews-ios` — SwiftUI + Supabase Swift SDK
- **Backend**: `/Users/tfinklea/git/nebularnews-api` — Edge Functions + PostgREST + RLS

## Active Milestones

### M1: Core Reading Experience (complete)
- [x] Supabase backend with RLS and 10 Edge Functions
- [x] Apple Sign In via Supabase Auth
- [x] Feed management (add/remove/pause, OPML import/export)
- [x] AI enrichment on-demand (summarize, key points, chat, brief)
- [x] Algorithmic scoring (4 signals, per-user, reaction feedback)
- [x] Offline support with SyncManager
- [x] Push notifications
- [x] TestFlight shipping (Build 4)

### M2: Platform Expansion (not started)
- [ ] macOS target (code ready with #if os guards)
- [ ] Widget Extension target (code ready in NebularNewsWidgets/)
- [ ] Fix marketing version in Xcode project settings

### M3: Product Refinement (not started)
- [ ] Hybrid AI + algorithmic scoring
- [ ] Per-user AI rate limiting
- [ ] Full-text search UI
- [ ] Richer article reading experience
- [ ] Feed discovery

### M4: Infrastructure (not started)
- [ ] Docker self-hosting end-to-end
- [ ] CI/CD for Edge Function deployment
- [ ] Monitoring and backup

## Constraints

- iOS 17+ (SwiftUI + SwiftData)
- $0/mo target (Supabase free tier)
- AI enrichment is on-demand only (cost control)
- BYOK for user API keys

## Priority Order

M2 first (low effort, high visibility), then M3 (product value), then M4 (operational maturity).

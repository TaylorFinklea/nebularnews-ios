# Current State (2026-04-15)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## Completed Milestones
- **M1-M5**: Core reading, article UX, AI improvements, search & discovery, macOS app
- **M6**: AI Overhaul — three-tier AI, streaming chat, MCP server, floating AI assistant, admin dashboard, auto-enrichment, scheduled briefs, scoring v2, topic clustering
- **M7**: Inbox Unification (code complete) — email newsletter backend, web clipper, Share Extension wired into Xcode project. Manual items remaining: CF Email Routing config, on-device e2e testing.

## M8: Reader Depth — In Progress

### Done
- Phase spec written, plan approved

### Current Phase: Collections (Phase 1)
- D1 migration (4 tables)
- Workers collections route
- iOS CollectionService + Library tab + collection views

### Remaining Phases
- Phase 2: Highlights (backend + iOS rendering)
- Phase 3: Annotations (backend + iOS editor)
- Phase 4: Markdown export
- Phase 5: SyncManager offline + polish

## Deployed Migrations
- 0001 through 0007 all applied on production D1

## Known Issues
- Roadmap.md vision text and repo references are stale (still says "Supabase")
- Some article images still broken (depends on source feed providing valid URLs)
- Admin dashboard visible to all users in Settings (role-gated on backend but the link is always shown)
- M7 manual items: CF Email Routing not yet configured, e2e testing pending

## Both Repos Clean
- `nebularnews-ios`: 187d31d (HEAD)
- `nebularnews`: efef4a0 (HEAD)

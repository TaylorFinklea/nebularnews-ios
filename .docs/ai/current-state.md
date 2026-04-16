# Current State (2026-04-15)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## Completed Milestones
- **M1-M5**: Core reading, article UX, AI improvements, search & discovery, macOS app
- **M6**: AI Overhaul — three-tier AI, streaming chat, MCP server, floating AI assistant, admin dashboard, auto-enrichment, scheduled briefs, scoring v2, topic clustering
- **M7**: Inbox Unification (code complete) — email newsletter backend, web clipper, Share Extension. Manual: CF Email Routing config, e2e device testing.

## M8: Reader Depth — Code Complete

### Done
- **Phase 1 (Collections)**: D1 migration (4 tables), Workers CRUD route, iOS CollectionService, Library tab (replaces Lists), CreateCollectionSheet, EditCollectionSheet, AddToCollectionSheet, collection detail view
- **Phase 2 (Highlights)**: Workers highlights route (CRUD), article detail endpoint returns highlights, iOS HighlightService, HighlightsSection in detail view, highlight creation via alert + toolbar button
- **Phase 3 (Annotations)**: Workers annotations route (GET/PUT/DELETE), article detail endpoint returns annotation, iOS AnnotationService, AnnotationSection with TextEditor sheet
- **Phase 4 (Export)**: Client-side MarkdownExporter, ShareLink in article detail toolbar and collection detail menu

### Remaining (Manual/Testing)
- Deploy Workers: `cd ~/git/nebularnews && npx wrangler deploy --env production`
- Run migration: `npx wrangler d1 migrations apply nebularnews-prod --env production --remote`
- End-to-end test: create collection → add articles → highlight text → add note → export Markdown
- Phase 5 (deferred): SyncManager offline support for collection/highlight/annotation mutations

## Deployed Migrations
- 0001 through 0007 applied on production D1
- 0008 (reader_depth) written but not yet deployed

## Known Issues
- Roadmap.md vision text and repo references still say "Supabase"
- Highlight creation uses paste-based alert (MVP); future: intercept native text selection
- M7 manual: CF Email Routing not yet configured
- SyncManager doesn't yet queue collection/highlight/annotation mutations offline

## Both Repos Clean
- `nebularnews-ios`: c3a2230 (HEAD)
- `nebularnews`: 17e895b (HEAD)

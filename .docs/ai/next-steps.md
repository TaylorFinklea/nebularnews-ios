# Next Steps (2026-04-15)

## Deploy & Test M8

- [ ] Deploy Workers: `cd ~/git/nebularnews && npx wrangler deploy --env production`
- [ ] Run migration: `npx wrangler d1 migrations apply nebularnews-prod --env production --remote`
- [ ] Test collections: create, add articles, view, edit, delete
- [ ] Test highlights: create from article detail, view in section, delete
- [ ] Test annotations: add note, edit, delete
- [ ] Test export: share Markdown from article detail and collection detail
- [ ] TestFlight release

## M7 Manual Items (Still Pending)

- [ ] Configure CF Email Routing: `read.nebularnews.com` in CF Dashboard
- [ ] End-to-end test: forward a newsletter, clip from Safari on device

## M8 Phase 5 (Deferred Polish)

- [ ] SyncManager offline support for collection/highlight/annotation mutations
- [ ] Improve highlight creation: intercept native text selection instead of paste alert
- [ ] Highlight rendering: yellow background overlays in RichArticleContentView
- [ ] CompanionCache integration for collections

## Future Milestones

- **M9: Platform Polish** — iPad layout, Lock Screen widgets, Live Activities, Watch glance

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation
- [ ] User timezone support for scheduled briefs (currently UTC)
- [ ] AI assistant direct actions (tool-calling to filter articles, navigate, apply tags)

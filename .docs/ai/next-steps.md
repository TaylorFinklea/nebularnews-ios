# Next Steps (2026-04-15)

## M7 Manual Items (User)

- [ ] Configure CF Email Routing: `read.nebularnews.com` in CF Dashboard, catch-all → nebular-news worker
- [ ] End-to-end test: forward a newsletter, clip from Safari on device
- [ ] TestFlight release with Share Extension

## M8: Reader Depth — Phase 1 (Collections)

### Backend
- [ ] Write `migrations/0008_reader_depth.sql` (4 tables: collections, collection_articles, article_highlights, article_annotations)
- [ ] Create `src/routes/collections.ts` (CRUD + article membership)
- [ ] Register collections route in `src/index.ts`

### iOS
- [ ] Add `CompanionCollection` / `CompanionCollectionDetail` DTOs to `CompanionModels.swift`
- [ ] Create `Services/CollectionService.swift`
- [ ] Add facade methods to `SupabaseManager.swift`
- [ ] Create `Features/Library/LibraryView.swift` (replaces Lists tab)
- [ ] Create `Features/Library/CollectionDetailView.swift`
- [ ] Create `Features/Library/CreateCollectionSheet.swift`
- [ ] Create `Features/Library/AddToCollectionSheet.swift`
- [ ] Update `App/MainTabView.swift` — "Lists" → "Library" with `books.vertical` icon

## M8 Upcoming Phases

- Phase 2: Highlights (backend routes + iOS highlight rendering + creation flow)
- Phase 3: Annotations (backend routes + iOS annotation editor)
- Phase 4: Markdown export (client-side MarkdownExporter + ShareLink)
- Phase 5: SyncManager offline support + polish

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation
- [ ] User timezone support for scheduled briefs (currently UTC)
- [ ] AI assistant direct actions (tool-calling to filter articles, navigate, apply tags)

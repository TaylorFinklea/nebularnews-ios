# Next Steps (2026-04-11)

## Immediate — Verify & Fix

- [ ] Set AI provider keys for enrichment: `wrangler secret put OPENAI_API_KEY --env production`
- [ ] Set scraper keys: `wrangler secret put STEEL_API_KEY --env production`
- [ ] Test AI enrichment (summarize, chat) from iOS
- [ ] Fix 4 stale feed URLs or remove dead feeds
- [ ] Delete 8 unscored articles, re-score remaining
- [ ] Test OPML import/export
- [ ] Test tag add/remove
- [ ] Test feed add/delete from iOS
- [ ] Remove debug endpoints (debug-poll, trigger-score) before prod release
- [ ] Clean up old `src/lib/server/` (104 SvelteKit-era files)

## Soon — Polish

- [ ] Update CLAUDE.md to reference Workers backend
- [ ] TestFlight release with Workers backend
- [ ] Remove Supabase Swift Package from Xcode project
- [ ] Push notifications (verify APNS works with Workers)
- [ ] Handle articles with null published_at better in scoring

## Strategic — M6 Candidates

See memory `project_m6_candidates.md`. Pick after migration stable:
1. Reader depth (collections, highlights, annotations)
2. Listening (TTS, CarPlay)
3. Inbox unification (email newsletters as feeds)
4. Brief 2.0 (scheduled push, per-topic)
5. Scoring v2 (hybrid AI + algorithmic)
6. Platform polish (iPad, Lock Screen widgets, Watch)

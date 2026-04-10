# Next Steps (2026-04-10)

## Immediate — Deploy & Test

- [ ] Create production D1 database: `wrangler d1 create nebular-news-prod`
- [ ] Update `wrangler.toml` production database_id with real ID
- [ ] Set production secrets: `wrangler secret put BETTER_AUTH_SECRET --env production` (and APPLE_CLIENT_ID, APPLE_CLIENT_SECRET, optionally OPENAI_API_KEY/ANTHROPIC_API_KEY)
- [ ] Deploy: `cd ~/git/nebularnews && npx wrangler deploy --env production`
- [ ] Run migration: `wrangler d1 migrations apply DB --env production --remote`
- [ ] Test locally: `npx wrangler dev` → curl /api/health, trigger cron
- [ ] Test Apple Sign In from iOS → verify session token flow
- [ ] Add a feed, wait for cron poll, verify articles appear
- [ ] Test AI enrichment with BYOK key

## Soon — Cleanup

- [ ] Remove Supabase Swift Package dependency from Xcode project
- [ ] Clean up `.dev.vars` (remove old Supabase secrets)
- [ ] Remove old `src/lib/server/` directory (104 SvelteKit-era files no longer used)
- [ ] Remove old `schema.sql` (replaced by `migrations/0001_initial.sql`)
- [ ] Delete `SupabaseServiceModels.swift` if no longer needed
- [ ] Update CLAUDE.md to reference Workers backend instead of Supabase
- [ ] New TestFlight release with Workers backend

## Strategic — M6 Candidates

See memory file `project_m6_candidates.md`. Pick one after migration is stable:
1. Reader depth (collections, highlights, annotations)
2. Listening (TTS, CarPlay)
3. Inbox unification (email newsletters as feeds)
4. Brief 2.0 (scheduled push, per-topic)
5. Scoring v2 (hybrid AI + algorithmic)
6. Platform polish (iPad, Lock Screen widgets, Watch)

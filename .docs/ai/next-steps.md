# Next Steps (2026-04-09)

> Short checklist of exact next actions. Updated at end of every session.
> Full roadmap with phases and backlog: `.docs/ai/roadmap.md`

## Status

All M1–M5 phases complete. All tiered backlog items (trivial + minor) closed.
Two refactors landed this session: `score-articles` (455→115 lines) and
`enrich-article` (496→99 lines). Neither is deployed yet.

## Immediate

- [ ] Deploy refactored Edge Functions once ready to verify behavior:
  - `/deploy-function score-articles`
  - `/deploy-function enrich-article`
- [ ] Decide whether to push the API repo (now 12 commits ahead of origin).
- [ ] Review untracked `supabase/migrations/00009_monitoring_views.sql` —
  roadmap says monitoring is done but the file was never committed.

## Soon — possible next milestones

Pick one when ready to start new product work:

- **Reader enhancements**: saved-article folders/collections, highlights,
  annotations, export to Readwise/Notion.
- **Brief authoring polish**: scheduled push delivery, per-topic brief
  generation, audio version.
- **Feed discovery v2**: personalized recommendations based on reactions,
  "because you liked X" surfaces.
- **Scoring v2**: hybrid AI + algorithmic — run AI score only on top-N
  algorithmically-ranked items to control cost.
- **Admin dashboard**: user management, usage monitoring surfaces from
  `00009_monitoring_views.sql`.

## Backlog — empty

No open tiered items. Populate with `/audit-backlog` when resuming.

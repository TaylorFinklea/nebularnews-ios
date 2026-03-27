# Next Steps

*Last updated: 2026-03-27*

## Immediate

- [ ] Test web onboarding end-to-end with a fresh account (Apple Sign In -> feed selection -> subscribe -> dashboard populates)
- [ ] Build and release iOS to TestFlight with onboarding flow
- [ ] Verify Apple Sign In client secret works (expires ~Sep 2026)

## Short-term

- [ ] Add empty-state messages to iOS tabs (Today, Feeds, Articles) for users who skip feed selection
- [ ] Consider auto-redirecting new web users to `/onboarding` after first login instead of requiring them to click "Choose feeds"
- [ ] Add user administration capabilities (view users, reset accounts)

## Planned

- [ ] D1 -> Supabase Postgres migration (see `decisions.md` ADR-001)
  - Port `schema.sql` to Postgres DDL
  - Set up Supabase CLI migration workflow
  - Swap `db.ts` implementation
  - Convert ~200 SQL queries (syntax differences)
  - FTS5 -> tsvector
  - Run test suite against Postgres

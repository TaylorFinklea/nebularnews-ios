# Next Steps

*Last updated: 2026-03-27*

## Immediate

- [ ] Build and release iOS to TestFlight with all onboarding + empty state changes
- [ ] Test full web flow: new user Apple Sign In -> auto-redirect to /onboarding -> subscribe -> dashboard
- [ ] Test full iOS flow: sign in -> feed selection -> subscribe -> Today tab populates

## Short-term

- [x] ~~Add empty-state messages to iOS tabs~~ (done)
- [x] ~~Auto-redirect new web users to `/onboarding`~~ (done)
- [x] ~~User admin~~ (already existed at `/settings/users`)

## Planned

- [ ] D1 -> Supabase Postgres migration (see `decisions.md` ADR-001)
  - Port `schema.sql` to Postgres DDL
  - Set up Supabase CLI migration workflow
  - Swap `db.ts` implementation
  - Convert ~200 SQL queries (syntax differences)
  - FTS5 -> tsvector
  - Run test suite against Postgres

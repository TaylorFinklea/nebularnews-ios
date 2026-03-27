# Roadmap

## Project

NebularNews — two-repo RSS reader with AI enrichment.
- **Web/Server**: `/Users/tfinklea/git/nebularnews` — SvelteKit on Cloudflare Workers + D1
- **iOS**: `/Users/tfinklea/git/nebularnews-ios` — SwiftUI + NebularNewsKit framework

## Domains

- `app.nebularnews.com` — web app (full access)
- `api.nebularnews.com` — mobile API host (restricted paths)
- `mcp.nebularnews.com` — MCP server host

## Active Milestones

### Multi-user & Auth (complete)
- [x] Users table, per-user data isolation (V17 migration)
- [x] Supabase Auth (magic link + Apple Sign In)
- [x] OAuth PKCE flow for iOS
- [x] Ephemeral browser sessions for OAuth

### Onboarding (complete)
- [x] Guided feed selection with curated catalog (web + iOS)
- [x] Bulk subscribe + auto-pull after selection
- [x] Three-phase iOS onboarding (server connect -> feed selection -> main app)

### Postgres Migration (planned, not started)
- [ ] Swap D1 (SQLite) for Supabase Postgres
- [ ] Keep Workers for compute, use Postgres for data
- [ ] Estimated 2-week focused sprint
- [ ] See `decisions.md` ADR-001 for rationale

## Constraints

- iOS app uses `JSONEncoder` with `.convertToSnakeCase` — all server `/api/mobile/` endpoints must accept both camelCase and snake_case keys
- No Supabase JS SDK — raw HTTP calls to GoTrue API
- `OPENAI_API_KEY` in macOS Keychain, not source control
- Prefer native Apple frameworks on iOS; local-first, background-friendly designs

## Non-goals

- Real-time collaborative editing
- Supabase Edge Functions (staying on Workers for compute)
- React Native or cross-platform rewrites

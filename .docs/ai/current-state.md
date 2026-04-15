# Current State (2026-04-15)

## Architecture
- **Backend**: Cloudflare Workers + D1 at `api.nebularnews.com` in `~/git/nebularnews`
- **iOS app**: SwiftUI + URLSession REST client in `~/git/nebularnews-ios`
- **Auth**: better-auth with Apple Sign In, Bearer token sessions (D1 direct lookup)

## Completed Milestones
- **M1-M5**: Core reading, article UX, AI improvements, search & discovery, macOS app
- **M6**: AI Overhaul — three-tier AI, streaming chat, MCP server, floating AI assistant, admin dashboard, auto-enrichment, scheduled briefs, scoring v2, topic clustering

## M7: Inbox Unification — In Progress

### Done
- Email newsletter backend: CF Email Worker handler + MIME parsing + auto-create feeds per sender
- Newsletter management routes: GET/POST /newsletters/address
- Web clip endpoint: POST /articles/clip (scrapes URL, creates article)
- iOS: newsletter address section in Settings, feed type icons in feed list
- Share Extension source files written (ShareViewController.swift, Info.plist)

### Remaining
- **Share Extension Xcode target**: needs to be added in Xcode (File → New → Target → Share Extension), with shared Keychain access group between main app and extension
- **CF Email Routing**: manual CF Dashboard config — add `read.nebularnews.com` domain, enable Email Routing, catch-all rule → nebular-news worker
- **End-to-end testing**: forward a real newsletter, clip a URL from Safari

## Deployed Migrations
- 0001 through 0007 all applied on production D1

## Known Issues
- Roadmap.md vision text and repo references are stale (still says "Supabase")
- current-state.md was outdated until this update
- Some article images still broken (depends on source feed providing valid URLs)
- Admin dashboard visible to all users in Settings (role-gated on backend but the link is always shown)

## Both Repos Clean
- `nebularnews-ios`: 6b74fea (HEAD)
- `nebularnews`: efef4a0 (HEAD)

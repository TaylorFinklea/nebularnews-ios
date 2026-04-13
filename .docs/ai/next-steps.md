# Next Steps (2026-04-13)

## Immediate — Deploy M6

- [ ] Run migrations 0002-0004 on D1: `wrangler d1 migrations apply DB --env production --remote`
- [ ] Set AI provider keys: `wrangler secret put OPENAI_API_KEY --env production` / `ANTHROPIC_API_KEY`
- [ ] Deploy Workers: `cd ~/git/nebularnews && npx wrangler deploy --env production`
- [ ] Test streaming chat from iOS
- [ ] Test MCP with Claude Desktop
- [ ] Test batch enrichment (POST /enrich/batch)
- [ ] Test follow-up suggestions (>> line parsing)
- [ ] Test Brief 2.0 with depth parameter
- [ ] Configure App Store Connect products (com.nebularnews.ai.basic, com.nebularnews.ai.pro)
- [ ] Test StoreKit sandbox purchase flow
- [ ] TestFlight release with M6 features

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation (currently trusts client)
- [ ] Auto-enrichment on feed poll for subscribers (server-side, in poll-feeds cron)
- [ ] Push notifications for scheduled briefs

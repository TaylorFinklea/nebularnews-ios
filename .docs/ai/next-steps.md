# Next Steps (2026-04-12)

## Immediate — Deploy & Test M6

- [ ] Run migrations 0002-0004 on D1: `wrangler d1 migrations apply DB --env production --remote`
- [ ] Set AI provider keys: `wrangler secret put OPENAI_API_KEY --env production` / `ANTHROPIC_API_KEY`
- [ ] Deploy Workers: `cd ~/git/nebularnews && npx wrangler deploy --env production`
- [ ] Test streaming chat from iOS (send a message, verify words appear incrementally)
- [ ] Test MCP with Claude Desktop (configure with Bearer token, try search_articles)
- [ ] Test batch enrichment (BYOK user, POST /enrich/batch with article IDs)
- [ ] Test follow-up suggestions (chat, verify >> lines parsed into pills)
- [ ] Configure App Store Connect products for StoreKit 2 (com.nebularnews.ai.basic, com.nebularnews.ai.pro)
- [ ] Test StoreKit sandbox purchase flow

## Soon — Polish & Complete

- [ ] B4: iOS "Integrations" settings section (MCP config snippet generator)
- [ ] C4: Brief 2.0 (scheduled push briefs, per-topic, configurable depth)
- [ ] Wire summary style/length user settings through to prompt builder
- [ ] Usage dashboard UI in iOS Settings
- [ ] Scoring v2: add behavioral signals (read depth, time spent) to weighted formula
- [ ] AI-generated weekly reading insights (needs AI call, currently data-only)
- [ ] TestFlight release with M6 features

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation (currently trusts client)
- [ ] Auto-enrichment on poll for subscribers (server-side, in poll-feeds cron)

# Next Steps (2026-04-13)

## Immediate — Test & Ship

- [x] Run migrations 0002-0005 on D1
- [x] Deploy Workers to production
- [ ] Set AI provider keys if not already: `wrangler secret put ANTHROPIC_API_KEY --env production`
- [ ] Test floating AI assistant from iOS (sparkle button → bottom sheet → send message)
- [ ] Test streaming chat (words appear incrementally)
- [ ] Test MCP with Claude Desktop
- [ ] Test auto-enrichment (subscribe → wait for poll → verify summaries appear)
- [ ] Test scheduled briefs (configure morning time → verify push notification)
- [ ] Configure App Store Connect products (com.nebularnews.ai.basic, com.nebularnews.ai.pro)
- [ ] TestFlight release

## M7 Candidates

Pick from these for the next milestone:

1. **Reader depth** — collections/folders, highlights, annotations, export to Readwise/Obsidian/Markdown
2. **Listening** — in-app TTS, CarPlay, podcast-style queue
3. **Inbox unification** — email newsletters as feeds, Safari web clipper
4. **Platform polish** — iPad layout, Lock Screen widgets, Live Activities, Watch glance

## Deferred

- [ ] RevenueCat migration (if StoreKit complexity grows)
- [ ] Apple App Store Server API for receipt validation
- [ ] User timezone support for scheduled briefs (currently UTC)
- [ ] AI assistant direct actions (tool-calling to filter articles, navigate, apply tags)

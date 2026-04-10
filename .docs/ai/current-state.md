# Current State (2026-04-09)

## Architecture
- **Backend**: Supabase project `nebularnews-v2` (vdjrclxeyjsqyqsjzjfj) in us-east-1
- **iOS app**: SwiftUI + Supabase Swift SDK (direct PostgREST + Edge Functions)
- **Repos**: `nebularnews-api` (backend), `nebularnews-ios` (iOS)
- **Old infra**: All decommissioned (CF Workers, Vercel, old Supabase project, web repo archived)
- **Cost**: $0/mo (Supabase free tier)

## Last Session Summary

**Date**: 2026-04-09

- Closed the last two open `[minor]` backlog items (both API code-quality refactors):
  1. **score-articles refactor**: moved the per-user scoring pipeline into
     `_shared/scoring.ts` (`loadUserWeights`, `scoreArticleForUser`,
     `scoreArticlesForUser`). `computeWeightedScore` now also returns
     `weightedAvg`/`dataBackedCount`/`totalSignals` so the insert path no
     longer re-derives them. `score-articles/index.ts`: 455 → 115 lines.
  2. **enrich-article refactor**: split into one handler file per job type
     under `enrich-article/handlers/` (`summarize`, `key-points`, `score`,
     `auto-tag`, `suggest-questions`) plus `enrich-article/shared.ts` for
     fetch/truncate/normalize helpers. `enrich-article/index.ts`:
     496 → 99 lines.
- Both refactors verified with `deno check` + `deno lint`. **Not yet deployed.**
- iOS roadmap updated to mark both items `[x]`.

## Open handoff notes

- `nebularnews-api` is 12 commits ahead of `origin/main` — safe to push when ready.
- `nebularnews-api/supabase/migrations/00009_monitoring_views.sql` is untracked;
  the roadmap says monitoring is done but this file was never committed.
  Review before committing.
- No Edge Function deploys since the refactors landed — run
  `/deploy-function score-articles` and `/deploy-function enrich-article`
  when convenient to confirm behavior in production.

## Phases — all complete
- **M1**: Core reading experience (Supabase backend, auth, feeds, enrichment,
  scoring, offline, push, TestFlight)
- **M2**: Article reading experience (typography, inline images, progress,
  reader mode)
- **M3**: AI improvements (hybrid scoring UI, chat overhaul, suggested
  questions, multi-article "Today's News" chat, BYOK rate limiting)
- **M4**: Search & discovery (tsvector search, feed discovery catalog)
- **M5**: macOS app (builds clean on both iOS and macOS; Xcode signing config
  outside repo)

## Backend (nebularnews-api) — current file map
- 9 migrations, 29 tables with RLS
- 10 Edge Functions deployed; two (score-articles, enrich-article) have
  pending refactor commits ready to ship
- Shared modules: `ai.ts`, `ai-key-resolver.ts`, `constants.ts`, `env-config.ts`,
  `fetch-with-timeout.ts`, `feed-parser.ts`, `logger.ts`, `model-config.ts`,
  `prompts.ts`, `scoring.ts`, `scraper.ts`, `supabase.ts`, `usage.ts`
- Per-function modules: `enrich-article/shared.ts` + 5 handlers under
  `enrich-article/handlers/`

## iOS App (nebularnews-ios) — current state
- TestFlight: Build 8 (2.0.1) shipped
- macOS target passing build; signing requires Apple Developer portal config
  for push entitlement + Sign in with Apple
- No app-side changes this session (all work was API refactors)

## Claude Code Automations
- `.claude/agents/backlog-worker.md` — picks up backlog items by tier
- `.claude/agents/swift-reviewer.md` — SwiftUI code review
- `.claude/skills/release/SKILL.md` — /release for TestFlight
- `.claude/skills/deploy-function/SKILL.md` — /deploy-function for Edge Functions
- `.claude/settings.json` — PostToolUse (Swift build flag) + PreToolUse (credential guard)
- `~/.claude/skills/handoff-prompt/SKILL.md` — /handoff-prompt for rate-limit handoffs

## What's NOT done
- Hybrid AI + algorithmic scoring (cost-controlled)
- Admin user management surface
- `00009_monitoring_views.sql` file committed and dashboard wired up
- Reader enhancements (collections, highlights, annotations)
- Per-topic brief generation + scheduled push delivery

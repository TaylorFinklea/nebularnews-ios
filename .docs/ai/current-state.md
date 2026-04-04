# Current State (2026-04-04)

## Architecture
- **Backend**: Supabase project `nebularnews-v2` (vdjrclxeyjsqyqsjzjfj) in us-east-1
- **iOS app**: SwiftUI + Supabase Swift SDK (direct PostgREST + Edge Functions)
- **Repos**: `nebularnews-api` (backend), `nebularnews-ios` (iOS)
- **Old infra**: All decommissioned (CF Workers, Vercel, old Supabase project, web repo archived)
- **Cost**: $0/mo (Supabase free tier)

## Last Session Summary

**Date**: 2026-04-04

- Restructured roadmap: phased product work (M2-M5) + two-tier backlog for cheaper models
- Completed 10 backlog items via subagent-driven development (6 trivial with Haiku, 2 minor with Sonnet, 2 trivial with Haiku in API)
- Created Claude Code automations: backlog-worker agent, swift-reviewer agent, /release skill, /deploy-function skill, PostToolUse/PreToolUse hooks
- Created global /handoff-prompt skill for rate-limit handoffs to other AI agents
- Cleaned up settings.local.json (94 → 41 wildcard entries)
- Standardized AI handoff docs globally with resume-after-handoff protocol
- iOS build: passing

## Backend (nebularnews-api)
- 29 tables with RLS enabled on all
- 8 migrations applied
- 10 Edge Functions deployed
- New shared modules: `_shared/usage.ts`, `_shared/constants.ts`, `_shared/ai-key-resolver.ts`
- README updated with all 10 functions, .env.example updated with scraper keys

## iOS App (nebularnews-ios)
- Fixed isSaved logic bug (was checking isRead, now checks savedAt)
- Fixed FeedListView force unwraps
- Extracted Task.sleep named constants
- Removed stale CloudKit and MobileAPIClient references from all instruction docs
- TestFlight: Build 4 uploaded (no new release this session)

## Claude Code Automations
- `.claude/agents/backlog-worker.md` — picks up backlog items by tier
- `.claude/agents/swift-reviewer.md` — SwiftUI code review
- `.claude/skills/release/SKILL.md` — /release for TestFlight
- `.claude/skills/deploy-function/SKILL.md` — /deploy-function for Edge Functions
- `.claude/settings.json` — PostToolUse (Swift build flag) + PreToolUse (credential guard)
- `~/.claude/skills/handoff-prompt/SKILL.md` — /handoff-prompt for rate-limit handoffs

## What's NOT done
- macOS target (code ready, needs Xcode setup)
- Widget Extension target (code ready, needs Xcode wiring — backlog item)
- Clean marketing version number (backlog item)
- Per-user AI rate limiting
- Hybrid AI+algorithmic scoring
- Full-text search UI
- Remaining backlog: 14 items (see roadmap.md)

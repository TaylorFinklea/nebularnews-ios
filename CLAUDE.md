# NebularNews iOS Claude Instructions

## Session Workflow
- **Start of session**: Read `docs/ai/roadmap.md`, `docs/ai/current-state.md`, and `docs/ai/next-steps.md` before doing any work. These are the source of truth for project state.
- **End of session**: Update `docs/ai/current-state.md` and `docs/ai/next-steps.md` with what changed. Add to `docs/ai/decisions.md` if any architectural decisions were made. Use `docs/ai/handoff-template.md` as a guide.

## Instruction File Sync
- When you change this `CLAUDE.md`, also review and update `AGENTS.md`, `.cursorrules`, and `.github/copilot-instructions.md` in the same change when the guidance overlaps.
- Shared guidance in these files should stay consistent unless a file is intentionally tool-specific.

## Working Style
- Prefer native Apple frameworks and interaction patterns over custom UI/control systems.
- Keep custom visual treatment for editorial/content surfaces, not utility controls.
- Read the existing code before changing architecture or patterns.
- Make focused, minimal changes that fit the current codebase.

## Code Change Expectations
- After code changes, make a small descriptive commit by default.
- Do not push unless the user explicitly asks.
- Use repository-native edit workflows and avoid broad rewrites unless required.

## Shell Commands
- Run one command at a time unless the output of one must pipe into the next.
- Never chain independent commands with `&&`. Use `git -C <path>` instead of `cd <path> && git`.

## Verification
- Build or test the smallest relevant target after changes.
- Mention clearly if something could not be verified.

## Mobile API Encoding
- `MobileAPIClient` uses `JSONEncoder` with `.convertToSnakeCase`. This means all POST/PATCH/DELETE bodies send snake_case keys (`is_read`, `feed_id`, `add_tag_names`).
- The NebularNews server endpoints parse raw JSON and expect camelCase keys (`isRead`, `feedId`, `addTagNames`).
- **Every server endpoint under `/api/mobile/` MUST accept both camelCase and snake_case keys**: `body?.isRead ?? body?.is_read`.
- The `updateSettings` method is a special case — it uses a plain `JSONEncoder()` (no snake_case) because the settings payload must match the server's camelCase field names exactly.

## Release / TestFlight
- Run `./scripts/release.sh` to archive and upload to TestFlight.
- The script auto-increments both `MARKETING_VERSION` (patch) and `CURRENT_PROJECT_VERSION` (build number) via `agvtool`, archives, exports with automatic signing, uploads to App Store Connect, and commits the version bump.
- No manual Xcode archive workflow needed.

## Project Notes
- `OPENAI_API_KEY` is expected in the macOS Keychain, not in source control.
- Standalone CloudKit sync is state-only. Heavy article cache/runtime data stays local unless the architecture is intentionally changed.
- Prefer local-first and background-friendly designs; do not block core reading flows on optional enrichment.

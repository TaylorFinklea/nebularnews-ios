# NebularNews iOS Agent Instructions

## Instruction File Sync
- When you change this `AGENTS.md`, also review and update `CLAUDE.md`, `.cursorrules`, and `.github/copilot-instructions.md` in the same change when the guidance overlaps.
- Shared guidance in these files should stay consistent unless a file is intentionally tool-specific.

## Working Style
- Prefer native Apple frameworks and interaction patterns over custom UI/control systems.
- Keep custom visual treatment for editorial/content surfaces, not utility controls.
- Read the existing code before changing architecture or patterns.
- Make focused, minimal changes that fit the current codebase.

## Code Change Expectations
- After code changes, make a small descriptive commit by default.
- Do not push unless the user explicitly asks.
- Use `apply_patch` for manual file edits.
- Prefer ASCII unless a file already requires other characters.

## Shell Commands
- Run one command at a time unless the output of one must pipe into the next.
- Never chain independent commands with `&&`. Use `git -C <path>` instead of `cd <path> && git`.

## Verification
- Build or test the smallest relevant target after changes.
- Mention clearly if something could not be verified.

## Project Notes
- `OPENAI_API_KEY` is expected in the macOS Keychain, not in source control.
- Standalone CloudKit sync is state-only. Heavy article cache/runtime data stays local unless the architecture is intentionally changed.
- Prefer local-first and background-friendly designs; do not block core reading flows on optional enrichment.

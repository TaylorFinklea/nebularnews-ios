# NebularNews iOS Copilot Instructions

- Prefer native Apple frameworks and interaction patterns over custom controls.
- Keep custom UI chrome for editorial/content presentation, not utility or management surfaces.
- Read surrounding code before changing architecture or patterns.
- Make focused changes that fit the current codebase.
- After code changes, create a small descriptive commit by default.
- Do not push unless explicitly asked.
- Build or test the smallest relevant target after changes.
- `OPENAI_API_KEY` belongs in the macOS Keychain, not in source control.
- Standalone CloudKit sync is state-only; heavy article cache/runtime data should stay local unless intentionally redesigned.

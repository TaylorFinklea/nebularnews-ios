# NebularNews iOS Copilot Instructions

- Prefer native Apple frameworks and interaction patterns over custom controls.
- Keep custom UI chrome for editorial/content presentation, not utility or management surfaces.
- Read surrounding code before changing architecture or patterns.
- Make focused changes that fit the current codebase.
- After code changes, create a small descriptive commit by default.
- Do not push unless explicitly asked.
- Build or test the smallest relevant target after changes.
- `MobileAPIClient` encodes bodies as snake_case. Server endpoints must accept BOTH camelCase and snake_case keys (e.g., `body?.isRead ?? body?.is_read`).
- `OPENAI_API_KEY` belongs in the macOS Keychain, not in source control.

# Next Steps (2026-04-03)

## Xcode Setup Needed (no code changes)
- Add macOS destination to NebularNews target (code is ready with #if os guards)
- Add Widget Extension target, wire up existing files from NebularNewsWidgets/
- Fix marketing version: set clean 2.0.0 in project settings
- Set up App Groups for widget data sharing

## Product Improvements
- **Hybrid scoring**: layer AI scoring on top of algorithmic (user triggers "AI Score" per article)
- **Per-user AI rate limiting**: enforce quotas on global API keys, track via ai_usage table
- **Search UI**: prominent search bar using the tsvector full-text search index
- **Article reading experience**: richer typography, inline images, reading progress
- **Admin user management**: view users, reset algorithms, set roles, manage global keys
- **Feed discovery**: suggest feeds based on user interests, popular feeds among users

## Infrastructure
- **Docker self-hosting**: test end-to-end with `supabase start`
- **CI/CD**: GitHub Actions for Edge Function deployment on push
- **Monitoring**: track Edge Function errors, scoring quality, scraping success rates
- **Backup**: automated Supabase DB backups

## Developer Tooling
- Complete `opencode auth login` for Google/Gemini if Gemini-backed agents should be available locally
- Optionally install `@code-yeongyu/comment-checker` to clear the remaining `bunx oh-my-opencode doctor` warning for the comment-checker hook

## Future Platforms
- **macOS app**: code is platform-ready, add Xcode target + sidebar navigation
- **Web client**: thin client on Supabase PostgREST (if needed)
- **Android**: Kotlin/Compose client against same Supabase backend

## Scaling
- **Supabase Pro**: upgrade when exceeding free tier limits (500MB DB, 2M function invocations)
- **Connection pooling**: Supabase handles this, but monitor as user count grows
- **Feed polling optimization**: prioritize active feeds, reduce polling for stale feeds

---
name: deploy-function
description: Deploy a Supabase Edge Function to production
user-invocable: true
disable-model-invocation: true
---

# Deploy Edge Function

Deploy a Supabase Edge Function to the NebularNews production project.

## Usage

`/deploy-function <function-name>`

If no function name is provided, list all available functions and ask which to deploy.

## Available Functions

- `article-chat` — Chat about articles with AI
- `enrich-article` — AI summarize, score, key points, auto-tag
- `export-opml` — OPML feed export
- `generate-news-brief` — AI editorial briefing
- `import-opml` — OPML feed import
- `poll-feeds` — RSS/Atom feed polling
- `process-jobs` — Job queue processor
- `score-articles` — Algorithmic scoring
- `scrape-article` — Browser scraping with Steel/Browserless
- `send-notification` — APNS push notifications

## Steps

1. **Validate function name**: Check that the function exists in `/Users/tfinklea/git/nebularnews-api/supabase/functions/`. If not, show the list above and ask.

2. **Check for uncommitted changes** in the API repo:
   ```bash
   git -C /Users/tfinklea/git/nebularnews-api status
   ```
   If there are uncommitted changes to the function being deployed, ask whether to commit first.

3. **Deploy**:
   ```bash
   cd /Users/tfinklea/git/nebularnews-api && npx supabase functions deploy <function-name> --no-verify-jwt
   ```

4. **Report result**: Show the deployment output. If it failed, report the error.

5. If the user says "all", deploy every function:
   ```bash
   cd /Users/tfinklea/git/nebularnews-api && npx supabase functions deploy --no-verify-jwt
   ```

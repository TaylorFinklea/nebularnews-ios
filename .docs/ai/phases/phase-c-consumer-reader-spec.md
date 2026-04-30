# Phase C — Consumer Reader (`app.nebularnews.com`)

> Status: **Approved (2026-04-30)**
> Target tier: **Sonnet implementer**, sized for ~8 sub-phase sessions.
> Depends on: M17 admin-web Apple Sign In going live (Apple Services ID + APPLE_CLIENT_SECRET_WEB on Wrangler prod).
>
> ## Decisions confirmed (2026-04-30)
> 1. **Repo**: new sibling repo `/Users/tfinklea/git/nebularnews-app`.
> 2. **Apple Sign In**: reuse `com.nebularnews.web` Services ID (no new Developer Portal config, no new `.p8`-signed JWT).
> 3. **Data fetching**: SSR via `+page.server.ts`. Bearer token stays httpOnly server-side. Sparkle chat uses a same-origin SvelteKit `+server.ts` proxy that forwards to the streaming Worker endpoint.
> 4. **Scope**: v1 includes Today, Article detail, Brief history, Sparkle chat, **BYOK key entry UI**, **feed management** (subscribe/unsubscribe/pause/OPML), **highlights/annotations/collections**. Web push notifications **deferred**.

## Product Overview

A public-facing SvelteKit reader at `app.nebularnews.com` for users who don't have iOS — Android, web-first folks, anyone trying NebularNews from a desktop. Surfaces:

- **Today** — daily brief lead image + bullets, hero article, up-next list, resume card, stats; mirrors `CompanionTodayView` on iOS.
- **Article detail** — title, body (rich content), summary, key points, mark-read, save, sparkle chat anchor.
- **Brief history** — list of past briefs with edition labels; tap into the same brief render used on Today.
- **Sparkle chat** — the AI assistant panel, page-context-aware, streamed via `/chat/assistant`.

In scope for Phase C v1:
- Today, Article detail, Brief history, Sparkle chat (sub-phases 1–5).
- BYOK key entry UI (sub-phase 6).
- Feed management — subscribe/unsubscribe/pause/min-score/max-per-day/OPML (sub-phase 7).
- Highlights, annotations, collections (sub-phase 8).

Out of scope for Phase C (deferred to later phases):
- Tag editing beyond what feed management exposes.
- Reactions beyond thumb-up/down on article detail.
- Share extension equivalents.
- Web push notifications (service worker + browser push + APNs-equivalent — big lift, deferred).
- Newsletters / Web Clips inbox surfaces.
- Onboarding / curated-feed catalog (consumer signs in and inherits whatever feeds were set up on iOS or admin; feed mgmt covers add-by-URL).

Success criteria: a non-iOS user can sign in with Apple at `app.nebularnews.com`, see their Today screen, read a single article end-to-end with summary and key points, talk to sparkle, and browse brief history.

## Current State (anchors)

- **Backend** (`/Users/tfinklea/git/nebularnews`): Workers + D1, all routes already exist for iOS — `/today` (`src/routes/today.ts`), `/articles/:id` (`src/routes/articles.ts:131`), `/brief/history` + `/brief/:id` (`src/routes/brief.ts:238`/`:294`), `/chat/assistant` SSE (`src/routes/chat.ts:879`). CORS already allowlists `https://app.nebularnews.com` (`src/index.ts:49-64`).
- **Auth backend**: better-auth in `src/lib/auth.ts` already accepts a multi-audience Apple config (App ID for iOS native id_tokens, Services ID for web OAuth). `trustedOrigins` already lists `nebularnews://*`, `localhost:*`, `admin.nebularnews.com`, `api.nebularnews.com` — `app.nebularnews.com` will need to be added.
- **Web handoff endpoint**: `GET /api/auth/web-handoff?target=...` (`src/routes/auth.ts:9-47`). The allowlist `ALLOWED_HANDOFF_TARGETS` currently only contains `https://admin.nebularnews.com/sign-in/callback` and `http://localhost:5173/sign-in/callback`. Phase C adds `https://app.nebularnews.com/sign-in/callback` (and a second localhost port for dev).
- **Admin web reference** (`/Users/tfinklea/git/nebularnews-web`): SvelteKit 2 + Svelte 5 + Tailwind v4 + `@sveltejs/adapter-cloudflare`. Cookie name `nn_session`, 30-day TTL, set in `src/lib/auth/session.ts`. Server-load uses `event.locals.sessionToken` populated by `src/hooks.server.ts`. API client at `src/lib/api/client.ts` handles bearer token injection + envelope unwrap + ApiError. `src/lib/components/StatCard.svelte` is the only shared component.
- **iOS reference** (`/Users/tfinklea/git/nebularnews-ios`): `NebularNews/Services/StreamingChatService.swift` documents the SSE event shape (`delta`, `tool_call_propose`, `tool_call_server_result`, `tool_call_client`, `done`, `error`). `NebularNews/Features/AIAssistant/AIPageContext.swift` defines the page-context payload shape.
- **Brief lead image** (`/Users/tfinklea/git/nebularnews/src/cron/scheduled-briefs.ts:21-26`): deterministic rotation `https://r2-fallback.nebularnews.com/fallback-NNN.jpg` keyed by hash of brief id over 30-image pool. Backend already writes `image_url` on every brief, so the consumer reader does not need to recompute the rotation — it renders `image_url` straight from `/brief/:id`.

## Architecture Decisions

### Repo layout — **NEW REPO `nebularnews-app`** (recommended)

Trade-off:

- **Subdirectory of `nebularnews-web`**: cheaper to share `app.css` tokens, the `api/client.ts`, and `auth/session.ts`. Single deploy pipeline. But it forces one Cloudflare Pages project to serve two domains with two distinct routing trees, which SvelteKit's adapter doesn't model cleanly without per-host route guards. Also conflates "admin" and "consumer" concerns — different release cadence, different bundle, different access control. Authoring noise.
- **New repo `nebularnews-app`**: adds one repo to maintain but cleanly separates the bundle, the deploy target (its own Pages project `nebularnews-app`), and the ownership story (admin = staff, app = customers). The shared bits we want — API client, auth/session helpers, app.css tokens — copy at a couple-hundred-line cost, which is cheaper than the routing conditionals that the subdirectory option requires forever.

**Decision: new repo at `/Users/tfinklea/git/nebularnews-app`**, sibling to `nebularnews`, `nebularnews-web`, `nebularnews-ios`. Cloudflare Pages project `nebularnews-app`, custom domain `app.nebularnews.com`. SvelteKit 2 + Svelte 5 + Tailwind v4 + `@sveltejs/adapter-cloudflare`. Same versions as `nebularnews-web` `package.json` to avoid drift.

Files copied at scaffold time (verbatim, then specialized):

- `src/lib/api/client.ts` — bearer + envelope client, no changes.
- `src/lib/api/types.ts` — extend with consumer-facing response types (Today, Article, Brief).
- `src/lib/auth/session.ts` — drop the `is_admin` requirement; for consumer, any signed-in user is valid. Replace the `/admin/me` round-trip with `/auth/me` (see Auth section).
- `src/hooks.server.ts` — same shape, but no admin gate.
- `src/app.css` — copy the same Tailwind layer + design tokens; consumer adds its own typography stack on top.

### Auth — **single-audience Apple, shared Services ID `com.nebularnews.web`**

The user's open question is: do we add `app.nebularnews.com` to the existing Services ID, or mint a third clientId?

**Decision: reuse `com.nebularnews.web` Services ID.** Apple Services IDs allow multiple Return URLs under one identifier. Adding `https://api.nebularnews.com/api/auth/callback/apple` is already done for admin; since the OAuth callback always lands on `api.nebularnews.com` (better-auth's `baseURL`), the redirect target on Apple's side does not change at all when adding `app.nebularnews.com` as a consumer site. What changes is:

1. better-auth's `trustedOrigins` array (`src/lib/auth.ts:51-56`) — add `'https://app.nebularnews.com'` next to the admin entry.
2. The Workers handoff allowlist (`src/routes/auth.ts:9-12`) — add `https://app.nebularnews.com/sign-in/callback` and a second localhost port (5174 to avoid colliding with admin's 5173).
3. CORS ALLOWED_WEB_ORIGINS already contains `app.nebularnews.com` (`src/index.ts:51`) — no change.
4. No new Apple Developer Portal config, no new client_secret JWT, no new Wrangler secret. We share `APPLE_SERVICES_ID` + `APPLE_CLIENT_SECRET_WEB`.

Why not a third clientId: a separate Services ID would mean a second `.p8`-signed JWT (or a multi-aud JWT), a second Wrangler secret, and a second `socialProviders.apple` block — all to gain nothing, since the consumer and admin reach the same backend better-auth instance. The audience already covers both via the multi-`audience` array in `createAuth` (App ID for iOS + Services ID for any web client).

Auth flow:

1. User on `app.nebularnews.com` clicks "Continue with Apple" → SvelteKit redirects to `https://api.nebularnews.com/api/auth/sign-in/social?provider=apple&callbackURL=https://api.nebularnews.com/api/auth/web-handoff?target=https://app.nebularnews.com/sign-in/callback`.
2. better-auth handles the OAuth round-trip with Apple. On success it sets its session cookie on `api.nebularnews.com`.
3. better-auth redirects to `callbackURL` (the web-handoff endpoint). Workers `/auth/web-handoff` reads the just-minted session cookie, looks up `session.token`, and 302s to `https://app.nebularnews.com/sign-in/callback?token=<token>`.
4. Consumer SvelteKit `/sign-in/callback` validates the token (calls `/auth/me`, see below), sets its own httpOnly cookie `nn_session`, then redirects to `/today`.
5. On every subsequent request, `hooks.server.ts` reads `nn_session`, hits `/auth/me`, populates `event.locals.user`. Layout server-loads check `event.locals.user`; if null, redirect to `/sign-in`.

We need a public `/auth/me` route on the backend — currently `/admin/me` is admin-gated. **New backend route** `GET /api/auth/me` (mounted on `protectedApi`, no admin requirement) returns `{ user_id, email, name, is_admin }`. Admin web can migrate to this same route in a future cleanup, or keep using `/admin/me`.

### Data fetching — **SSR via `+page.server.ts`** (recommended)

Trade-off:

- **SSR**: each page does a Worker round-trip on the server, returning fully-hydrated HTML. First paint is content, not skeleton. Mirrors admin-web's pattern, so the API client and auth helpers we lift over Just Work. Cost: Pages function invocation on every navigation (cold-ish, but Workers warm fast). For desktop reading where pages are visited intermittently this is fine; the user's perception is "it just loads."
- **Client-side fetch**: ship a thin shell, fetch JSON in `+page.svelte`, render skeletons → real content. Faster TTFB, but TTFP-with-content is slower because of the chained fetch. Requires CORS-with-credentials browser fetches from `app.nebularnews.com` to `api.nebularnews.com` — already enabled, but every page still pays the auth-cookie attach cost. Also forces us to expose the bearer token to JS, which we explicitly avoided in admin (cookie is httpOnly).

**Decision: SSR for Today, article detail, brief history, brief detail. Client-side stream for sparkle chat.** The chat is inherently streaming over SSE and is opened on user gesture, so SSR doesn't apply — it's a pure browser EventSource consumer.

### Routing

```
/                       redirect to /today if signed in, else /sign-in
/sign-in                Apple Sign In landing
/sign-in/callback       handoff token consumer (server endpoint, sets cookie, redirects to /today)
/sign-out               server endpoint, clears cookie, hits POST /auth/sign-out
/today                  Today surface (SSR)
/articles/[id]          Article detail (SSR)
/briefs                 Brief history list (SSR)
/briefs/[id]            Single brief render (SSR)
/chat                   Full-screen chat fallback (mobile or "Open chat" deep link)
```

The sparkle chat is **always available as a slide-out panel** on every authenticated page (right-edge drawer on desktop, bottom sheet on mobile). `/chat` exists only as a deep-link fallback — deep links elsewhere in the app may want to "open chat with this article context", which is easier as a full route than a forced-state query param.

### Navigation

Responsive — single layout, two presentations:

- **Desktop (≥768px)**: persistent left sidebar with Today / Briefs / Sign out + a right-side floating sparkle button that toggles a 380px-wide drawer over the right third of the page.
- **Mobile (<768px)**: top header with hamburger → sidebar as overlay drawer; sparkle as a bottom-right floating action button that opens a full-height bottom sheet.

No tab bar — consumer reader has only two main destinations (Today, Briefs); a tab bar would feel over-built. Sidebar grows naturally if Phase D adds Saved or Search.

### Streaming chat

Browser-native `EventSource`. Pseudo:

```ts
const es = new EventSource(`${apiBase}/api/chat/assistant?stream=true`, { withCredentials: false });
// We can't use POST with EventSource; backend currently uses POST /chat/assistant?stream=true.
```

`EventSource` is GET-only. Backend currently uses POST for the chat assistant (`src/routes/chat.ts:879`). Two options:

- **(A)** Add a new `streamFetch` helper on the consumer that uses `fetch(POST)` + `ReadableStream` reader to consume `text/event-stream` manually. ~50 lines, no backend change. **Recommended.**
- **(B)** Add a GET variant of `/chat/assistant` that takes args via query string. Backend churn for no win.

**Decision: (A)** — write a small `lib/sse/stream.ts` that calls `fetch(POST, body, headers={Authorization, Accept: text/event-stream})` and yields parsed `{type, ...}` events. Reuse the auth header injection from `lib/api/client.ts`. Token comes from the cookie via a `+server.ts` proxy — the consumer fetches `/api/proxy/chat/assistant` on the **same origin** (SvelteKit endpoint), and that proxy forwards to Workers with the bearer token attached server-side. This keeps the bearer out of browser JS.

So the path is: `EventSource`-shaped consumer in browser → SvelteKit `/api/proxy/chat/assistant` `+server.ts` POST → forwards to Workers `/chat/assistant?stream=true` with bearer → streams response back to browser unmodified. The proxy is ~30 lines and lets us keep the cookie httpOnly.

### Component reuse from admin web

- **Lift verbatim**: `lib/api/client.ts`, `lib/api/types.ts` (extend), `app.css` Tailwind setup + color tokens, `lib/components/StatCard.svelte` (reuse on Today for the unread/new/high-fit row).
- **Consumer-distinct visual identity**: editorial typography (serif body via `font-serif` Tailwind utility, sans for chrome), softer surfaces, larger reading column (max-width 720px on article detail). Admin is dense and utilitarian; consumer is reader-first.

### CORS coordination with backend

The roadmap calls out "CORS tightening on the Workers API — currently `*`; lock to admin + app + native scheme before consumer launch." The good news: **CORS is already locked.** `src/index.ts:49-64` already allowlists exactly `admin.nebularnews.com` and `app.nebularnews.com` plus localhost. iOS bypasses CORS entirely (no Origin header on URLSession). No backend CORS work is needed for Phase C.

What this Phase C work *does* unblock: the roadmap entry can be marked done once the consumer reader ships and we verify no rogue origins leak through.

## Page Specs

Sequence the implementer should follow:

### Sub-phase 1 — Repo scaffold + Auth (one Sonnet session)

1. Create `/Users/tfinklea/git/nebularnews-app` from `nebularnews-web` as a starting point: copy `package.json`, `svelte.config.js`, `vite.config.ts`, `tsconfig.json`, `wrangler.toml`, `src/app.css`, `src/app.html`, `src/app.d.ts`, `src/hooks.server.ts`, `src/lib/api/`, `src/lib/auth/session.ts`. Replace `name` in `package.json` to `nebularnews-app`. Strip everything under `src/routes/admin/`, `src/lib/components/StatCard.svelte` for now (will add back when Today needs it).
2. Edit `src/lib/auth/session.ts`: replace `/admin/me` calls with `/auth/me`, replace `AdminMe` type with `Me` (`{ user_id, email, name }`), drop the `is_admin` filter.
3. **Backend change in `nebularnews`** (`src/routes/auth.ts`): add `GET /auth/me` route on the protected side (or mount inside `protectedApi`). Returns `{ ok: true, data: { user_id, email, name, is_admin } }`. Add `https://app.nebularnews.com/sign-in/callback` and `http://localhost:5174/sign-in/callback` to `ALLOWED_HANDOFF_TARGETS`. Add `'https://app.nebularnews.com'` to better-auth `trustedOrigins` in `src/lib/auth.ts:51-56`.
4. Build `src/routes/sign-in/+page.svelte` (Apple button + dev-bypass form copied from admin) + `src/routes/sign-in/+page.server.ts` (build the `signInUrl` like admin does, point `target` at `app.nebularnews.com/sign-in/callback`).
5. Build `src/routes/sign-in/callback/+server.ts` (token validation via `/auth/me`, set cookie, redirect to `/today`).
6. Build `src/routes/sign-out/+server.ts` (clear cookie, optionally POST `/auth/sign-out` for cleanliness, redirect to `/sign-in`).
7. Build `src/routes/+layout.server.ts` (surface `locals.user`), `src/routes/+layout.svelte` (responsive nav skeleton — sidebar on desktop, hamburger on mobile, sparkle FAB).
8. Wire root `+page.server.ts` redirect (`/` → `/today` if signed in, `/sign-in` otherwise).
9. Deploy preview to `nebularnews-app.pages.dev`, hand-test sign-in. Custom domain wiring (`app.nebularnews.com`) is a manual CF Dashboard step — document in repo `README.md`.

**Files touched** (new repo unless noted):
- `nebularnews-app/package.json`, `svelte.config.js`, `vite.config.ts`, `tsconfig.json`, `wrangler.toml`, `src/app.css`, `src/app.html`, `src/app.d.ts`, `src/hooks.server.ts`
- `nebularnews-app/src/lib/api/{client,types}.ts`, `nebularnews-app/src/lib/auth/session.ts`
- `nebularnews-app/src/routes/{+layout.server.ts,+layout.svelte,+page.server.ts,sign-in/+page.svelte,sign-in/+page.server.ts,sign-in/callback/+server.ts,sign-out/+server.ts}`
- **Backend**: `nebularnews/src/routes/auth.ts` (extend allowlist + add `/auth/me`), `nebularnews/src/lib/auth.ts` (extend trustedOrigins).

**Acceptance**: `[ ]` Sign in via Apple at `app.nebularnews.com` (or preview URL with localhost target) → cookie set → `/today` placeholder loads → "signed in as <email>" shows in nav.

### Sub-phase 2 — Today (one Sonnet session)

1. `src/routes/today/+page.server.ts`: server-load calls `api.get<TodayResponse>('/today', { sessionToken: locals.sessionToken })`. Type `TodayResponse` matches the shape in `nebularnews/src/routes/today.ts:122-135`.
2. `src/routes/today/+page.svelte`: render in this order, top to bottom:
   - **Resume card** (if `resume` present) — slim card with image, title, "X% read", links to `/articles/[id]`. Single-line.
   - **News brief card** (if `news_brief` present) — large card with `news_brief.title`, `edition_label`, `generated_at` (relative), and the bullets list. The brief lead image comes from a separate fetch — see step 3 below — because `/today` doesn't include `image_url`. Use the same fallback computation as iOS: render whatever `/today.news_brief` carries; if no image and we have a brief id, fetch `/brief/:id` for `image_url` (which the backend already fills via `fallbackImageForBriefId`). For Phase C, simpler approach: fetch `/brief/:id` lazily only when user clicks into the brief — Today just shows the bullets. **Decision: don't show a hero image on Today's brief card; keep it text-forward.** The iOS app renders an image because of NSE/lock-screen constraints; web doesn't have those constraints. Saves a query.
   - **Stats row** — three `StatCard`s: Unread, New today, High-fit unread (from `today.stats`).
   - **Hero article** (`today.hero`) — large article card with image (if `image_url`), title, source name, score badge.
   - **Up-next** (`today.up_next[]`) — list of compact article cards.
3. `src/lib/components/ArticleCard.svelte` — props `{ article, variant: 'hero' | 'compact' | 'resume' }`. Editorial styling (serif title, sans byline). Click navigates to `/articles/[id]`.
4. `src/lib/components/BriefCard.svelte` — props `{ brief, variant: 'today' | 'detail' }`. Bullet rendering supports the schema iOS uses (bullets are `{ headline: string; body: string; source_id?: string }[]` per `news_brief_editions.bullets_json`).
5. Empty states: if `today.up_next.length === 0` and no brief and no resume, render an "All caught up" card with a link to Briefs.

**Files touched**: `nebularnews-app/src/routes/today/{+page.server.ts,+page.svelte}`, `nebularnews-app/src/lib/components/{ArticleCard,BriefCard,StatCard}.svelte`.

**Acceptance**: `[ ]` Today renders with brief, hero, up-next, stats for a real user account. `[ ]` Click hero → article detail (works after sub-phase 3). `[ ]` Click brief → `/briefs/<id>` (works after sub-phase 4).

### Sub-phase 3 — Article detail (one Sonnet session)

1. `src/routes/articles/[id]/+page.server.ts`: load `/articles/:id` and the response matches `nebularnews/src/routes/articles.ts:208-229`. POST `/articles/:id/read` with `{ is_read: 1 }` after the load resolves so the article auto-marks as read on open (mirrors iOS behavior).
2. `src/routes/articles/[id]/+page.svelte`:
   - **Header**: title, byline (source · author · published date · reading time = `Math.round(article.word_count / 200)` min).
   - **Score badge** (if `score`): small pill colored by score 1-5.
   - **Action bar**: Save / Unsave toggle (POST `/articles/:id/save`), thumb up/down (POST `/articles/:id/reaction` with `value: 1` or `-1`), Open Source link (external).
   - **Summary card** (if `summary`): markdown-rendered `summary.summary_text` with provider/model attribution footer.
   - **Key points** (if `key_points`): rendered list from `JSON.parse(key_points.key_points_json)`.
   - **Article body**: render `article.content_html` if present (sanitized — see Edge Cases), else `article.content_text` as paragraphs, else "Source content unavailable" with link out.
3. Markdown rendering: pull in `marked` + `dompurify`. Keep both server-rendered (use `marked` in `+page.server.ts` if reading layout perf matters). Alternatively, render in-browser inside the Svelte template — simpler, fine for Phase C.
4. HTML sanitization: `article.content_html` is already extracted by Readability on the backend, but it could still contain script tags from a malicious feed. Run through `dompurify` (browser) or a server-side sanitizer (`isomorphic-dompurify`) before rendering.

**Files touched**: `nebularnews-app/src/routes/articles/[id]/{+page.server.ts,+page.svelte}`, `nebularnews-app/src/lib/components/{ScoreBadge,ActionBar,SummaryCard,KeyPointsList,RichArticleBody}.svelte`, `nebularnews-app/package.json` (+ `marked`, `dompurify`, `isomorphic-dompurify` deps).

**Acceptance**: `[ ]` Article opens with title, body, summary, key points. `[ ]` Marks as read on open (verify in iOS). `[ ]` Save toggles persist round-trip. `[ ]` Reaction up/down persists. `[ ]` HTML is sanitized — script tags do not execute.

### Sub-phase 4 — Brief history (one Sonnet session)

1. `src/routes/briefs/+page.server.ts`: call `GET /brief/history` (response shape: `{ briefs: [{ id, generated_at, edition_kind, edition_slot, ... }] }` — verify in `nebularnews/src/routes/brief.ts:238`).
2. `src/routes/briefs/+page.svelte`: list grouped by date (today / yesterday / earlier). Each row shows edition (Morning / Evening), time, bullet count.
3. `src/routes/briefs/[id]/+page.server.ts`: call `GET /brief/:id`. Returns full brief with `bullets`, `image_url`, `generated_at`, etc.
4. `src/routes/briefs/[id]/+page.svelte`: render image (the `image_url` from backend will be the rotation fallback if no candidate image), edition label, bullets — the BriefCard component built in sub-phase 2 with `variant: 'detail'` works here.

**Files touched**: `nebularnews-app/src/routes/briefs/{+page.server.ts,+page.svelte,[id]/+page.server.ts,[id]/+page.svelte}`.

**Acceptance**: `[ ]` Briefs list shows the user's recent briefs newest first. `[ ]` Tapping a brief loads detail with image + bullets. `[ ]` Empty state ("No briefs yet — generate one from iOS") if zero briefs.

### Sub-phase 5 — Sparkle chat (one Sonnet session)

1. `src/lib/sse/stream.ts`: `async function* streamPost(url, body, opts)` — calls `fetch(url, { method: 'POST', body: JSON.stringify(body), headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream', ...opts.headers } })`, reads `response.body` as a `ReadableStream<Uint8Array>`, parses SSE frames (`data: {...}\n\n`), yields parsed JSON events. Cancellation via `AbortController` passed in `opts.signal`.
2. `src/routes/api/proxy/chat/assistant/+server.ts`: SvelteKit `+server.ts` endpoint at `/api/proxy/chat/assistant`. Reads cookie, attaches bearer, forwards POST to `https://api.nebularnews.com/api/chat/assistant?stream=true`, pipes the response body back unchanged. This keeps the token out of browser JS.
3. `src/lib/components/SparkleChatPanel.svelte`: drawer/sheet UI. Two modes:
   - **Empty thread** — show 4-6 suggested prompts based on page context ("Summarize Today's headlines", "What's worth reading?", "Find articles about X").
   - **Active thread** — message list, streaming bubble for the in-flight assistant turn, input at bottom.
4. Page context payload — match the iOS `AIPageContext` shape:
   ```ts
   { pageType: 'today' | 'article' | 'briefs' | 'brief_detail',
     pageLabel: string,
     articleId?: string,
     briefId?: string }
   ```
   Wire from each page's layout: each `+page.svelte` writes its current context to a Svelte store, the chat panel reads from the store on open.
5. Tool-call events: backend may send `tool_call_propose`, `tool_call_server_result`, `tool_call_client`. For Phase C, **render server tool results as inline confirmation chips** (e.g., "Marked 12 articles as read"); **silently ignore client tool calls** for Phase C (no client-side action dispatcher yet); **render proposals as a confirm/reject button row** (POST `/chat/confirm-tool` to resume).
6. New thread button → POST `/chat/assistant/new`.
7. History → GET `/chat/assistant/history`, list previous threads in a side-panel inside the chat drawer.
8. Markdown: render assistant text via `marked` + `dompurify` (already a dep from sub-phase 3).

**Files touched**: `nebularnews-app/src/routes/api/proxy/chat/assistant/+server.ts`, `nebularnews-app/src/lib/sse/stream.ts`, `nebularnews-app/src/lib/components/SparkleChatPanel.svelte`, `nebularnews-app/src/lib/stores/pageContext.ts`, `nebularnews-app/src/routes/+layout.svelte` (mount the panel + sparkle FAB).

**Acceptance**: `[ ]` Sparkle FAB opens drawer on every signed-in page. `[ ]` Sending "what's worth reading?" streams a response token-by-token. `[ ]` Page context shifts when navigating Today → Article (verify a context-shift segment renders, matching iOS). `[ ]` New thread button starts fresh. `[ ]` Tool-call confirmation chip renders for at least one server tool (e.g., `mark_articles_read`). `[ ]` Token does not appear in browser-tools network tab response bodies (proxy keeps it server-side).

### Sub-phase 6 — BYOK key entry UI (one Sonnet session)

Mirrors iOS BYOK in Settings → AI: lets a signed-in consumer add their own OpenAI / Anthropic key. Backend already supports the BYOK headers (`x-user-api-key` / `x-user-api-provider`) and the user-keys persistence path (see `nebularnews/src/routes/settings.ts` and the `user_api_keys` table).

1. `src/routes/settings/+layout.server.ts` — gate to signed-in users only (redundant with hooks).
2. `src/routes/settings/+layout.svelte` — settings shell with sub-nav: AI keys, Feeds (sub-phase 7), Account.
3. `src/routes/settings/ai/+page.server.ts` — `load()` calls `GET /settings/api-keys` (returns existing key fingerprints + provider, never the raw key). Form actions: `setKey` (POST `/settings/api-keys` with `{ provider, api_key }`), `deleteKey` (DELETE `/settings/api-keys/:provider`).
4. `src/routes/settings/ai/+page.svelte` — list current keys with provider, masked fingerprint, last-used. Add-key form with provider dropdown (OpenAI / Anthropic) + paste-only key input + "Test" button (POST `/settings/api-keys/test` to validate before saving).
5. Render which key sparkle is currently using (BYOK vs server default) at the top of the settings/ai page.

**Files touched**: `nebularnews-app/src/routes/settings/{+layout.server.ts,+layout.svelte}`, `nebularnews-app/src/routes/settings/ai/{+page.server.ts,+page.svelte}`. Backend: confirm `/settings/api-keys` route exists; if not, parity with iOS implementation already on backend.

**Acceptance**: `[ ]` Add OpenAI key, see masked fingerprint render. `[ ]` Send a sparkle message and confirm it routes through BYOK (verify via `/admin/usage` after the call — provider attribution in `ai_usage` table). `[ ]` Delete key, sparkle falls back to server default.

### Sub-phase 7 — Feed management (one Sonnet session)

Lifts feed management from admin web's pattern but consumer-scoped to the signed-in user's subscriptions. Backend routes: `GET /feeds`, `POST /feeds`, `DELETE /feeds/:id`, `PATCH /feeds/:id/settings` (already shipped with `If-Match` ETag from M12 / 412-conflict spec).

1. `src/routes/settings/feeds/+page.server.ts` — `load()` calls `GET /feeds`. Form actions: `subscribe` (POST `/feeds` with normalized URL), `unsubscribe` (DELETE `/feeds/:id`), `updateSettings` (PATCH `/feeds/:id/settings` with `paused`, `max_articles_per_day`, `min_score`).
2. `src/routes/settings/feeds/+page.svelte` — list of subscribed feeds with title, source domain, error count, paused-indicator. Each row has expand/collapse with the per-feed settings sub-form. Add-feed input at the top.
3. `src/routes/settings/feeds/import/+page.svelte` — OPML import drag-and-drop. Upload action POSTs `multipart/form-data` to `/feeds/import` (verify backend supports OPML import; iOS uses it).
4. `src/routes/settings/feeds/discover/+page.svelte` — curated catalog (re-uses backend's existing discover endpoint if present). Optional sub-feature; defer if backend doesn't expose it.
5. URL normalization client-side: lift the iOS `FeedURLNormalizer` rules (subreddit `.rss`, hnrss for hacker news) — the backend has a TypeScript port at `src/lib/feed-url-normalizer.ts`. Confirm and reuse.

**Files touched**: `nebularnews-app/src/routes/settings/feeds/{+page.server.ts,+page.svelte,import/+page.svelte,discover/+page.svelte}`, `nebularnews-app/src/lib/feed-url-normalizer.ts` (lift from backend or import via shared package).

**Acceptance**: `[ ]` Subscribe to a real RSS feed → confirm appears in `/today` after next poll. `[ ]` Pause a feed → confirm articles stop appearing. `[ ]` OPML upload of a 10-feed file → all subscribe. `[ ]` Adjust max-articles-per-day → setting persists round-trip. `[ ]` 412 conflict path: edit settings on iOS and web simultaneously, save web after iOS — confirm conflict surface uses the same diff sheet shape (or graceful "settings changed elsewhere" toast).

### Sub-phase 8 — Highlights / annotations / collections (one Sonnet session)

Mirrors iOS M8 surfaces. Backend routes: `/articles/:id/highlights`, `/articles/:id/annotations`, `/collections`, `/collections/:id/articles` (all per `nebularnews/src/routes/articles.ts` and `collections.ts` if present — verify).

1. **Article detail extensions** (`src/routes/articles/[id]/+page.svelte`):
   - **Highlight creation**: text-selection menu → "Highlight" button → POSTs `/articles/:id/highlights` with `{ text, anchor_start, anchor_end }`. Render highlights as inline `<mark>` elements in the body on subsequent loads.
   - **Annotation pane**: notes drawer or sticky-note style card next to the article body. Add/edit/delete annotations.
   - **Save to collection**: dropdown above the article action bar → list user's collections → POST `/collections/:id/articles`.
2. **Collections list** at `/collections/+page.svelte`: list of user's collections with article counts. Click a collection → list of articles in it.
3. **Collection detail** at `/collections/[id]/+page.svelte`: shows articles in that collection; remove-from-collection action.
4. **Markdown export**: per-article and per-collection `<a>` links (POST `/articles/:id/export.md` and `/collections/:id/export.md` if the backend supports; otherwise generate Markdown client-side from loaded data).
5. Handle highlight rendering edge cases: when article body re-extracts (rescrape), anchors may shift — gracefully degrade by showing highlights as a list at the end of the article rather than inline if anchors fail to resolve.

**Files touched**: `nebularnews-app/src/routes/articles/[id]/+page.svelte` (extend), `nebularnews-app/src/routes/collections/{+page.server.ts,+page.svelte,[id]/+page.server.ts,[id]/+page.svelte}`, `nebularnews-app/src/lib/components/{HighlightToolbar,AnnotationDrawer,CollectionPicker}.svelte`.

**Acceptance**: `[ ]` Select text in article body → "Highlight" button → highlight saves and renders. `[ ]` Add annotation note → persists round-trip. `[ ]` Save article to a new collection → collection appears in `/collections`. `[ ]` Click collection → articles render. `[ ]` Export collection as `.md` → file downloads with article titles and bodies.

## Interfaces and Data Flow

**New backend route**:
- `GET /api/auth/me` — `{ ok: true, data: { user_id, email, name, is_admin } }`. Auth-required (mounted under `protectedApi`). Used by both consumer and (eventually) admin in place of `/admin/me`.

**Modified backend constants**:
- `ALLOWED_HANDOFF_TARGETS` in `nebularnews/src/routes/auth.ts:9-12` — add `https://app.nebularnews.com/sign-in/callback`, `http://localhost:5174/sign-in/callback`.
- `trustedOrigins` in `nebularnews/src/lib/auth.ts:51-56` — add `https://app.nebularnews.com`.

**No iOS code changes.** This phase does not touch `nebularnews-ios`.

**Cookie**: `nn_session` on `app.nebularnews.com`, httpOnly, secure, lax, 30-day max-age. Same name as admin (different host, no collision).

**API proxy route**: `POST /api/proxy/chat/assistant` on `app.nebularnews.com`. Forwards to Workers with bearer attached.

**Streamed events** (consumed by browser, parsed in `lib/sse/stream.ts`):
```
data: {"type":"delta","content":"…"}
data: {"type":"tool_call_propose","proposeId":"…","name":"…","args":{…},"summary":"…","detail":{…},"contextHint":"…"}
data: {"type":"tool_call_server_result","name":"…","summary":"…","succeeded":true,"undoTool":null,"undoArgsB64":null}
data: {"type":"tool_call_client","name":"…","args":{…}}
data: {"type":"done","content":"…","usage":{"prompt_tokens":…,"completion_tokens":…,"total_tokens":…}}
data: {"type":"error","message":"…"}
```

## Edge Cases and Failure Modes

1. **Token expires mid-session** — `/auth/me` returns 401. `hooks.server.ts` clears the cookie and the layout redirects to `/sign-in`. The user-visible behavior is "you got bounced to sign-in"; that's acceptable for v1.
2. **Quarantined article** — `/articles/:id` still returns the article (the quarantine filter only applies to list endpoints). Render normally; user reached it via direct link or a stale brief reference.
3. **Empty article body** — `content_html` and `content_text` both null. Show "Source content unavailable — open at <feed_title>" with the canonical_url link, plus the summary if we have one.
4. **Stale brief image** — backend always populates `image_url` (real or fallback). If the R2 URL ever 404s (pool not seeded), the `<img>` shows broken-image. Add `onerror` handler in `BriefCard.svelte` to swap to a 1×1 transparent placeholder + CSS gradient background.
5. **No briefs yet** — `/brief/history` returns `{ briefs: [] }`. Briefs page shows a "No briefs yet" empty state. Today shows no brief card at all.
6. **No subscriptions** — `/today` returns zeros. Today shows "No articles yet — set up feeds in the iOS app or admin web." For Phase C this is a known sharp edge; web subscribe UI is out of scope.
7. **Chat budget exceeded** (non-BYOK) — backend returns `{ ok: false, error: { code: 'budget_exceeded', reset_at: <ts> } }` with HTTP 429. `streamPost` sees a non-200 response before the SSE stream starts; surface as a chat error bubble: "Daily AI budget exceeded — resets at <local time>."
8. **Chat tool proposal user ignores** — proposal sits in `tool_call_proposals` table forever. No cleanup needed for Phase C; the chat thread stays in "awaiting confirmation" state until the user acts or starts a new thread.
9. **CORS preflight on the proxy route** — proxy is same-origin so no preflight. The server-to-server call from proxy → Workers also has no CORS (server-side fetch).
10. **Cookie not set in Safari ITP / 3rd-party cookie restrictions** — the `nn_session` cookie is first-party on `app.nebularnews.com`, so ITP doesn't apply. The better-auth session cookie on `api.nebularnews.com` is briefly cross-site during the OAuth handshake, but better-auth uses a same-site=lax cookie so the OAuth GET callback carries it. Already proven working with admin web.
11. **Sparkle drawer scroll lock on mobile** — when the bottom sheet is open, lock body scroll (CSS `overflow: hidden` on `body` while open). Restore on close.
12. **Multiple tabs / sessions** — same `nn_session` cookie; both tabs share state. The chat history list refreshes on drawer open, so a thread started in another tab appears.

## Test Plan

Verification commands:

```sh
# Type-check the consumer app (run from /Users/tfinklea/git/nebularnews-app):
pnpm install
pnpm check

# Local dev (port 5174 to avoid colliding with admin's 5173):
pnpm dev -- --port 5174

# Backend changes — type-check:
cd /Users/tfinklea/git/nebularnews && npx tsc --noEmit

# Backend deploy:
cd /Users/tfinklea/git/nebularnews && npx wrangler deploy --env production

# Consumer deploy preview:
cd /Users/tfinklea/git/nebularnews-app && pnpm build && npx wrangler pages deploy .svelte-kit/cloudflare --project-name=nebularnews-app
```

Manual acceptance walkthrough (post-deploy):

- `[ ]` Visit `https://app.nebularnews.com` → redirects to `/sign-in`.
- `[ ]` Click "Continue with Apple" → Apple flow → bounce-back to `/today`.
- `[ ]` Today page renders user's brief, hero article, up-next, stats.
- `[ ]` Click hero → article detail loads with summary and key points.
- `[ ]` Toggle save → reload page → save state persists.
- `[ ]` Open sparkle drawer, ask "what should I read?", get streamed response.
- `[ ]` Navigate to Briefs → list renders → tap a brief → bullets and image load.
- `[ ]` Sign out → cookie cleared → bounce to `/sign-in`.
- `[ ]` Open dev tools network tab during chat → bearer token does NOT appear in any browser request to `api.nebularnews.com` (only the proxy hits it).
- `[ ]` Resize to mobile width → sidebar becomes hamburger, sparkle becomes bottom-sheet FAB.

Residual gaps:
- No automated E2E tests yet; Phase C ships with manual smoke. A Playwright suite is a Phase C+1 candidate.
- Lighthouse/perf budget unmeasured; expect SSR to be fast enough on Pages but no formal target set.

## Handoff

**Recommended tier**: **Sonnet implementer**, sized per sub-phase. The five sub-phases above are roughly equally sized; sequence sub-phase 1 first (it gates the others), then 2, 3, 4, 5 in parallel-friendly order if multiple sessions run.

**Files likely touched**:
- New repo: `/Users/tfinklea/git/nebularnews-app/**` (entire scaffold)
- `nebularnews/src/routes/auth.ts` — extend handoff allowlist + add `/auth/me`
- `nebularnews/src/lib/auth.ts` — extend trustedOrigins
- `nebularnews-ios/.docs/ai/current-state.md` and `.docs/ai/roadmap.md` — once each sub-phase ships, mark Phase C progress and remove the "CORS tightening" line under "Later — Phase C candidates" since CORS was already tightened pre-Phase C

**Constraints for the implementer**:
- Do not change iOS code.
- Do not introduce new auth providers; reuse `com.nebularnews.web` Services ID.
- Do not expose the bearer token to browser JS; the proxy pattern is non-negotiable.
- Match admin web's TypeScript/Svelte conventions (Svelte 5 runes, `$lib` aliases, type-only imports where possible).
- Keep dependencies thin: `marked`, `dompurify` (or `isomorphic-dompurify`), `lucide-svelte` for icons. No UI kit beyond Tailwind.
- Use `pnpm` (matches admin) — repo `package.json` should ship a `pnpm-lock.yaml`.

## Verification Commands (canonical, repeated for spec-implementer)

```sh
pnpm --dir /Users/tfinklea/git/nebularnews-app install
pnpm --dir /Users/tfinklea/git/nebularnews-app check
pnpm --dir /Users/tfinklea/git/nebularnews-app build
npx tsc -p /Users/tfinklea/git/nebularnews/tsconfig.json --noEmit
```

Backend deploy (Wrangler is pre-authorized per memory):

```sh
npx wrangler deploy --env production --cwd /Users/tfinklea/git/nebularnews
```

Consumer deploy preview:

```sh
npx wrangler pages deploy /Users/tfinklea/git/nebularnews-app/.svelte-kit/cloudflare --project-name=nebularnews-app
```

Manual: CF Dashboard → Pages → `nebularnews-app` → Custom Domain → add `app.nebularnews.com` → DNS CNAME (auto-suggested by CF). Apple Developer Portal → Services ID `com.nebularnews.web` → Add `https://app.nebularnews.com` to Website URLs (no Return URL change needed; OAuth still lands on `api.nebularnews.com`).

---

**Remaining decisions for the user before implementer kicks off**:
1. Confirm new repo `/Users/tfinklea/git/nebularnews-app` (vs subdirectory). I lean new repo and recommend it; user said they lean the same way.
2. Confirm reuse of `com.nebularnews.web` Services ID (vs minting `com.nebularnews.app`). I recommend reuse — the multi-aud array already supports it and it avoids a second `.p8`-signed JWT.
3. Confirm SSR-first data fetching. (Recommended.)
4. Confirm scope cuts — BYOK UI, feed management, highlights, push notifications all deferred. (Recommended.)

If the user agrees on all four, this spec is decision-complete and ready for `spec-implementer`.

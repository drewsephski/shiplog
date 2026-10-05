# Shiplog agent

Next.js App Router / TypeScript, Neon PostgreSQL, a GitHub App, and OpenRouter structured generation. The native app is the journal reader/editor; this service owns credentials, evidence ingestion, synthesis, and scheduled work.

## Configure

1. Create a GitHub **App**. Grant repository **Contents: read**, **Pull requests: read**, **Issues: read**, and implicit **Metadata: read**. No write or organization permissions are needed. Subscribe to `push`, `pull_request`, and `issues`. GitHub delivers installation, repository-access, and authorization lifecycle events automatically; do not put them in a manifest's `default_events`. Enable expiring user tokens.
2. Set the user authorization callback to `https://YOUR-AGENT/connect/callback` and the installation setup URL to `https://YOUR-AGENT/connect/install`. Disable automatic user authorization during installation: Shiplog authenticates the user before opening installation selection. Set the webhook URL to `https://YOUR-AGENT/api/github/webhook` with a strong webhook secret.
3. Create a Neon PostgreSQL database for this service. Copy `.env.example` to `.env.local` and fill the values locally. `SHIPLOG_PUBLIC_URL` must be the deployed HTTPS origin, with no path. The private key accepts GitHub's RSA PEM format or PKCS8, including escaped newlines. Generate `TOKEN_ENCRYPTION_KEY` with 32 random bytes encoded as base64; preserve it across deploys to keep stored refresh tokens readable. Generate independent strong webhook and cron secrets.
4. Explicitly select an OpenRouter model supporting strict JSON Schema outputs. Provider routing requires parameter support and denies providers collecting prompt data. No provider is silently selected by the application. Read the chosen provider's retention terms before using private repositories.
5. Install and migrate:

```sh
pnpm install --frozen-lockfile
pnpm exec tsx --env-file=.env.local scripts/migrate.ts
pnpm check
pnpm build
pnpm dev
```

6. Deploy with Vercel's project root set to `backend`. Add the same values as server environment variables. The current Hobby deployment uses `.github/workflows/agent-jobs.yml` to call the authenticated jobs route every five minutes. Configure repository variable `SHIPLOG_AGENT_URL` and secret `SHIPLOG_CRON_SECRET` (the server's `CRON_SECRET`). GitHub Actions schedules can be delayed and are automatically disabled after 60 days of inactivity in a public repository; monitor workflow health and queue age. A paid Vercel plan can instead use a Vercel cron; disable the external workflow when switching schedulers. Monitor `jobs.error_code` and failed webhook deliveries. Do not rely solely on `after()` callbacks. Durable retries and backfill require a healthy scheduler.
7. Set the native `SHIPLOG_AGENT_URL` build setting to the deployed HTTPS origin. `project.yml` maps it to the app's `ShiplogAgentURL` Info.plist key. It is public configuration, not a credential. The `shiplog` callback scheme is registered in `config/Info.plist`. For the archive script, pass `SHIPLOG_AGENT_URL=https://YOUR-AGENT SHIPLOG_BUILD_NUMBER=<next-number> ./scripts/archive.sh` from the repository root. Verify on a physical iPhone before the next TestFlight release.

The production origin is `https://shiplog.fun`, on Vercel project `shiplog-agent` in `drews-projects-870e934b`, with root directory `backend`. The public GitHub App is [Shiplog Journal](https://github.com/apps/shiplog-journal), owned by `drewsephski`, app ID `5201267`. The native build's default public URL matches this origin. Production writing uses the explicitly configured `openai/gpt-4.1` model. Build 2 retains `https://shiplog-agent.vercel.app`; keep that alias active without API redirects. Its initial sign-in hop stays on the pinned alias, and the authentication browser hands off to the canonical domain before setting its secure flow cookie. Credentials belong only in the ignored `backend/.env.local` and production server environment; `.vercelignore` excludes local environment files and native build artifacts from CLI uploads.

For a new account setup, run `python3 scripts/setup-credentials.py` from the repository root. Its loopback-only helper creates a GitHub App through GitHub's manifest flow and a dedicated OpenRouter key through PKCE, saving credentials directly to `.env.local` with mode `0600`. It preserves existing keys, verifies callback state, and expires after one hour. Stop it after setup. `node scripts/publish-agent-env.mjs` uploads the allowlisted service variables to this Vercel project through stdin without printing their values. It refuses incomplete configuration unless explicitly passed `--partial`. Keep the token encryption key safe across deployments; replacing it makes stored tokens unreadable.

## Connection and ownership

The phone generates a verifier and sends only its SHA256 challenge to `/api/connect/start`. An expiring server flow uses GitHub App user authorization, an HttpOnly secure cookie, OAuth state, and CSRF protection. Repository choices are revalidated with the **user access token**, proving the intersection of installation access and this user's access. Installation IDs from callbacks are ignored. Only the selected repositories are enabled, and AI transfer requires consent; bounded patches have a separate unchecked opt-in.

The callback contains a short-lived one-time exchange code, never a bearer or GitHub token. `/api/connect/exchange` atomically consumes it with the phone's verifier. The native bearer is stored in a device-only Keychain item; only its hash is stored on the server. GitHub user/refresh tokens are encrypted at rest. Repository-scoped installation tokens are minted on the server with read permissions. Every import and push hydration revalidates current user access.

## Agent behavior

- HMAC verification precedes webhook parsing. Unselected repository deliveries are discarded. Issue/PR actions are normalized immediately, with exact actor IDs; commits require GitHub API hydration because push author names/emails cannot establish identity. Duplicate delivery IDs and evidence IDs are idempotent.
- Commit evidence includes verified author/committer IDs across up to 20 branches. Issue/PR opening is attributed to the author; merge/close/reopen timeline events use the actual actor. Timeline comments or generic `updated_at` changes are not treated as proof of work. Unlinked commit identities are excluded rather than inferred from names.
- Context caches last 24 hours: description, languages, top-level filenames, and bounded README/manifest/architecture excerpts. Input includes up to 200 attributed events. Each AI input has a 24,000-character document budget, a 12,000-character optional patch budget, and a 200,000-character total limit. Sensitive file patterns and lockfiles are excluded from patches. These are minimization boundaries, not a secret detector; repository prose can still contain sensitive content.
- `JournalSynthesisService` is separate from a summary of manually authored entries. Strict output validation rejects unknown/cross-repository sources, duplicate assignments, invalid confidence, unsupported narrative provenance, and reuse of protected evidence. The prompt treats repository text as untrusted data and forbids unsupported deployment, test, impact, or completion claims. Exact citations establish provenance; factual interpretation still needs real-user evaluation. Confidence is a model estimate, not a calibrated accuracy score.
- Runs are scoped to user + civil day + time zone + canonical evidence/context hash + prompt version. Related events become coherent blog sections with full paragraphs and an opening daily story. Required canonical evidence-assignment keys cover every unprotected event exactly once; missing sources fail validation. An invalid provider response receives one bounded revision before publication is refused. The internal structured format is normalized to the existing public journal contract. Evidence overlap reconciles IDs. Edited/deleted entries reserve or suppress their evidence; regeneration preserves their text. Narrative edits/deletion are protected separately.
- Atomic leases fence expired workers. Interrupted jobs retry through cron; up to five attempts are made before surfacing failure. Access revocation disables import and cannot publish a new draft. Reconciliation runs at least every six hours when the scheduler is healthy, backfilling up to seven civil days from the last checkpoint after interruptions, and finalization is due at the selected local evening time. Exact completion time is not guaranteed under provider delays or queue backlog.
- The native reader presents the same full daily article in Today and History, with sources and editing available per section. Automatic checks are quiet: pending jobs poll every 30 seconds, loaded days check at most every five minutes, and civil-day/time-zone changes refresh immediately. Explicit analysis and pull-to-refresh remain available.
- `/api/journals` pages server-written history with a watermark and five-minute overlap so reopening the phone retrieves days generated while it was closed. Returned evidence omits code patches and full bodies. Offline native edits use an idempotent persistent outbox.
- Disconnect stops jobs, disables repositories, invalidates bearer sessions, and removes stored GitHub credentials while retaining server history. Account deletion cascades user-owned remote data. Local journal copies remain. Delivery records contain only selected repository/installation IDs and commit SHAs; processed payloads are cleared, and operational delivery records expire after seven days. A disconnected user can reconnect to delete retained history. The GitHub App installation must be managed/uninstalled in GitHub separately.

The first release is intentionally bounded. Exhausted pagination (20 pages), branch, event, or context limits fail explicitly rather than publishing a partial-success journal. Reviews, releases, deployments, notifications/APNs, billing, and other integrations are outside this vertical.

## Verify

`pnpm check` runs lint, strict TypeScript, and pure-domain/security tests. PostgreSQL integration tests are skipped unless `TEST_DATABASE_URL` is supplied. **Use an isolated throwaway database**: the tests truncate its agent tables. The harness transports the production Neon SQL to real PostgreSQL; it does not mock SQL. GitHub and model calls remain controlled fixtures in these tests.

```sh
TEST_DATABASE_URL=postgresql://USER@127.0.0.1:55432/shiplog_test pnpm check
```

Before claiming the live vertical works, verify real GitHub authorization and repository selection, private-repository consent, an attributed commit/PR, a coherent generated day, edits followed by regeneration, webhook replay, revoked user/repository access, phone-closed scheduled generation, history recovery, and disconnect/deletion. Measure the first-day latency and factual accuracy; the 10–30 second product target is not proven by mocked providers or a successful build.

References: [GitHub App user authorization](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app), [installation repository access](https://docs.github.com/en/rest/apps/installations), [commit permissions](https://docs.github.com/en/rest/commits/commits), [OpenRouter structured output](https://openrouter.ai/docs/guides/features/structured-outputs), [Vercel cron execution](https://vercel.com/docs/cron-jobs/manage-cron-jobs).

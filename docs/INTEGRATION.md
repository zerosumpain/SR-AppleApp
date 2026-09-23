# Strange Ramblings integration boundary

The existing SR-Health ingest route and dashboard were inspected before building this pilot. That service uses an owner/public model and a shared Apple ingest API key. Reusing those paths or forwarding family health records into its legacy tables would not preserve per-person privacy.

SR-AppleApp therefore owns new paths and a separate database:

- `/apple-app/` — private dashboard shell; record APIs require its session.
- `/api/apple/*` — explicit browser or device authentication.
- `/healthz` — liveness only; keep internal.

The local LAN gateway routes these new paths to `apple-app:5295`. It does not inject an owner identity. Existing `/health` pages are untouched. The private HTTPS pilot now routes the companion paths separately; see PILOT-OPERATIONS.md. Do not forward incoming headers as a trusted user identity.

For production/staging routing, proxy only `/apple-app`, `/apple-app/*` and `/api/apple/*` to the loopback-bound service, preserve method/body/cookies, and preserve the canonical HTTPS origin used in `APP_ORIGIN`. No gateway authentication exemption should be added to legacy health routes. This service still authenticates all data endpoints itself. Check browser Origin handling after proxying; untrusted proxy headers do not determine identity.

Provision users into the isolated service with:

```sh
# Supply NEW_USER_PASSWORD securely through the operator's environment.
# The command requires at least 14 characters. Never commit account exports.
node server/admin.mjs create-user person@example.com 'Display name' family-id
```

Run inside the service container or with `DATABASE_PATH` pointing to the intended database. Reusing a family-id is an explicit membership assignment, not a value clients can set through the API. New users start with location sharing off. A family administrator does not acquire health access. The pilot does not expose account provisioning, password reset or membership changes as public endpoints.

Do not seed demo accounts in an environment containing real data. Use trusted TLS and secure the persistent volume/backups. No public telemetry or third-party analytics is included. This is a single-process family pilot, not a multi-instance service.

## The one read /health makes (2026-09-23)

`GET /api/apple/journeys?from=&to=` (epoch seconds, at most the retention window) lets SR-Health put the owner's journeys in `/health/activities` beside the workouts. It is the only thing the service lane opens:

- `Authorization: Bearer $APPLE_SERVICE_TOKEN`, compared as a digest. Any other path given that token answers exactly as a stale device token would.
- The person is `APPLE_SERVICE_OWNER` (an email already in `users`), fixed by configuration. There is no user parameter, so no other family member's movement can be asked for.
- Read-through: /health keeps no copy. Retention and `DELETE /api/apple/data` therefore reach /health on its next read.
- Unset token or owner = 404.

It returns journeys exactly as `activitiesOf` finds them, each with its fixes and the heart-rate readings inside it, plus the phone's own workout records for the window. Deciding what counts as an activity (on foot, long enough, not already a workout) is SR-Health's job, in `src/lib/trails/companion.ts`.

In production SR-Health's web container runs with host networking and reaches this server on `http://127.0.0.1:5295`, so the token never leaves the machine.

## Later integration work

- Exchange the site's authenticated session for a short-lived, audience-bound identity with stable per-person IDs; retain API ownership checks.
- Build invitation/account-recovery flows before wider family rollout.
- Add per-person adapters to existing health analytics only after those analytics and queries are owner-scoped. Do not map all users to the existing site's owner.
- Add retention jobs independent of ingestion, backup/restore checks, and operational alerting before a durable rollout.

None of those steps is silently simulated by the current preview. The new dashboard already consumes the real new API and persisted database; its example records are synthetic.

# Strange Ramblings integration boundary

The existing SR-Health ingest route and dashboard were inspected before building this pilot. That service uses an owner/public model and a shared Apple ingest API key. Reusing those paths or forwarding family health records into its legacy tables would not preserve per-person privacy.

SR-AppleApp therefore owns new paths and a separate database:

- `/apple-app`, `/apple-app/*` — the retired dashboard; 308 to `${APPLE_PUBLIC_ORIGIN}/welcome` (2026-09-26). Nothing else is served outside the API.
- `/api/apple/*` — explicit browser or device authentication.
- `/healthz` — liveness only; keep internal.

The local LAN gateway routes these new paths to `apple-app:5295`. It does not inject an owner identity. Existing `/health` pages are untouched. The private HTTPS pilot now routes the companion paths separately; see PILOT-OPERATIONS.md. Do not forward incoming headers as a trusted user identity.

For production/staging routing, proxy only `/api/apple/*` to the loopback-bound service (and `/apple-app`, `/apple-app/*` while old bookmarks still arrive — they only redirect), preserve method/body/cookies, and preserve the canonical HTTPS origin used in `APP_ORIGIN`. No gateway authentication exemption should be added to legacy health routes. This service still authenticates all data endpoints itself. Check browser Origin handling after proxying; untrusted proxy headers do not determine identity.

Provision users into the isolated service with:

```sh
# Supply NEW_USER_PASSWORD securely through the operator's environment.
# The command requires at least 14 characters. Never commit account exports.
node server/admin.mjs create-user person@example.com 'Display name' family-id
```

Run inside the service container or with `DATABASE_PATH` pointing to the intended database. Reusing a family-id is an explicit membership assignment, not a value clients can set through the API. New users start with location sharing off. A family administrator does not acquire health access. The pilot does not expose account provisioning, password reset or membership changes as public endpoints; SR-Main adds people to the owner's family over the token-gated household lane (see "Onboarding over the household lane").

Do not seed demo accounts in an environment containing real data. Use trusted TLS and secure the persistent volume/backups. No public telemetry or third-party analytics is included. This is a single-process family pilot, not a multi-instance service.

## The two reads /health makes (2026-09-23)

`GET /api/apple/journeys?from=&to=` (epoch seconds, at most the retention window) lets SR-Health put the owner's journeys in `/health/activities` beside the workouts. It is the first of two things the service lane opens; see "Second read — the health export" below for the other.

- `Authorization: Bearer $APPLE_SERVICE_TOKEN`, compared as a digest. Any other path given that token answers exactly as a stale device token would.
- The person is `APPLE_SERVICE_OWNER` (an email already in `users`), fixed by configuration. There is no user parameter, so no other family member's movement can be asked for.
- Read-through: /health keeps no copy. Retention and `DELETE /api/apple/data` therefore reach /health on its next read.
- Unset token or owner = 404.

It returns journeys exactly as `activitiesOf` finds them, each with its fixes and the heart-rate readings inside it, plus the phone's own workout records for the window. Deciding what counts as an activity (on foot, long enough, not already a workout) is SR-Health's job, in `src/lib/trails/companion.ts`.

In production SR-Health's web container runs with host networking and reaches this server on `http://127.0.0.1:5295`, so the service token never leaves the machine — it is used only for these loopback reads. The doorbell below is a separate, deliberately weaker secret that does leave the machine.

## Second read — the health export (a COPY)

`GET /api/apple/export?after=<epoch ms>&limit=<≤5000>` — same token, same fixed owner,
same 404-when-unconfigured rule as journeys. Returns `{ after, next, more, earliest,
earliestByKind, records, workouts, tombstones }` (`earliest` = the owner's oldest record
here; `earliestByKind` gives the same minimum per kind, so a rebase can use each metric's
own history start rather than one borrowed from another kind); pass `next` back as `after`. An upload is never split across
pages. A workout arrives whole (`{ workout, route, series }`) whenever any part of it
changed. Deletions arrive as `tombstones` (`{ id, kind, start, deleted }`); a metric deletion is omitted while another sample still holds the same kind and start.

Unlike journeys, /health KEEPS what it reads here: the owner's health history, the
same data Health Auto Export used to post. So `DELETE /api/apple/data` clears this
server but not /health's copy; tombstones for individual HealthKit deletions do reach
it. Location never leaves through this endpoint.

After each upload by the owner, this server POSTs `APPLE_DOORBELL_URL` (empty body,
`Authorization: Bearer $APPLE_DOORBELL_TOKEN`) so /health pulls at once. This is its
own ring-only token, not `APPLE_SERVICE_TOKEN` — it can only trigger a pull and
grants no read access, so it is safe to leave the host even though the service
token above never does. Unset token or URL = no ring, as before.

## Onboarding over the household lane (2026-09-26)

SR-Main's `/welcome` and `/admin/access/devices` replace the retired dashboard's Connect & privacy tab. They call these routes server-to-server with `Authorization: Bearer $APPLE_HOUSEHOLD_TOKEN` (404 when unset, 401 on any other token). Every route works inside the family of `APPLE_SERVICE_OWNER` and nowhere else; emails are lower-cased.

| Route | Body | Answer |
| --- | --- | --- |
| `POST /api/apple/household/users` | `{email, name}` | 201 `{id, email, name, created:true}` for a new person (sharing off), 200 `{..., created:false}` for an existing member (name updated, sharing untouched). 409 if the email belongs to ANOTHER family (never moved) or no owner is configured. |
| `POST /api/apple/household/pair-code` | `{email}` | 200 `{code, payload, expiresIn:600}`; replaces that person's previous code. `payload` is the exact QR string, `{"type":"sr-companion-pair","version":1,"server":"<APPLE_PUBLIC_ORIGIN>","code":"..."}`. 404 for anyone not in the family. |
| `GET /api/apple/household/devices` | — | 200 `{devices:[{id, email, name, label, created, expires, lastUsed}]}`: every live paired phone in the family. `id` is the credential hash; times are ISO; `created` is derived (`expires` − 90 days); `lastUsed` is always `null` (not tracked). |
| `DELETE /api/apple/household/devices/:id` | — | 204, or 404 when the id is not a live phone in the family. |
| `PUT /api/apple/household/sharing` | `{email, enabled}` | 200 `{sharing}`; 404 for anyone not in the family. |
| `POST /api/apple/household/data/delete` | `{email}` | 200 `{deleted:{health, tombstones, locations, alerts, credentials}}` (row counts). Exactly what that person's own `DELETE /api/apple/data` does, through the same `deleteUserData` in `server/store.mjs`: uploaded health, its tombstones, location history, queued alerts, paired phones and any live pair code are removed and sharing is switched off. The account row (family membership) stays. /health's COPY of the owner's health export is not reached (see above). 404 for anyone not in the family. |
| `GET /api/apple/household/day?email=&from=&to=&tz=` | — | 200, one person's day for SR-Main's `/home/people` "Your day" — see below. 400 on a window over 48 h; 404 for anyone not in the family. |

The origin in the QR is `APPLE_PUBLIC_ORIGIN` (default `https://strangeramblings.com`), not `APP_ORIGIN`: SR-Main asks over loopback, and a QR must name somewhere a phone on mobile data can reach. `node server/admin.mjs create-user` still works for anything outside this flow.

### `GET /api/apple/household/day`

The retired dashboard's Movement tab drew a day from two calls, `/api/apple/track?offset=&date=` and `/api/apple/timeline?from=&to=`. This returns both for one family member in one response, built by the same functions (`trackWindow`, `timelineWindow` in `server/app.mjs`), so a port of the dashboard's `movement.js` sets `state.day = body.track` and `state.timeline = body.timeline` and changes nothing else.

Query (all required except `tz`; nothing else accepted):

- `email` — a member of the owner's family. SR-Main passes the SIGNED-IN person's own email; this server cannot tell who is looking, so that rule is SR-Main's to keep.
- `from`, `to` — ISO timestamps; `to − from` must be > 0 and ≤ 48 h. Seconds are floored/ceiled to whole epoch seconds. For a local calendar day use local midnight to the next local midnight.
- `tz` — minutes, JavaScript `getTimezoneOffset()` convention (positive west of UTC, so BST is `-60`), integer, |tz| ≤ 840, default 0. Echoed back for the caller's day bucketing; the window is already absolute.

```jsonc
{
  "email": "alex@example.test",
  "tz": -60,
  "track": {                       // == /api/apple/track?date= minus the day index
    "from": 1790290800,            // epoch seconds, the window as asked
    "to": 1790377200,
    "points": [                    // [lon, lat, epochSeconds, accuracyM, moving 0|1, speedMps], oldest first
      [-1.5, 51.5, 1790337600, 5, 1, 1.4],
      [-1.4995, 51.5, 1790337630, 5, 1, 1.4]
    ],
    "segments": [[0, 1]],          // [firstIndex, lastIndex] into points; a >600 s gap starts a new one (draw dashed between)
    "activities": [                // journeys and the stops between them (activitiesOf)
      { "kind": "journey", "first": 0, "last": 1, "from": 1790337600, "to": 1790337630, "seconds": 30, "metres": 35, "fixes": 2 }
    ],
    "totals": { "fixes": 2, "metres": 35, "movingSeconds": 30, "journeys": 1 },
    "gapSeconds": 600,
    "truncated": false             // true only past 20,000 fixes; the oldest are kept
  },
  "timeline": {                    // == /api/apple/timeline?from=&to=&bins=ceil(window/300)
    "from": 1790290800,
    "to": 1790377200,
    "heartRate": { "seconds": 300, "bins": [[1790337600, 70]] },   // [bucketStart, mean bpm]; empty buckets omitted
    "restingHeartRate": { "value": 54, "at": "2026-09-24T00:00:00.000Z" },  // or null
    "steps": [ { "value": 8241, "start": "…", "end": "…", "source": "HealthKit daily statistics" } ],  // RECORDS, never summed
    "workouts": [ { "activity": "Walking", "start": "…", "end": "…", "seconds": 1800, "distance": 2100, "energy": null, "source": "Watch" } ],
    "sleep": [ { "stage": "deep", "start": "…", "end": "…", "source": "Watch" } ],  // every stage record overlapping the window
    "asleepSeconds": 3600          // asleep/core/deep/rem, unioned across sources and clipped to the window
  }
}
```

Spans (steps, workouts, sleep) are selected by OVERLAP with the window, so a night that began the evening before is included; heart rate by start. The `activities` entries carry whatever `activitiesOf` in `server/movement.mjs` returns (a stop is `{kind:"stop", first, last, from, to, seconds, fixes, lng, lat}`, pinned at the median fix); `/api/apple/timeline` now also returns `asleepSeconds`.

## Later integration work

- Exchange the site's authenticated session for a short-lived, audience-bound identity with stable per-person IDs; retain API ownership checks.
- Build invitation/account-recovery flows before wider family rollout.
- Add per-person adapters to existing health analytics only after those analytics and queries are owner-scoped. Do not map all users to the existing site's owner.
- Add retention jobs independent of ingestion, backup/restore checks, and operational alerting before a durable rollout.

None of those steps is silently simulated by the current preview; its example records are synthetic.

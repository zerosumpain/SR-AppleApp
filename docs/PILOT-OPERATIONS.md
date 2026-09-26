# Private iPhone pilot

Activated 21 September 2026 after the TestFlight 0.1.0 (2) upload.

- Browser dashboard: **retired 2026-09-26.** https://strangeramblings.com/apple-app/ now 308s to https://strangeramblings.com/welcome; its views live on the main site (see below).
- Native server origin: https://strangeramblings.com (no path suffix).
- The browser API lane uses the **main website login** (Google). There is no separate companion password.
- Generate a one-time, ten-minute pairing QR code at strangeramblings.com/welcome (or Admin → Access → Devices); manual copy remains available.
- Location sharing starts off; each person opts in. Health endpoints stay owner-scoped.

## Deployment

The HTTPS host runs this as a **separate Compose project** deployed from a
per-release directory, with its own env file and its own named volume. The
service binds to **loopback only**; the existing Cloudflare tunnel routes just
the companion's own paths to it. No shared database, demo account, main-site
identity injection or Docker socket is mounted.

Exact paths, the env-file name, the volume name and the tunnel rule are **not
published here** — this repository is public. They are discoverable on the host
itself (`docker inspect` on the running container names its mounts and its
compose working directory) and recorded in the private ops notes.

The deployment uses the pinned Node image in Dockerfile. The matching local synthetic service and its existing volume remain separate and available at the local preview endpoint.

## Checks performed

Nine API tests passed before activation. Public HTTPS checks verified dashboard delivery, authenticated sign-in, Secure/HttpOnly/SameSite cookies, CSRF rejection, single-use pairing, an empty device sync, device revocation, and logout. Verification wrote no health or location records. Actual iPhone HealthKit and background-location behavior still require device testing; see DEVICE-TESTING.md.

## Operations and rollback

Use the deployment Compose file together with its env file for status, logs or
restart. **Preserve the named data volume, and never `down -v`** to update the
service — that deletes it.

A timestamped copy of the pre-change tunnel configuration is kept in the
deployment's backups directory on the host. To roll back, remove **only** the
companion's ingress entry from the current configuration, validate it with
`cloudflared … tunnel ingress validate`, then **restart** cloudflared — a SIGHUP
stops it and takes every hostname down with it.

Do not restore an old whole-file backup over later routing changes: the tunnel
config is shared with every other service on the host and it has moved on. Stop
the companion service separately, and retain its volume.

For account provisioning, see INTEGRATION.md. Keep credentials outside Git and logs.

Main-site sign-in replaced the pilot's own login on 2026-09-22: the browser lane
now verifies the site's Auth.js session with `AUTH_SECRET` (copied into the
deployment's env file from the main site's environment, never written back to
it), and `users.password` is dropped on open. There is no password to reset. A person needs both a strangeramblings.com login and a row in `users`. The pilot still has no automated database backup job.

QR update: that release preserved the existing volume and routes. Ten API tests pass, including decoding the generated QR pixels and checking replacement/replay rejection. Desktop/mobile rendered QR and expiry checks pass. The live HTTPS QR decoded to the canonical origin and successfully paired a temporary verification device, which was then revoked. Physical camera scanning still requires the updated TestFlight build on an iPhone.

TestFlight 0.1.0 (3), from the same release, uploaded successfully on 21 September 2026. Native unit/UI checks passed with the simulator set to dark appearance, including QR payload validation, manual-code visibility, and camera-unavailable fallback. The physical-camera acceptance check remains for the device tester.

## Dashboard retired (26 September 2026)

The `/apple-app/` dashboard is gone. Its four tabs moved to the main site: health to `/health`, family to `/home/people`, movement to the person's own `/home/people` page (reading `GET /api/apple/household/day`), and Connect & privacy to `/welcome` + `/admin/access/devices` (pairing, devices, sharing, delete my data via `POST /api/apple/household/data/delete`). This server now serves JSON only: `/apple-app`, `/apple-app/*` and `/` 308 to `${APPLE_PUBLIC_ORIGIN}/welcome`, and the CSP is `default-src 'none'`. The history below describes the dashboard as it was.

## Movement map (22 September 2026)

The dashboard gained a **Movement** tab: the signed-in person's own recorded
track on a Mapbox basemap, with that day's heart rate, workouts, sleep and step
total on a timeline beneath it. Two new read endpoints, `/api/apple/track` and
`/api/apple/timeline`, both owner-scoped on either lane — there is no family
history and no parameter that could ask for one.

Nothing new to provision. The basemap uses the main site's existing public
Mapbox token, fetched by the browser from `/api/maps/config` on the same origin;
this container holds no Mapbox credential and the tunnel already routes
`/api/maps` to the main site. The only header change is
`img-src https://api.mapbox.com` in the CSP.

**If the map is blank but the track draws, check the referrer before anything
else.** The token is URL-restricted and this server sends
`Referrer-Policy: no-referrer`; a tile that inherits that is refused with a 403
and logs nothing visible. Each tile carries its own
`referrerpolicy="strict-origin-when-cross-origin"` to override it. If the token
endpoint is unreachable the track still draws, on a plain ground, and the frame
says "No map imagery".

Thirty-one API tests pass, including that a family member cannot read another
member's track, that pausing sharing does not hide your own history from you,
and that a recording gap becomes a second segment rather than a line drawn
through it. The Playwright check covers the tab on desktop and phone: trace,
dashed gap, timeline scrub placing and refusing to place the map's dot, pan and
zoom. Deployment is unchanged — the same per-release Compose file and env file,
the volume preserved, never `down -v`.

A pre-existing preview bug was fixed in the same change: signing out of the
local preview handed the browser the main site's `/auth/signout`, which the
preview does not serve, so a successful sign-out landed on a 404. The preview's
session is this server's own cookie and is already ended by clearing it.

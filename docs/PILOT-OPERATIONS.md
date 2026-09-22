# Private iPhone pilot

Activated 21 September 2026 after the TestFlight 0.1.0 (2) upload.

- Browser dashboard: https://strangeramblings.com/apple-app/
- Native server origin: https://strangeramblings.com (no path suffix).
- The browser dashboard uses the **main website login** (Google). There is no separate companion password.
- Generate a one-time, ten-minute pairing QR code in Connect & privacy; manual copy remains available.
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

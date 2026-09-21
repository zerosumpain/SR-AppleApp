# Private iPhone pilot

Activated 21 September 2026 after the TestFlight 0.1.0 (2) upload.

- Browser dashboard: https://strangeramblings.com/apple-app/
- Native server origin: https://strangeramblings.com (no path suffix).
- Browser account credentials are separate from the main website login.
- Generate a one-time, ten-minute pairing code in Connect & privacy.
- Location sharing starts off; each person opts in. Health endpoints stay owner-scoped.

## Deployment

The HTTPS host runs a separate Compose project, `sr-appleapp`, from `/opt/sr-appleapp/releases/c61899c33432/deploy/compose.yaml`. Environment configuration is `/opt/sr-appleapp/pilot.env`. The database uses the dedicated `sr-appleapp_apple_data` volume. The service binds only `127.0.0.1:5295`; the existing Cloudflare tunnel routes only `/apple-app`, `/apple-app/*`, and `/api/apple/*` on the canonical hostname to it. No shared database, demo accounts, main-site identity injection, or Docker socket is mounted.

The deployment uses the pinned Node image in Dockerfile. The matching local synthetic service and its existing volume remain separate and available at the local preview endpoint.

## Checks performed

Nine API tests passed before activation. Public HTTPS checks verified dashboard delivery, authenticated sign-in, Secure/HttpOnly/SameSite cookies, CSRF rejection, single-use pairing, an empty device sync, device revocation, and logout. Verification wrote no health or location records. Actual iPhone HealthKit and background-location behavior still require device testing; see DEVICE-TESTING.md.

## Operations and rollback

Use the deployment Compose file with `--env-file /opt/sr-appleapp/pilot.env` for status, logs, or restart. Preserve the named data volume. Never run `down -v` to update the service.

The pre-change tunnel configuration is backed up at `/opt/sr-appleapp/backups/cloudflared-20260921T191736Z.yml`. For rollback, remove only the companion ingress entry from the current configuration, validate with `cloudflared --config /etc/cloudflared/config.yml tunnel ingress validate`, then restart cloudflared. Do not restore an old whole-file backup over later routing changes. Stop the companion service separately; retain its volume.

For account provisioning, see INTEGRATION.md. Keep credentials outside Git and logs. This pilot has no main-site SSO, self-service password reset, or automated database backup job yet.

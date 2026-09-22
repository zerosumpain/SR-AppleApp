import { getToken } from '@auth/core/jwt';

/**
 * Who is signed in to strangeramblings.com.
 *
 * The companion used to keep its own email-and-password login, its own
 * `sr_apple` cookie and its own scrypt hashes. It does not any more: the site
 * already has an identity — Google via Auth.js — and a second one meant a second
 * password to set, lose and reset, on a login reachable from the whole internet.
 *
 * ## Why this reads the cookie directly, rather than sitting behind the kit's gateway
 *
 * Every EXTRACTED application (Policy, Drive, Health, JKAI) sits behind the
 * ~60-line gateway in `~/sr-infra/gateway/`, which validates this same cookie at
 * the edge and re-issues a 30-second HMAC assertion. That design exists because
 * those apps are a separate trust domain reached through a proxy: the gateway's
 * job is to STRIP every client-supplied identity header before the app sees one,
 * so the app can trust a header at all.
 *
 * There is no header to strip here. Identity comes from an encrypted JWE that
 * cannot be forged without `AUTH_SECRET`, so the cryptography does the work the
 * assertion would have done. Both designs need `AUTH_SECRET` in this container
 * either way, so the gateway would have bought process separation and nothing
 * else — at the cost of a second port, a second image, a release lane of its
 * own, and an ingress change. The companion is also not in
 * `registry/apps.json`: it is a single-container pilot with no release slots,
 * and the kit's blue/green machinery has nothing to act on.
 *
 * `sessionIdentity` itself is taken UNCHANGED from `sr-infra/gateway/session.mjs`
 * so the two cannot drift on the part that matters.
 *
 * @returns the lower-cased email, or null.
 */
export async function sessionIdentity(cookie, secret) {
  if (!secret) throw new Error('AUTH_SECRET is required');
  const token = await getToken({
    req: { headers: new Headers({ cookie: cookie ?? '' }) },
    secret,
    // Main issues `__Secure-authjs.session-token` on HTTPS. Reading the
    // unprefixed name instead finds nothing and reads as "not signed in".
    secureCookie: true
  });
  if (!token || typeof token.email !== 'string' || !token.email.trim()) return null;
  return token.email.trim().toLowerCase();
}

/**
 * The local-preview identity, which production cannot have.
 *
 * Signing in needs Main's cookie, and a laptop running this server on loopback
 * has no Main to get one from. So the preview names a user in a cookie instead.
 *
 * Two independent conditions, because one is a config flag and a config flag can
 * be set by mistake:
 *
 *   1. `DEMO_MODE=1` — deliberately absent from `deploy/compose.yaml`, and
 *      verified absent from the running production container.
 *   2. The origin is NOT https — production's `APP_ORIGIN` is
 *      `https://strangeramblings.com`, so even if the flag leaked into the
 *      environment this lane still cannot open there.
 *
 * Neither alone is enough to reach it.
 */
export function demoIdentity(cookie, { demo, secure }) {
  if (!demo || secure) return null;
  const match = cookie?.match(/(?:^|; )sr_apple_demo=([^;]+)/);
  if (!match) return null;
  try {
    const email = decodeURIComponent(match[1]).trim().toLowerCase();
    return email && email.length <= 320 ? email : null;
  } catch {
    return null;
  }
}

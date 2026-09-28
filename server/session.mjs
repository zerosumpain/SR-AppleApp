import { getToken } from '@auth/core/jwt';

/** Browser sessions use Main's audience-bound authority in production.
 * Direct decoding remains only for isolated legacy-format tests.
 */
export async function sessionIdentity(cookie, secret) {
  if (process.env.SESSION_INTROSPECTION_URL || process.env.SESSION_INTROSPECTION_TOKEN) return (await sessionContext(cookie)).email;
  if (!secret) throw new Error('AUTH_SECRET is required');
  const token = await getToken({
    req: { headers: new Headers({ cookie: cookie ?? '' }) },
    secret,
    // Main issues `__Secure-authjs.session-token` on HTTPS. Reading the
    // unprefixed name instead finds nothing and reads as "not signed in".
    secureCookie: true
  });
  if (!token || (token.registrant != null && token.registrant !== false) || typeof token.email !== 'string' || !token.email.trim()) return null;
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

/** Ask Main to verify a browser session without distributing its signing key. */
export async function sessionContext(cookie, {
  url = process.env.SESSION_INTROSPECTION_URL,
  token = process.env.SESSION_INTROSPECTION_TOKEN,
  audience = process.env.SESSION_INTROSPECTION_AUDIENCE,
  fetchImpl = fetch,
} = {}) {
  if (!url || !audience || (token?.length ?? 0) < 32) throw new Error('Session authority configuration required');
  const target = new URL(url);
  if (target.protocol !== 'https:' && !(target.protocol === 'http:' && ['localhost','127.0.0.1','[::1]'].includes(target.hostname))) throw new Error('Unsafe session authority URL');
  const response = await fetchImpl(target, { method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'x-sr-session-audience': audience, cookie: cookie ?? '' },
    redirect: 'error', signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error('Session authority unavailable');
  const value = await response.json();
  if (value.email !== null && (typeof value.email !== 'string' || !value.email.includes('@'))) throw new Error('Invalid session authority response');
  if (value.viewingAs != null && (typeof value.viewingAs !== 'string' || !value.email)) throw new Error('Invalid view-as response');
  return { email: value.email, viewingAs: value.viewingAs ?? null };
}

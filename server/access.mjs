import { hash } from './store.mjs';

export function accessError(status, message) {
  return Object.assign(new Error(message), { status });
}

/** No cached grants. An unavailable authority cannot become an allow decision. */
export function accessPolicy(db, { url, token, demo, secure, fetchImpl = fetch }) {
  async function check(user) {
    if (!url || !token || token.length < 32) {
      if (demo && !secure) return { allowed: true, version: user.access_version };
      throw accessError(503, 'Access check unavailable');
    }
    let policy;
    try {
      const target = new URL(url);
      if (target.protocol !== 'https:' && !['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname)) throw new Error();
      target.searchParams.set('email', user.email);
      const r = await fetchImpl(target, { headers: { Authorization: `Bearer ${token}` },
        redirect: 'error', signal: AbortSignal.timeout(5000) });
      if (!r.ok) throw new Error();
      policy = await r.json();
      if (typeof policy.allowed !== 'boolean' || typeof policy.version !== 'string') throw new Error();
    } catch { throw accessError(503, 'Access check unavailable'); }
    if ((!policy.allowed && user.access_allowed !== 0) || user.access_version !== policy.version) {
      // Persist invalidation before responding. An old token cannot revive on
      // a later membership restoration, even if no request saw the removal.
      db.prepare('DELETE FROM credentials WHERE user_id=?').run(user.id);
      db.prepare('DELETE FROM household_views').run();
      db.prepare('DELETE FROM alerts').run();
      db.prepare('UPDATE users SET access_version=?, access_allowed=?, sharing=0, steps_sharing=0, site_pair_wanted=NULL WHERE id=?')
        .run(policy.version, Number(policy.allowed), user.id);
    }
    return policy;
  }
  async function requireUser(user, credentialVersion) {
    const policy = await check(user);
    if (!policy.allowed) throw accessError(403, 'This account no longer has family access');
    if (credentialVersion !== undefined && credentialVersion !== policy.version) {
      throw accessError(401, 'Pair this iPhone again');
    }
    return policy;
  }
  async function household(family) {
    const users = db.prepare('SELECT * FROM users WHERE family=? ORDER BY email').all(family);
    const policies = await Promise.all(users.map(check));
    const active = users.filter((_, i) => policies[i].allowed);
    // Read consent AFTER policy invalidation; never return the old sharing flag.
    const current = active.map(u => db.prepare('SELECT * FROM users WHERE id=?').get(u.id));
    const revision = hash(JSON.stringify(current.map(u => [u.id, u.access_version, u.privacy_version, u.sharing, u.steps_sharing])));
    return { users: current, revision };
  }
  return { check, requireUser, household };
}

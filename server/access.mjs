import { hash } from './store.mjs';

export function accessError(status, message) {
  return Object.assign(new Error(message), { status });
}

/**
 * No cached grants. An unavailable authority cannot become an allow decision.
 *
 * Every decision is Main's, asked fresh — but asked as few times as a request
 * needs. `seen` is one request's own record of the answers it already has:
 * the account check that opens every request and the household read after it
 * name the same person, and the second must not ask Main again a moment later.
 * It lives exactly as long as the request; nothing carries to the next one.
 * A household read asks for every member in ONE call (`emails`), not one call
 * each.
 */
export function accessPolicy(db, { url, token, demo, secure, fetchImpl = fetch }) {
  const ask = target => fetchImpl(target, { headers: { Authorization: `Bearer ${token}` },
    redirect: 'error', signal: AbortSignal.timeout(5000) });
  const valid = policy => policy && typeof policy.allowed === 'boolean' && typeof policy.version === 'string';
  async function one(base, email) {
    const target = new URL(base);
    target.searchParams.set('email', email);
    const r = await ask(target);
    if (!r.ok) throw new Error();
    const policy = await r.json();
    if (!valid(policy)) throw new Error();
    return policy;
  }
  /** Main's answer for each email, in order. A Main from before `emails` 400s it: ask one by one instead. */
  async function fetchPolicies(emails) {
    const base = new URL(url);
    if (base.protocol !== 'https:' && !['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname)) throw new Error();
    if (emails.length === 1) return [await one(base, emails[0])];
    const target = new URL(base);
    for (const email of emails) target.searchParams.append('emails', email);
    const r = await ask(target);
    if (r.status === 400) return Promise.all(emails.map(email => one(base, email)));
    if (!r.ok) throw new Error();
    const body = await r.json();
    const people = body?.people;
    if (!people || typeof people !== 'object') throw new Error();
    return emails.map(email => {
      const policy = people[email.toLowerCase()];
      if (!valid(policy)) throw new Error();
      return policy;
    });
  }
  function apply(user, policy) {
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
  async function checkAll(users, seen) {
    if (!url || !token || token.length < 32) {
      if (demo && !secure) return users.map(user => ({ allowed: true, version: user.access_version }));
      throw accessError(503, 'Access check unavailable');
    }
    const answers = seen ?? new Map();
    const asking = users.filter(user => !answers.has(user.id));
    if (asking.length) {
      let policies;
      try { policies = await fetchPolicies(asking.map(user => user.email)); }
      catch { throw accessError(503, 'Access check unavailable'); }
      asking.forEach((user, i) => answers.set(user.id, apply(user, policies[i])));
    }
    return users.map(user => answers.get(user.id));
  }
  async function check(user, seen) {
    return (await checkAll([user], seen))[0];
  }
  async function requireUser(user, credentialVersion, seen) {
    const policy = await check(user, seen);
    if (!policy.allowed) throw accessError(403, 'This account no longer has family access');
    if (credentialVersion !== undefined && credentialVersion !== policy.version) {
      throw accessError(401, 'Pair this iPhone again');
    }
    return policy;
  }
  async function household(family, seen) {
    const users = db.prepare('SELECT * FROM users WHERE family=? ORDER BY email').all(family);
    const policies = await checkAll(users, seen);
    const active = users.filter((_, i) => policies[i].allowed);
    // Read consent AFTER policy invalidation; never return the old sharing flag.
    const current = active.map(u => db.prepare('SELECT * FROM users WHERE id=?').get(u.id));
    const revision = hash(JSON.stringify(current.map(u => [u.id, u.access_version, u.privacy_version, u.sharing, u.steps_sharing])));
    return { users: current, revision };
  }
  return { check, requireUser, household };
}

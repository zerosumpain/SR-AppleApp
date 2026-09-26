import test from 'node:test';
import assert from 'node:assert/strict';
import { openStore, createUser, issue } from '../store.mjs';
import { createApp } from '../app.mjs';

async function fixture(t, overrides = {}) {
  const db = openStore(':memory:');
  for (const [id, family] of [['alex', 'one'], ['sam', 'one'], ['robin', 'two']]) createUser(db, { id, family, email: `${id}@example.test`, name: id });
  const tokens = Object.fromEntries(['alex', 'sam', 'robin'].map(id => [id, issue(db, id, 'device', 'Test phone', 3600000)]));
  // A configured owner so the tombstone tests below (R7: tombstones are only
  // kept for the configured service owner) exercise the real gate rather than
  // the "no owner configured" branch. serviceToken stays unset, so the
  // service lane itself remains closed (404) for every test using fixture().
  // Tests that need the household lane open (its own token) or a different
  // owner pass `overrides` — merged in last so they can also unset serviceOwner.
  const app = createApp(db, { origin: 'http://localhost', demo: true, serviceOwner: 'alex@example.test', ...overrides });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const request = async (path, { user = 'alex', method = 'GET', body, headers = {} } = {}) => {
    const response = await fetch(`http://127.0.0.1:${app.address().port}/api/apple/${path}`, { method, headers: { ...(user ? { Authorization: `Bearer ${tokens[user]}` } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: response.status === 204 ? null : await response.json(), headers: response.headers };
  };
  return { db, tokens, request };
}
const stamp = () => new Date().toISOString();
const health = (id = 'sample') => ({ id, kind: 'heart_rate', start: stamp(), end: stamp(), value: 72, unit: 'bpm', source: 'Test' });
const location = () => ({ id: 'point', recorded: stamp(), latitude: 51, longitude: 0, accuracy: 10, speed: 1, moving: true });
const batch = (records = [], locations = [], deleted = []) => ({ health: records, locations, deleted });

test('authentication is required and health cannot be read across users or via family', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('health', { user: null })).status, 401);
  assert.equal((await request('sync', { method: 'POST', body: batch([health()]) })).status, 200);
  assert.equal((await request('health')).body.records.length, 1);
  assert.equal((await request('health', { user: 'sam' })).body.records.length, 0);
  assert.equal((await request('health?user=alex', { user: 'sam' })).status, 400);
  const family = (await request('family', { user: 'sam' })).body;
  assert.equal(JSON.stringify(family).includes('heart_rate'), false);
  assert.deepEqual(family.members.map(x => x.id), ['alex', 'sam']);
});
test('location sharing is opt in, family scoped, and pause hides the last location', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('sync', { method: 'POST', body: batch([], [location()]) })).status, 409);
  await request('sharing', { method: 'PUT', body: { enabled: true } });
  assert.equal((await request('sync', { method: 'POST', body: batch([], [location()]) })).status, 200);
  assert.equal((await request('family', { user: 'sam' })).body.members[0].location.latitude, 51);
  assert.equal((await request('family', { user: 'robin' })).body.members.length, 1);
  await request('sharing', { method: 'PUT', body: { enabled: false } });
  assert.equal((await request('family', { user: 'sam' })).body.members[0].location, null);
});
test('retries are idempotent and deletion only affects the authenticated owner', async t => {
  const { request } = await fixture(t);
  const payload = batch([health()]);
  await request('sync', { method: 'POST', body: payload });
  await request('sync', { method: 'POST', body: payload });
  await request('sync', { user: 'sam', method: 'POST', body: payload });
  assert.equal((await request('health')).body.records.length, 1);
  await request('sync', { method: 'POST', body: batch([], [], ['sample']) });
  assert.equal((await request('health')).body.records.length, 0);
  assert.equal((await request('health', { user: 'sam' })).body.records.length, 1);
});
test('invalid batches are atomic; ownership spoofing, ranges and oversized batches rejected', async t => {
  const { request } = await fixture(t);
  const cases = [batch([health(), { ...health('bad'), value: 900 }]), { ...batch(), userId: 'sam' }, batch([{ ...health(), user_id: 'sam' }]), batch(Array.from({ length: 501 }, () => health()))];
  for (const body of cases) assert.equal((await request('sync', { method: 'POST', body })).status, 400);
  assert.equal((await request('health')).body.records.length, 0);
});
test('browser pairing is single-use; browser cannot upload; revoked devices cannot read', async t => {
  const { request } = await fixture(t);
  const login = await request('demo-signin', { user: null, method: 'POST', headers: { Origin: 'http://localhost' }, body: { email: 'alex@example.test' } });
  assert.equal(login.status, 200);
  const headers = { Cookie: login.headers.get('set-cookie').split(';')[0], Origin: 'http://localhost' };
  assert.equal((await request('pair-code', { user: null, method: 'POST', headers: { ...headers, Origin: 'https://evil.test' }, body: {} })).status, 403);
  const code = (await request('pair-code', { user: null, method: 'POST', headers, body: {} })).body.code;
  const paired = await request('pair', { user: null, method: 'POST', body: { code, label: 'My phone' } });
  assert.equal(paired.status, 200);
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code, label: 'Replay' } })).status, 401);
  assert.equal((await request('sync', { user: null, method: 'POST', headers, body: batch([health()]) })).status, 404);
  const devices = (await request('devices', { user: null, headers })).body.devices;
  for (const d of devices) await request(`devices/${d.id}`, { user: null, method: 'DELETE', headers });
  assert.equal((await request('health')).status, 401);
  assert.equal((await request('health', { user: null, headers: { Authorization: `Bearer ${paired.body.token}` } })).status, 401);
});
test('delete uploaded data revokes devices and pairing codes without touching another user', async t => {
  const { request, db } = await fixture(t);
  await request('sync', { method: 'POST', body: batch([health()]) });
  await request('sync', { user: 'sam', method: 'POST', body: batch([health()]) });
  const code = issue(db, 'alex', 'pair', 'Pending', 600000);
  assert.equal((await request('data', { method: 'DELETE' })).status, 200);
  assert.equal((await request('health')).status, 401);
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code, label: 'Phone' } })).status, 401);
  assert.equal((await request('health', { user: 'sam' })).body.records.length, 1);
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM health WHERE user_id=?').get('alex').count, 0);
});
test('expired credentials fail and secrets are not returned with profile', async t => {
  const { request, db } = await fixture(t);
  const profile = await request('me');
  assert.equal(profile.headers.get('cache-control'), 'no-store');
  assert.deepEqual(Object.keys(profile.body).sort(), ['demo', 'email', 'id', 'name', 'owner', 'sharing']);
  db.prepare('UPDATE credentials SET expires=0').run();
  assert.equal((await request('me')).status, 401);
});
test('pair codes expire and new codes do not grant browser sessions', async t => {
  const { request, db } = await fixture(t);
  const code = issue(db, 'alex', 'pair', 'Expired', -1);
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code, label: 'Phone' } })).status, 401);
  const fresh = issue(db, 'alex', 'pair', 'Pending', 60000);
  assert.equal((await request('health', { user: null, headers: { Cookie: `sr_apple=${fresh}` } })).status, 401);
});
test('summary stays owner scoped even with a noisy heart-rate history', async t => {
  const { request } = await fixture(t);
  const stamp = new Date().toISOString();
  const steps = { id: 'daily', kind: 'steps', start: stamp, end: stamp, value: 4567, unit: 'count', source: 'HealthKit statistics' };
  await request('sync', { method: 'POST', body: batch([steps]) });
  for (let b = 0; b < 2; b++) await request('sync', { method: 'POST', body: batch(Array.from({ length: 300 }, (_, i) => health(`hr-${b}-${i}`))) });
  const result = await request('summary');
  assert.equal(result.body.records.find(r => r.kind === 'steps').value, 4567);
  assert.equal((await request('summary', { user: 'sam' })).body.records.length, 0);
});

test('summary only surfaces legacy kinds, not the whole catalogue', async t => {
  const { request } = await fixture(t);
  const stamp = new Date().toISOString();
  const ox = { id: 'ox', kind: 'oxygen_saturation', start: stamp, end: stamp, value: 98, unit: '%', source: 'Watch' };
  await request('sync', { method: 'POST', body: batch([health(), ox]) });
  const result = await request('summary');
  assert.deepEqual(result.body.records.map(r => r.kind).sort(), ['heart_rate']);
});

test('unfiltered /health hides workout route/series chunks, but an explicit kind still returns them', async t => {
  const { request } = await fixture(t);
  const stamp = new Date().toISOString();
  const t0 = Math.floor(Date.now() / 1000) - 10;
  const route = { id: 'route:W1:0', kind: 'workout_route', start: stamp, end: stamp, source: 'Watch', workout: 'W1', chunk: 0, points: [[t0, 51.5, -0.1, 10, 3, 5]] };
  await request('sync', { method: 'POST', body: batch([health(), route]) });
  const all = await request('health');
  assert.deepEqual(all.body.records.map(r => r.kind).sort(), ['heart_rate']);
  const explicit = await request('health?kind=workout_route');
  assert.equal(explicit.body.records.length, 1);
});

test('QR pixels contain the canonical origin and a single-use code; regeneration revokes the previous code', async t => {
  const { PNG } = await import('pngjs');
  const { default: jsQR } = await import('jsqr');
  const { request } = await fixture(t);
  const login = await request('demo-signin', { user: null, method: 'POST', headers: { Origin: 'http://localhost' }, body: { email: 'alex@example.test' } });
  const headers = { Cookie: login.headers.get('set-cookie').split(';')[0], Origin: 'http://localhost', 'X-Forwarded-Host': 'attacker.invalid' };
  const first = await request('pair-code', { user: null, method: 'POST', headers, body: {} });
  assert.equal(first.status, 200);
  assert.equal(first.body.expiresIn, 600);
  const png = PNG.sync.read(Buffer.from(first.body.qr.split(',')[1], 'base64'));
  const decoded = jsQR(new Uint8ClampedArray(png.data), png.width, png.height);
  assert.ok(decoded, 'Generated QR image is readable');
  const payload = JSON.parse(decoded.data);
  assert.deepEqual(payload, { type: 'sr-companion-pair', version: 1, server: 'http://localhost', code: first.body.code });
  const next = await request('pair-code', { user: null, method: 'POST', headers, body: {} });
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code: payload.code, label: 'Old QR' } })).status, 401);
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code: next.body.code, label: 'New QR' } })).status, 200);
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code: next.body.code, label: 'Replay' } })).status, 401);
  assert.equal((await request('pair-code', { user: null, method: 'POST', body: {} })).status, 401);
});

// ---------------------------------------------------------------------------
// Signing in with the main site's account
//
// The companion's own email-and-password login is gone. What replaces it is the
// site's Google session, and these cover the three things that go wrong when an
// app starts trusting somebody else's cookie: a way in with no session, a way in
// for somebody the site knows but this server does not, and a local-only lane
// reachable in production.
// ---------------------------------------------------------------------------

test('a browser with no session is refused, and told where to go', async (t) => {
  const { request } = await fixture(t);
  const anonymous = await request('me', { user: null });
  assert.equal(anonymous.status, 401);
  assert.match(anonymous.body.error, /Sign in at strangeramblings\.com/);
});

test('a signed-in stranger is refused rather than enrolled', async (t) => {
  const { request } = await fixture(t);
  // Authentication says who; the users table says whether. Family membership
  // decides who can see a location, so a valid Google login must not create one.
  const stranger = await request('me', {
    user: null,
    headers: { Cookie: 'sr_apple_demo=nobody%40example.test' }
  });
  assert.equal(stranger.status, 403);
  assert.match(stranger.body.error, /not set up on the companion/);
});

test('the preview sign-in identifies a known account', async (t) => {
  const { request } = await fixture(t);
  const me = await request('me', {
    user: null,
    headers: { Cookie: 'sr_apple_demo=alex%40example.test' }
  });
  assert.equal(me.status, 200);
  assert.equal(me.body.email, 'alex@example.test');
});

test('the preview lane cannot exist on an https origin', async (t) => {
  // Two independent guards, and this asserts the one a mis-set environment
  // variable cannot defeat: production's origin is https, so even DEMO_MODE=1
  // leaves this shut.
  const db = openStore(':memory:');
  createUser(db, { id: 'alex', family: 'one', email: 'alex@example.test', name: 'alex' });
  const app = createApp(db, { origin: 'https://strangeramblings.com', demo: true, authSecret: 'x'.repeat(40) });
  await new Promise((resolve) => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise((resolve) => app.close(resolve)); db.close(); });
  const base = `http://127.0.0.1:${app.address().port}/api/apple`;

  const cookie = await fetch(`${base}/me`, { headers: { Cookie: 'sr_apple_demo=alex%40example.test' } });
  assert.equal(cookie.status, 401, 'a demo cookie must not authenticate on https');

  const signin = await fetch(`${base}/demo-signin`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://strangeramblings.com' },
    body: JSON.stringify({ email: 'alex@example.test' })
  });
  assert.equal(signin.status, 404, 'the demo endpoint must not exist on https');

  const context = await fetch(`${base}/context`);
  assert.equal((await context.json()).demo, false, 'the page must not be offered a door that is shut');
});

test('a device token still works, and is the only lane that needs no session', async (t) => {
  const { request } = await fixture(t);
  // The phone syncs in the background while the phone is locked and has no
  // browser session to present. Changing the browser lane must not touch it.
  const me = await request('me');
  assert.equal(me.status, 200);
  assert.equal(me.body.email, 'alex@example.test');
});

// --- Household: owner flag -------------------------------------------------

test('/me reports owner true only for the configured service owner, case-insensitively', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('me')).body.owner, true);
  assert.equal((await request('me', { user: 'sam' })).body.owner, false);
});

test('/me reports owner false for everyone when APPLE_SERVICE_OWNER is unset', async t => {
  const db = openStore(':memory:');
  createUser(db, { id: 'alex', family: 'one', email: 'alex@example.test', name: 'alex' });
  const token = issue(db, 'alex', 'device', 'Test phone', 3600000);
  const app = createApp(db, { origin: 'http://localhost', demo: true });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const response = await fetch(`http://127.0.0.1:${app.address().port}/api/apple/me`, { headers: { Authorization: `Bearer ${token}` } });
  assert.equal((await response.json()).owner, false);
});

// --- Household: GET /api/apple/household -------------------------------

const HOUSEHOLD_TOKEN = 'household-secret-for-tests';
const householdFix = (id, recorded, { lat = 51.0, lon = -1.0 } = {}) => ({ id, recorded, latitude: lat, longitude: lon, accuracy: 5, speed: 0, moving: false });

test('the household lane does not exist until APPLE_HOUSEHOLD_TOKEN is configured', async t => {
  const { request } = await fixture(t);
  const response = await request('household', { user: null, headers: { Authorization: 'Bearer anything' } });
  assert.equal(response.status, 404);
});

test('the household lane refuses the SR-Health service token, refuses any other wrong token, and accepts its own', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN, serviceToken: 'sr-health-service-token' });
  assert.equal((await request('household', { user: null, headers: { Authorization: 'Bearer sr-health-service-token' } })).status, 401);
  assert.equal((await request('household', { user: null, headers: { Authorization: 'Bearer wrong' } })).status, 401);
  assert.equal((await request('household', { user: null })).status, 401);
  assert.equal((await request('household', { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } })).status, 200);
});

test('the household lane rejects unknown query parameters', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const response = await request('household?foo=1', { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
  assert.equal(response.status, 400);
});

test('a household token equal to the service token disables the household lane (R9-style guard, mirrors the doorbell/service check)', async t => {
  const SAME = 'shared-token-value-for-tests';
  const { request } = await fixture(t, { householdToken: SAME, serviceToken: SAME });
  const response = await request('household', { user: null, headers: { Authorization: `Bearer ${SAME}` } });
  assert.equal(response.status, 404, 'a household token identical to the service token must be treated as unconfigured');
});

test('the household lane is answered from the received index, not a scan of every location', t => {
  const db = openStore(':memory:');
  t.after(() => db.close());
  createUser(db, { id: 'alex', family: 'one', email: 'alex@example.test', name: 'alex' });
  // The exact SQL app.mjs's household GET runs on a paged (cursor-bearing)
  // request — the branch most likely to fall back to a scan + temp sort if
  // the index doesn't cover both the WHERE and the ORDER BY.
  const sql = `SELECT l.user_id, l.id, l.recorded, l.payload, l.received, u.email FROM locations l JOIN users u ON u.id=l.user_id WHERE u.family=? AND u.sharing=1 AND (l.received > ? OR (l.received = ? AND (l.user_id > ? OR (l.user_id = ? AND l.id > ?)))) ORDER BY l.received, l.user_id, l.id LIMIT ?`;
  const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all('one', '2020-01-01T00:00:00.000Z', '2020-01-01T00:00:00.000Z', 'alex', 'alex', 'a', 10);
  const detail = plan.map(r => r.detail).join('\n');
  assert.match(detail, /locations_received/, 'the household page query should use the received index, not scan locations by user_id alone');
  assert.doesNotMatch(detail, /USE TEMP B-TREE/, 'the ORDER BY should be satisfied by the index, not a temp sort');
});

test('the household lane replies empty, echoing the cursor, when no service owner is configured', async t => {
  const db = openStore(':memory:');
  createUser(db, { id: 'alex', family: 'one', email: 'alex@example.test', name: 'alex' });
  const app = createApp(db, { origin: 'http://localhost', demo: true, householdToken: HOUSEHOLD_TOKEN });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const response = await fetch(`http://127.0.0.1:${app.address().port}/api/apple/household?since=abc`, { headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { cursor: 'abc', users: [], fixes: [], more: false });
});

test('paging across the household lane returns every shared fix exactly once', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await request('sharing', { method: 'PUT', body: { enabled: true } });
  await request('sharing', { user: 'sam', method: 'PUT', body: { enabled: true } });
  const stamp = i => new Date(Date.now() - (20 - i) * 60000).toISOString();
  const alexFixes = Array.from({ length: 5 }, (_, i) => householdFix(`alex-${i}`, stamp(i)));
  const samFixes = Array.from({ length: 3 }, (_, i) => householdFix(`sam-${i}`, stamp(i + 5), { lat: 51.1, lon: -1.1 }));
  assert.equal((await request('sync', { method: 'POST', body: batch([], alexFixes) })).status, 200);
  assert.equal((await request('sync', { user: 'sam', method: 'POST', body: batch([], samFixes) })).status, 200);

  const seen = new Set();
  let cursor = '', pages = 0;
  for (; ;) {
    const { status, body } = await request(`household?since=${encodeURIComponent(cursor)}&limit=2`, { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
    assert.equal(status, 200);
    assert.ok(body.fixes.length <= 2);
    for (const fix of body.fixes) seen.add(`${fix.email}:${fix.id}`);
    cursor = body.cursor;
    pages++;
    if (!body.more) break;
    assert.ok(pages < 20, 'paging did not terminate');
  }
  assert.equal(seen.size, 8);
  assert.ok(pages >= 4, 'a limit of 2 over 8 fixes should take at least 4 pages');
  // Re-fetching from the final cursor finds nothing new and still terminates.
  const tail = await request(`household?since=${encodeURIComponent(cursor)}&limit=2`, { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
  assert.deepEqual(tail.body.fixes, []);
  assert.equal(tail.body.more, false);
});

test('a family member with sharing off is listed but contributes no fixes', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await request('sharing', { user: 'sam', method: 'PUT', body: { enabled: true } });
  await request('sync', { user: 'sam', method: 'POST', body: batch([], [householdFix('sam-1', new Date().toISOString())]) });
  await request('sharing', { user: 'sam', method: 'PUT', body: { enabled: false } });
  const { body } = await request('household', { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
  assert.deepEqual(body.users.find(u => u.email === 'sam@example.test'), { email: 'sam@example.test', name: 'sam', sharing: false, sitePairWanted: null });
  assert.equal(body.fixes.some(f => f.email === 'sam@example.test'), false);
});

test('a user in another family never appears in the household lane', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await request('sharing', { user: 'robin', method: 'PUT', body: { enabled: true } });
  await request('sync', { user: 'robin', method: 'POST', body: batch([], [householdFix('robin-1', new Date().toISOString())]) });
  const { body } = await request('household', { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
  assert.equal(body.users.some(u => u.email === 'robin@example.test'), false);
  assert.equal(body.fixes.some(f => f.email === 'robin@example.test'), false);
});

// --- Household: events in, alerts out ------------------------------------

const householdEvent = (id, recipients, overrides = {}) => ({ id, recipients, title: 'Arrived', body: 'sam arrived home', at: new Date().toISOString(), ...overrides });
const postEvents = (request, events) => request('household/events', { user: null, method: 'POST', headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` }, body: { events } });

test('household events does not exist until APPLE_HOUSEHOLD_TOKEN is configured, and refuses the wrong token', async t => {
  const closed = await fixture(t);
  assert.equal((await postEvents(closed.request, [])).status, 404);
  const open = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const wrong = await open.request('household/events', { user: null, method: 'POST', headers: { Authorization: 'Bearer wrong' }, body: { events: [] } });
  assert.equal(wrong.status, 401);
});

test('household events are idempotent on a repeated id', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const event = householdEvent('evt-1', ['alex@example.test']);
  const first = await postEvents(request, [event]);
  assert.equal(first.status, 200);
  assert.equal(first.body.accepted, 1);
  const second = await postEvents(request, [event]);
  assert.equal(second.status, 200);
  assert.equal(second.body.accepted, 0);
  assert.equal(db.prepare("SELECT count(*) n FROM alerts WHERE user_id='alex'").get().n, 1);
});

test('a recipient only sees their own alerts', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await postEvents(request, [householdEvent('evt-2', ['alex@example.test'])]);
  assert.deepEqual((await request('alerts', { user: 'sam' })).body.alerts, []);
  const mine = (await request('alerts')).body.alerts;
  assert.equal(mine.length, 1);
  assert.deepEqual(mine[0], { id: 'evt-2', title: 'Arrived', body: 'sam arrived home', at: mine[0].at });
});

test('unknown recipients and a recipient outside the family are skipped, not errors', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const result = await postEvents(request, [householdEvent('evt-3', ['alex@example.test', 'ghost@example.test', 'robin@example.test'])]);
  assert.equal(result.status, 200);
  assert.equal(result.body.accepted, 1);
  assert.equal(db.prepare("SELECT count(*) n FROM alerts WHERE user_id='robin'").get().n, 0);
});

test("ack of another user's alert id acks nothing", async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await postEvents(request, [householdEvent('evt-4', ['alex@example.test'])]);
  const stolen = await request('alerts/ack', { user: 'sam', method: 'POST', body: { ids: ['evt-4'] } });
  assert.equal(stolen.status, 200);
  assert.equal(stolen.body.acked, 0);
  assert.equal(db.prepare("SELECT acked FROM alerts WHERE user_id='alex' AND id='evt-4'").get().acked, null);
  const real = await request('alerts/ack', { method: 'POST', body: { ids: ['evt-4'] } });
  assert.equal(real.body.acked, 1);
  assert.deepEqual((await request('alerts')).body.alerts, []);
});

test('alerts older than 7 days are pruned on every events POST', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const stale = new Date(Date.now() - 8 * 86400000).toISOString();
  db.prepare('INSERT INTO alerts (user_id, id, payload, created) VALUES (?,?,?,?)').run('alex', 'old', JSON.stringify({ id: 'old', title: 'Stale', body: 'x', at: stale }), stale);
  assert.equal(db.prepare('SELECT count(*) n FROM alerts').get().n, 1);
  await postEvents(request, [householdEvent('evt-5', ['sam@example.test'])]);
  assert.equal(db.prepare("SELECT count(*) n FROM alerts WHERE id='old'").get().n, 0);
  assert.equal(db.prepare("SELECT count(*) n FROM alerts WHERE id='evt-5'").get().n, 1);
});

test("deleting my data removes my alerts, not another user's", async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await postEvents(request, [householdEvent('evt-6', ['alex@example.test', 'sam@example.test'])]);
  assert.equal((await request('data', { method: 'DELETE' })).status, 200);
  assert.equal(db.prepare("SELECT count(*) n FROM alerts WHERE user_id='alex'").get().n, 0);
  assert.equal(db.prepare("SELECT count(*) n FROM alerts WHERE user_id='sam'").get().n, 1);
});

// --- Site pairing request: POST /api/apple/site-pair --------------------

test('site-pair needs a signed-in caller and a boolean, and nothing else', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('site-pair', { user: null, method: 'POST', body: { wanted: true } })).status, 401);
  assert.equal((await request('site-pair', { method: 'POST', body: { wanted: 'yes' } })).status, 400);
  assert.equal((await request('site-pair', { method: 'POST', body: { wanted: true, email: 'sam@example.test' } })).status, 400);
  const ok = await request('site-pair', { user: 'sam', method: 'POST', body: { wanted: true } });
  assert.equal(ok.status, 200);
  assert.deepEqual(ok.body, { ok: true });
});

test("site-pair sets and clears only the caller's own row", async t => {
  const { request, db } = await fixture(t);
  const wanted = id => db.prepare('SELECT site_pair_wanted w FROM users WHERE id=?').get(id).w;
  await request('site-pair', { user: 'sam', method: 'POST', body: { wanted: true } });
  assert.ok(!Number.isNaN(Date.parse(wanted('sam'))), 'wanted is stamped with a time');
  assert.equal(wanted('alex'), null);
  assert.equal(wanted('robin'), null);
  await request('site-pair', { user: 'sam', method: 'POST', body: { wanted: false } });
  assert.equal(wanted('sam'), null);
});

test('the household lane lists who wants a site pairing', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await request('site-pair', { user: 'sam', method: 'POST', body: { wanted: true } });
  const { body } = await request('household', { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
  const byEmail = Object.fromEntries(body.users.map(u => [u.email, u]));
  assert.equal(byEmail['alex@example.test'].sitePairWanted, null);
  assert.ok(!Number.isNaN(Date.parse(byEmail['sam@example.test'].sitePairWanted)));
  assert.equal(byEmail['robin@example.test'], undefined);
});

test('an existing database gains site_pair_wanted, and opening it twice is fine', async (t) => {
  const path = `/tmp/sr-apple-sitepair-${Date.now()}.sqlite`;
  openStore(path).close();
  const db = openStore(path);
  t.after(() => { db.close(); });
  const columns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
  assert.ok(columns.includes('site_pair_wanted'));
});

test('the stored password hashes are gone, not merely unused', async (t) => {
  const { db } = await fixture(t);
  const columns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
  assert.ok(!columns.includes('password'), `users still has: ${columns.join(', ')}`);
});

test('an existing database is migrated, dropping the column it arrived with', async (t) => {
  // The production database predates this change and has NOT NULL password
  // values in it. Opening it must remove them rather than leaving credential
  // material behind for something that no longer reads it.
  const { DatabaseSync } = await import('node:sqlite');
  const path = `/tmp/sr-apple-migrate-${Date.now()}.sqlite`;
  const old = new DatabaseSync(path);
  old.exec(`CREATE TABLE users (
    id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
    family TEXT NOT NULL, password TEXT NOT NULL, sharing INTEGER NOT NULL DEFAULT 0);`);
  old.prepare('INSERT INTO users(id,email,name,family,password) VALUES (?,?,?,?,?)')
    .run('john', 'john@example.test', 'John', 'kelly', 'salt:deadbeef');
  old.close();

  const db = openStore(path);
  t.after(() => { db.close(); });
  const columns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
  assert.ok(!columns.includes('password'), 'migration did not drop the column');
  // And the person survives it.
  assert.equal(db.prepare('SELECT email FROM users WHERE id=?').get('john').email, 'john@example.test');
});

test('a real Auth.js session cookie from the main site authenticates', async (t) => {
  // The preview lane above proves the plumbing; this proves the lane production
  // actually uses. A genuine encrypted Auth.js JWE is minted with the same
  // library Main signs with, and must resolve to the account behind it.
  const { encode } = await import('@auth/core/jwt');
  const secret = 'test-secret-at-least-32-characters-long!!';
  const db = openStore(':memory:');
  createUser(db, { id: 'alex', family: 'one', email: 'alex@example.test', name: 'alex' });
  const app = createApp(db, { origin: 'https://strangeramblings.com', demo: false, authSecret: secret });
  await new Promise((resolve) => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise((resolve) => app.close(resolve)); db.close(); });
  const base = `http://127.0.0.1:${app.address().port}/api/apple`;

  // `secureCookie: true` means Main names it `__Secure-authjs.session-token`.
  // Reading the unprefixed name instead finds nothing and reads as "signed out",
  // which is the quiet way this breaks.
  const salt = '__Secure-authjs.session-token';
  const token = await encode({ token: { email: 'Alex@Example.Test' }, secret, salt, maxAge: 3600 });

  const ok = await fetch(`${base}/me`, { headers: { Cookie: `${salt}=${token}` } });
  assert.equal(ok.status, 200);
  // Matched case-insensitively — Google returns whatever case the person typed.
  assert.equal((await ok.json()).email, 'alex@example.test');

  // A tampered cookie is not a session.
  const bad = await fetch(`${base}/me`, { headers: { Cookie: `${salt}=${token.slice(0, -4)}xxxx` } });
  assert.equal(bad.status, 401);

  // Nor is one signed with somebody else's secret.
  const wrong = await encode({ token: { email: 'alex@example.test' }, secret: 'a-completely-different-secret-value-32!!', salt, maxAge: 3600 });
  const forged = await fetch(`${base}/me`, { headers: { Cookie: `${salt}=${wrong}` } });
  assert.equal(forged.status, 401);
});

// --- Movement ---------------------------------------------------------------

/** Noon UTC yesterday: always in the past, always inside the retention window. */
function baseInstant() {
  const day = new Date();
  day.setUTCDate(day.getUTCDate() - 1);
  day.setUTCHours(12, 0, 0, 0);
  return day.getTime();
}
const fix = (id, at, moving = true) => ({ id, recorded: new Date(at).toISOString(), latitude: 54.52 + id.length / 10000, longitude: -1.57, accuracy: 6, speed: moving ? 1.4 : 0, moving });

async function withTrack(request) {
  const base = baseInstant();
  await request('sharing', { method: 'PUT', body: { enabled: true } });
  const locations = [
    fix('a', base), fix('b', base + 30000), fix('c', base + 60000),
    // Three hours of silence: the motion gate let the phone sleep.
    fix('d', base + 60000 + 3 * 3600000), fix('e', base + 90000 + 3 * 3600000),
  ];
  assert.equal((await request('sync', { method: 'POST', body: batch([], locations) })).status, 200);
  return { base, date: new Date(base).toISOString().slice(0, 10) };
}

test('a track is readable only by the person who recorded it', async t => {
  const { request } = await fixture(t);
  const { date } = await withTrack(request);

  const mine = (await request(`track?offset=0&date=${date}`)).body;
  assert.equal(mine.points.length, 5);
  // The gap becomes a second segment rather than a straight line through it.
  assert.deepEqual(mine.segments, [[0, 2], [3, 4]]);
  assert.equal(mine.totals.fixes, 5);
  assert.deepEqual(mine.days.map(d => d.date), [date]);

  // Same family, sharing switched ON, and still nothing: `family` discloses a
  // latest position, never a history, and there is no parameter to ask with.
  assert.deepEqual((await request('track?offset=0', { user: 'sam' })).body.days, []);
  assert.equal((await request(`track?offset=0&date=${date}`, { user: 'sam' })).body.points.length, 0);
  assert.equal((await request('track?offset=0&user=alex', { user: 'sam' })).status, 400);
  assert.equal((await request('track?offset=0', { user: null })).status, 401);
  assert.equal(JSON.stringify((await request('family', { user: 'sam' })).body).includes('"points"'), false);
});

test('reading your own history does not depend on the sharing switch', async t => {
  const { request } = await fixture(t);
  const { date } = await withTrack(request);
  await request('sharing', { method: 'PUT', body: { enabled: false } });
  // Pausing hides you from the family and stops new uploads. It must not lock
  // you out of what you already recorded.
  assert.equal((await request('family', { user: 'sam' })).body.members[0].location, null);
  assert.equal((await request(`track?offset=0&date=${date}`)).body.points.length, 5);
});

test('track parameters are validated rather than coerced', async t => {
  const { request } = await fixture(t);
  await withTrack(request);
  assert.equal((await request('track?limit=5')).status, 400);
  assert.equal((await request('track?offset=abc')).status, 400);
  assert.equal((await request('track?offset=1.5')).status, 400);
  assert.equal((await request('track?offset=900')).status, 400);
  assert.equal((await request('track?offset=0&date=yesterday')).status, 400);
  // `Number('')` and `Number(null)` are both 0, so an absent or empty offset
  // has to mean UTC deliberately rather than by accident.
  assert.equal((await request('track')).status, 200);
  assert.equal((await request('track?offset=')).status, 200);
});

test('a day index buckets in the reader timezone', async t => {
  const { request } = await fixture(t);
  const { base } = await withTrack(request);
  const utcDate = new Date(base).toISOString().slice(0, 10);
  // Noon is nowhere near a boundary, so every offset agrees on the day; the
  // shift shows up in the window the date resolves to.
  assert.deepEqual((await request('track?offset=-60')).body.days.map(d => d.date), [utcDate]);
  const shifted = (await request(`track?offset=-60&date=${utcDate}`)).body;
  assert.equal(new Date(shifted.from * 1000).toISOString().endsWith('T23:00:00.000Z'), true);
  assert.equal(shifted.to - shifted.from, 86400);
});

test('the timeline bins heart rate, selects spans by overlap, and stays owner scoped', async t => {
  const { request } = await fixture(t);
  const base = baseInstant();
  const date = new Date(base).toISOString().slice(0, 10);
  const from = Date.parse(`${date}T00:00:00Z`) / 1000;
  const iso = at => new Date(at).toISOString();
  await request('sync', { method: 'POST', body: batch([
    { id: 'hr1', kind: 'heart_rate', start: iso(base), end: iso(base), value: 60, unit: 'bpm', source: 'Watch' },
    { id: 'hr2', kind: 'heart_rate', start: iso(base + 60000), end: iso(base + 60000), value: 80, unit: 'bpm', source: 'Watch' },
    { id: 'hr3', kind: 'heart_rate', start: iso(base + 2 * 3600000), end: iso(base + 2 * 3600000), value: 100, unit: 'bpm', source: 'Watch' },
    // Begins the evening BEFORE this day and ends inside it.
    { id: 'sleep1', kind: 'sleep', start: iso(base - 14 * 3600000), end: iso(base - 6 * 3600000), stage: 'deep', source: 'Watch' },
    { id: 'walk', kind: 'workout', start: iso(base), end: iso(base + 1800000), value: 1800, unit: 'seconds', activity: 'Walking', distance: 2100, source: 'Watch' },
    { id: 'steps1', kind: 'steps', start: iso(from * 1000), end: iso(from * 1000 + 86399000), value: 8241, unit: 'count', source: 'HealthKit daily statistics' }
  ]) });

  const body = (await request(`timeline?from=${from}&to=${from + 86400}`)).body;
  assert.equal(body.heartRate.seconds, 300);
  // The two readings a minute apart average into one bucket; the third is its own.
  assert.equal(body.heartRate.bins.length, 2);
  assert.equal(body.heartRate.bins[0][1], 70);
  assert.equal(body.heartRate.bins[1][1], 100);
  // Selected by overlap: a night that started yesterday evening is this
  // morning's sleep, and selecting on `start` alone would lose every one.
  assert.deepEqual(body.sleep.map(s => s.stage), ['deep']);
  assert.deepEqual(body.workouts.map(w => w.activity), ['Walking']);
  // Steps come back as records, never pre-summed: one cumulative row per day
  // means adding two of them together reports a day that never happened.
  assert.deepEqual(body.steps.map(s => s.value), [8241]);

  assert.deepEqual((await request(`timeline?from=${from}&to=${from + 86400}`, { user: 'sam' })).body.sleep, []);
  assert.equal((await request(`timeline?from=${from}&to=${from + 86400}`, { user: null })).status, 401);
  assert.equal((await request(`timeline?from=${from}&to=${from + 86400}&user=alex`, { user: 'sam' })).status, 400);
  assert.equal((await request(`timeline?from=${from}&to=${from - 1}`)).status, 400);
  assert.equal((await request(`timeline?from=${from}&to=${from + 40 * 86400}`)).status, 400);
  assert.equal((await request(`timeline?from=${from}&to=${from + 86400}&bins=0`)).status, 400);
  assert.equal((await request('timeline')).status, 400);
});

test('the preview signs out where it signed in, not at the main site', async t => {
  const { request } = await fixture(t);
  const login = await request('demo-signin', { user: null, method: 'POST', body: { email: 'alex@example.test' }, headers: { Origin: 'http://localhost' } });
  const headers = { Cookie: login.headers.get('set-cookie').split(';')[0], Origin: 'http://localhost' };
  const out = await request('logout', { user: null, method: 'POST', body: {}, headers });
  // The preview's session is this server's own cookie. Naming the main site's
  // sign-out URL would send a laptop on loopback to a path nothing serves.
  assert.equal(out.body.signOutAt, undefined);
  assert.match(out.headers.get('set-cookie'), /sr_apple_demo=;.*Max-Age=0/);
  // A real session still belongs to the main site, and still says so.
  const real = await request('logout', { user: null, method: 'POST', body: {}, headers: { ...headers, Cookie: 'x=1' } });
  assert.equal(real.status, 401);
});

test('a day is listed as journeys and the stops between them', async t => {
  const { request } = await fixture(t);
  const base = baseInstant();
  const date = new Date(base).toISOString().slice(0, 10);
  await request('sharing', { method: 'PUT', body: { enabled: true } });
  const walk = (tag, from, count) => Array.from({ length: count }, (_, i) => ({
    id: `${tag}-${i}`, recorded: new Date(from + i * 30000).toISOString(),
    latitude: 54.52 + i / 4000, longitude: -1.57, accuracy: 5, speed: 1.4, moving: true,
  }));
  // An hour at a desk the phone SAMPLED THE WHOLE WAY THROUGH — a fix every two
  // minutes, so there is no recording gap anywhere in this day.
  const desk = Array.from({ length: 30 }, (_, i) => ({
    id: `desk-${i}`, recorded: new Date(base + 900000 + i * 120000).toISOString(),
    latitude: 54.5275, longitude: -1.57, accuracy: 6, speed: 0, moving: false,
  }));
  await request('sync', { method: 'POST', body: batch([], [...walk('out', base, 30), ...desk, ...walk('back', base + 4600000, 30)]) });

  const body = (await request(`track?offset=0&date=${date}`)).body;
  // One unbroken run of recording...
  assert.equal(body.segments.length, 1);
  // ...and still two journeys, because the break is in the MOVEMENT.
  assert.deepEqual(body.activities.map(a => a.kind), ['journey', 'stop', 'journey']);
  assert.equal(body.totals.journeys, 2);
  assert.ok(body.activities[1].seconds > 3000, 'the desk should read as about an hour');
  assert.equal(body.activities[1].fixes > 25, true);
  // Indices address the points array, so the map can light one activity up.
  const [first, last] = [body.activities[0].first, body.activities[0].last];
  assert.equal(body.points[first][2], Math.round(base / 1000));
  assert.ok(last > first);
  // The day index counts journeys too, so the strip can say what a day was.
  assert.equal(body.days.find(d => d.date === date).journeys, 2);
});

test('the service lane reads only the configured owner\'s journeys, and nothing else', async t => {
  const db = openStore(':memory:');
  for (const [id, family] of [['alex', 'one'], ['sam', 'one']]) createUser(db, { id, family, email: `${id}@example.test`, name: id });
  const serviceToken = 'service-token-for-tests';
  const app = createApp(db, { origin: 'http://localhost', serviceToken, serviceOwner: 'Alex@Example.test' });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const base = `http://127.0.0.1:${app.address().port}/api/apple`;
  const get = async (path, token = serviceToken) => {
    const response = await fetch(`${base}/${path}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
    return { status: response.status, body: await response.json() };
  };

  // A twenty-minute walk for alex, and one for sam that must never be read.
  const start = Math.floor(Date.now() / 1000) - 3600;
  const put = db.prepare('INSERT INTO locations VALUES (?,?,?,?,?)');
  for (const [user, lng] of [['alex', 0], ['sam', 1]]) {
    for (let i = 0; i <= 40; i++) {
      const recorded = new Date((start + i * 30) * 1000).toISOString();
      put.run(user, `${user}-${i}`, recorded, JSON.stringify({ id: `${user}-${i}`, recorded, latitude: 51 + i * 0.0004, longitude: lng, accuracy: 5, speed: 1.4, moving: true }), recorded);
    }
  }
  const beat = new Date((start + 300) * 1000).toISOString();
  db.prepare('INSERT INTO health VALUES (?,?,?,?,?,?,?)').run('alex', 'hr', 'heart_rate', beat, beat, JSON.stringify({ id: 'hr', kind: 'heart_rate', start: beat, end: beat, value: 101, unit: 'bpm', source: 'Watch' }), beat);
  const ws = new Date(start * 1000).toISOString(), we = new Date((start + 1200) * 1000).toISOString();
  db.prepare('INSERT INTO health VALUES (?,?,?,?,?,?,?)').run('alex', 'w', 'workout', ws, we, JSON.stringify({ id: 'w', kind: 'workout', start: ws, end: we, value: 1200, unit: 'seconds', source: 'Watch', activity: 'Walking' }), we);

  const ok = await get('journeys');
  assert.equal(ok.status, 200);
  assert.equal(ok.body.journeys.length, 1);
  const [journey] = ok.body.journeys;
  assert.equal(journey.from, start);
  assert.equal(journey.points.length, 41);
  assert.ok(journey.points.every(p => p[0] === 0), 'another user\'s fixes leaked into the owner\'s journey');
  assert.deepEqual(journey.heartRate, [[start + 300, 101]]);
  assert.deepEqual(ok.body.workouts.map(w => w.activity), ['Walking']);
  assert.equal(ok.body.retentionDays, 30);

  // Wrong, missing and device-shaped tokens are all refused.
  assert.equal((await get('journeys', 'wrong')).status, 401);
  assert.equal((await get('journeys', null)).status, 401);
  // No way to ask for somebody else.
  assert.equal((await get('journeys?user=sam')).status, 400);
  assert.equal((await get(`journeys?from=${start - 90 * 86400}&to=${start}`)).status, 400);
  // The token opens nothing but this one endpoint.
  assert.equal((await get('track')).status, 401);
  assert.equal((await get('health')).status, 401);
});

test('the service lane does not exist until it is configured', async t => {
  const db = openStore(':memory:');
  const app = createApp(db, { origin: 'http://localhost', serviceToken: '', serviceOwner: '' });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const response = await fetch(`http://127.0.0.1:${app.address().port}/api/apple/journeys`, { headers: { Authorization: 'Bearer anything' } });
  assert.equal(response.status, 404);
});
test('a HealthKit deletion leaves a tombstone naming its kind and start, and takes the workout\'s chunks with it', async t => {
  const { request, db } = await fixture(t);
  const start = new Date(Date.now() - 7200_000).toISOString(), end = new Date(Date.now() - 3600_000).toISOString();
  const t0 = Math.floor(Date.now() / 1000) - 7000;
  const workout = { id: 'W1', kind: 'workout', start, end, value: 3600, unit: 'seconds', activity: 'Outdoor Run', source: 'Watch' };
  const route = { id: 'route:W1:0', kind: 'workout_route', start, end, source: 'Watch', workout: 'W1', chunk: 0, points: [[t0, 51.5, -0.1, 10, 3, 5], [t0 + 5, 51.5001, -0.1, 10, 3, 5]] };
  assert.equal((await request('sync', { method: 'POST', body: batch([workout, route]) })).status, 200);
  assert.equal((await request('sync', { method: 'POST', body: batch([], [], ['W1']) })).status, 200);
  assert.equal(db.prepare("SELECT count(*) n FROM health WHERE user_id='alex'").get().n, 0);
  const stone = db.prepare("SELECT kind, start FROM health_deleted WHERE user_id='alex' AND id='W1'").get();
  assert.deepEqual({ ...stone }, { kind: 'workout', start });
});
test('re-uploading a deleted id clears its tombstone; deleting an unknown id leaves none', async t => {
  const { request, db } = await fixture(t);
  await request('sync', { method: 'POST', body: batch([health('A')]) });
  await request('sync', { method: 'POST', body: batch([], [], ['A', 'never-seen']) });
  assert.equal(db.prepare('SELECT count(*) n FROM health_deleted').get().n, 1);
  await request('sync', { method: 'POST', body: batch([health('A')]) });
  assert.equal(db.prepare('SELECT count(*) n FROM health_deleted').get().n, 0);
});
test('delete-my-data removes tombstones too', async t => {
  const { request, db } = await fixture(t);
  await request('sync', { method: 'POST', body: batch([health('A')]) });
  await request('sync', { method: 'POST', body: batch([], [], ['A']) });
  await request('data', { method: 'DELETE' });
  assert.equal(db.prepare("SELECT count(*) n FROM health_deleted WHERE user_id='alex'").get().n, 0);
});
test('a tombstone is kept only for the configured service owner\'s deletions (R7)', async t => {
  const { request, db } = await fixture(t);
  // sam is not APPLE_SERVICE_OWNER (alex is). /health only ever reads alex's
  // export, so a tombstone for sam's deletion would sit in the table forever,
  // never handed to anyone — and sam is not who this export is scoped to.
  await request('sync', { user: 'sam', method: 'POST', body: batch([health('S1')]) });
  assert.equal((await request('sync', { user: 'sam', method: 'POST', body: batch([], [], ['S1']) })).status, 200);
  assert.equal(db.prepare("SELECT count(*) n FROM health WHERE user_id='sam'").get().n, 0, 'the deletion itself still applies');
  assert.equal(db.prepare("SELECT count(*) n FROM health_deleted WHERE user_id='sam'").get().n, 0, 'no tombstone for a non-owner');

  // The owner's own deletion is still tombstoned exactly as before.
  await request('sync', { method: 'POST', body: batch([health('A1')]) });
  await request('sync', { method: 'POST', body: batch([], [], ['A1']) });
  assert.equal(db.prepare("SELECT count(*) n FROM health_deleted WHERE user_id='alex'").get().n, 1);
});
test('with no service owner configured, deletions apply but no tombstone is kept (R7)', async t => {
  const db = openStore(':memory:');
  createUser(db, { id: 'alex', family: 'one', email: 'alex@example.test', name: 'alex' });
  const token = issue(db, 'alex', 'device', 'Test phone', 3600000);
  const app = createApp(db, { origin: 'http://localhost', demo: true });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const request = async (path, { method = 'GET', body } = {}) => {
    const response = await fetch(`http://127.0.0.1:${app.address().port}/api/apple/${path}`, { method, headers: { Authorization: `Bearer ${token}`, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) }, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  };
  await request('sync', { method: 'POST', body: batch([health('A')]) });
  assert.equal((await request('sync', { method: 'POST', body: batch([], [], ['A']) })).status, 200);
  assert.equal(db.prepare("SELECT count(*) n FROM health WHERE user_id='alex'").get().n, 0, 'the deletion itself still applies');
  assert.equal(db.prepare('SELECT count(*) n FROM health_deleted').get().n, 0, 'no owner configured means no tombstone');
});

// --- Household: each person's Family view ---------------------------------

const postViews = (request, views, token = HOUSEHOLD_TOKEN) => request('household/views', { user: null, method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: { views } });
const view = (label) => ({ generatedAt: new Date().toISOString(), people: [{ subject: label }] });

test('household views do not exist until APPLE_HOUSEHOLD_TOKEN is configured, and refuse the wrong token', async t => {
  const closed = await fixture(t);
  assert.equal((await postViews(closed.request, [])).status, 404);
  const open = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  assert.equal((await postViews(open.request, [], 'wrong')).status, 401);
});

test('each person reads only their own view, and nothing before one is pushed', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  assert.deepEqual((await request('household/view')).body, { view: null, updated: null });
  const stored = await postViews(request, [{ email: 'ALEX@example.test', view: view('for-alex') }, { email: 'sam@example.test', view: view('for-sam') }]);
  assert.equal(stored.status, 200);
  assert.equal(stored.body.stored, 2);
  assert.equal((await request('household/view')).body.view.people[0].subject, 'for-alex');
  assert.equal((await request('household/view', { user: 'sam' })).body.view.people[0].subject, 'for-sam');
  // The route takes no parameter naming anybody: there is no way to ask for another's.
  assert.equal((await request('household/view?email=sam@example.test')).body.view.people[0].subject, 'for-alex');
});

test('a push replaces the family: a person left out loses their view, another family is never touched or written', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  db.prepare('INSERT INTO household_views (user_id,payload,updated) VALUES (?,?,?)').run('robin', JSON.stringify(view('robin-own')), stamp());
  await postViews(request, [{ email: 'alex@example.test', view: view('a1') }, { email: 'sam@example.test', view: view('s1') }]);
  const second = await postViews(request, [{ email: 'alex@example.test', view: view('a2') }, { email: 'robin@example.test', view: view('intruder') }]);
  assert.equal(second.body.stored, 1);
  assert.equal((await request('household/view')).body.view.people[0].subject, 'a2');
  assert.equal((await request('household/view', { user: 'sam' })).body.view, null);
  assert.equal((await request('household/view', { user: 'robin' })).body.view.people[0].subject, 'robin-own');
});

test('household views reject a malformed batch', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  assert.equal((await postViews(request, [{ email: 'alex@example.test', view: [] }])).status, 400);
  assert.equal((await postViews(request, [{ email: 'alex@example.test', view: view('x'), extra: 1 }])).status, 400);
  assert.equal((await postViews(request, Array.from({ length: 51 }, () => ({ email: 'alex@example.test', view: view('x') })))).status, 400);
});

test('a fix may carry a battery percentage, which the household lane passes on', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  await request('sharing', { method: 'PUT', body: { enabled: true } });
  const withBattery = { ...location(), id: 'charged', battery: 64 };
  assert.equal((await request('sync', { method: 'POST', body: batch([], [withBattery, { ...location(), id: 'old-phone' }]) })).status, 200);
  const { body } = await request('household', { user: null, headers: { Authorization: `Bearer ${HOUSEHOLD_TOKEN}` } });
  assert.equal(body.fixes.find(f => f.id === 'charged').battery, 64);
  assert.equal(body.fixes.find(f => f.id === 'old-phone').battery, null);
  for (const bad of [101, -1, 50.5, '64']) {
    assert.equal((await request('sync', { method: 'POST', body: batch([], [{ ...location(), id: `bad-${bad}`, battery: bad }]) })).status, 400);
  }
});

// --- Household: onboarding (SR-Main /welcome, /admin/access/devices) -------

const household = (request, path, { method = 'GET', body, token = HOUSEHOLD_TOKEN } = {}) =>
  request(path, { user: null, method, body, headers: token ? { Authorization: `Bearer ${token}` } : {} });

test('the onboarding routes do not exist until APPLE_HOUSEHOLD_TOKEN is configured, and refuse the wrong token', async t => {
  const closed = await fixture(t);
  const open = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const routes = [
    ['household/users', 'POST', { email: 'new@example.test', name: 'New' }],
    ['household/pair-code', 'POST', { email: 'sam@example.test' }],
    ['household/devices', 'GET', undefined],
    [`household/devices/${'0'.repeat(64)}`, 'DELETE', undefined],
    ['household/sharing', 'PUT', { email: 'sam@example.test', enabled: true }],
  ];
  for (const [path, method, body] of routes) {
    assert.equal((await household(closed.request, path, { method, body })).status, 404, `${method} ${path} unset`);
    assert.equal((await household(open.request, path, { method, body, token: 'wrong' })).status, 401, `${method} ${path} wrong token`);
    assert.equal((await household(open.request, path, { method, body, token: null })).status, 401, `${method} ${path} no token`);
  }
  assert.equal(open.db.prepare("SELECT count(*) n FROM users WHERE email='new@example.test'").get().n, 0);
});

test('adding a person puts them in the owner\'s family once, lower-cased, sharing off; another family\'s person is refused', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const first = await household(request, 'household/users', { method: 'POST', body: { email: 'New.Person@Example.test', name: ' New Person ' } });
  assert.equal(first.status, 201);
  assert.deepEqual(Object.keys(first.body).sort(), ['created', 'email', 'id', 'name']);
  assert.equal(first.body.email, 'new.person@example.test');
  assert.equal(first.body.name, 'New Person');
  assert.equal(first.body.created, true);
  const row = db.prepare('SELECT family, sharing FROM users WHERE id=?').get(first.body.id);
  assert.deepEqual({ ...row }, { family: 'one', sharing: 0 });
  const again = await household(request, 'household/users', { method: 'POST', body: { email: 'new.person@example.test', name: 'Renamed' } });
  assert.equal(again.status, 200);
  assert.deepEqual(again.body, { id: first.body.id, email: 'new.person@example.test', name: 'New Person', created: false });
  // An existing member's sharing is theirs, and an upsert leaves it alone.
  db.prepare("UPDATE users SET sharing=1 WHERE id='sam'").run();
  assert.equal((await household(request, 'household/users', { method: 'POST', body: { email: 'sam@example.test', name: 'sam' } })).status, 200);
  assert.equal(db.prepare("SELECT sharing FROM users WHERE id='sam'").get().sharing, 1);
  const robin = await household(request, 'household/users', { method: 'POST', body: { email: 'ROBIN@example.test', name: 'robin' } });
  assert.equal(robin.status, 409);
  assert.deepEqual({ ...db.prepare("SELECT family, name FROM users WHERE id='robin'").get() }, { family: 'two', name: 'robin' });
  for (const body of [{ email: 'x@example.test' }, { email: 'no-at', name: 'x' }, { email: 'x@example.test', name: 'x', family: 'two' }, { email: 'x@example.test', name: '   ' }]) {
    assert.equal((await household(request, 'household/users', { method: 'POST', body })).status, 400, JSON.stringify(body));
  }
});

test('adding a person with no configured owner is a configuration conflict, not a new family', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN, serviceOwner: undefined });
  assert.equal((await household(request, 'household/users', { method: 'POST', body: { email: 'new@example.test', name: 'New' } })).status, 409);
  assert.equal(db.prepare("SELECT count(*) n FROM users WHERE email='new@example.test'").get().n, 0);
});

test('a household pair code names the public origin, replaces the old one, and pairs a phone once', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const first = await household(request, 'household/pair-code', { method: 'POST', body: { email: 'SAM@example.test' } });
  assert.equal(first.status, 200);
  assert.deepEqual(Object.keys(first.body).sort(), ['code', 'expiresIn', 'payload']);
  assert.equal(first.body.expiresIn, 600);
  assert.equal(first.body.payload, JSON.stringify({ type: 'sr-companion-pair', version: 1, server: 'https://strangeramblings.com', code: first.body.code }));
  const second = await household(request, 'household/pair-code', { method: 'POST', body: { email: 'sam@example.test' } });
  assert.equal(db.prepare("SELECT count(*) n FROM credentials WHERE user_id='sam' AND kind='pair'").get().n, 1, 'one live code per person');
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code: first.body.code, label: 'Old' } })).status, 401, 'the replaced code is dead');
  const paired = await request('pair', { user: null, method: 'POST', body: { code: second.body.code, label: 'Sam phone' } });
  assert.equal(paired.status, 200);
  assert.equal(paired.body.userId, 'sam');
  assert.equal((await request('pair', { user: null, method: 'POST', body: { code: second.body.code, label: 'Again' } })).status, 401);
  assert.equal((await household(request, 'household/pair-code', { method: 'POST', body: { email: 'robin@example.test' } })).status, 404, 'another family');
  assert.equal((await household(request, 'household/pair-code', { method: 'POST', body: { email: 'ghost@example.test' } })).status, 404, 'unknown');
  assert.equal(db.prepare("SELECT count(*) n FROM credentials WHERE user_id='robin' AND kind='pair'").get().n, 0);
});

test('a household pair code takes its origin from APPLE_PUBLIC_ORIGIN, never the loopback it was asked over', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN, publicOrigin: 'https://staging.example.test/' });
  const { body } = await household(request, 'household/pair-code', { method: 'POST', body: { email: 'alex@example.test' } });
  assert.equal(JSON.parse(body.payload).server, 'https://staging.example.test');
});

test('household devices lists the family\'s live phones only, and revokes only within the family', async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  issue(db, 'sam', 'device', 'Expired phone', -1000);
  issue(db, 'sam', 'pair', 'One-time pairing', 600000);
  const { status, body } = await household(request, 'household/devices');
  assert.equal(status, 200);
  assert.deepEqual(body.devices.map(d => d.email).sort(), ['alex@example.test', 'sam@example.test']);
  const alex = body.devices.find(d => d.email === 'alex@example.test');
  assert.deepEqual(Object.keys(alex).sort(), ['created', 'email', 'expires', 'id', 'label', 'lastUsed', 'name']);
  assert.equal(alex.label, 'Test phone');
  assert.equal(alex.name, 'alex');
  assert.equal(alex.lastUsed, null);
  assert.match(alex.id, /^[0-9a-f]{64}$/);
  assert.ok(Date.parse(alex.expires) > Date.now());
  assert.equal(Date.parse(alex.expires) - Date.parse(alex.created), 90 * 86400000);
  const robinId = db.prepare("SELECT hash FROM credentials WHERE user_id='robin' AND kind='device'").get().hash;
  assert.equal((await household(request, `household/devices/${robinId}`, { method: 'DELETE' })).status, 404, 'another family');
  assert.equal((await request('me', { user: 'robin' })).status, 200, 'robin still paired');
  assert.equal((await household(request, 'household/devices/not-a-hash', { method: 'DELETE' })).status, 404);
  const del = await household(request, `household/devices/${alex.id}`, { method: 'DELETE' });
  assert.equal(del.status, 204);
  assert.equal((await request('me')).status, 401, 'alex\'s phone is revoked');
  assert.equal((await household(request, `household/devices/${alex.id}`, { method: 'DELETE' })).status, 404, 'already gone');
  assert.deepEqual((await household(request, 'household/devices')).body.devices.map(d => d.email), ['sam@example.test']);
});

test('household devices is empty, not an error, when no owner is configured', async t => {
  const { request } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN, serviceOwner: undefined });
  assert.deepEqual((await household(request, 'household/devices')).body, { devices: [] });
});

test("household sharing sets a family member's switch and nobody else's", async t => {
  const { request, db } = await fixture(t, { householdToken: HOUSEHOLD_TOKEN });
  const on = await household(request, 'household/sharing', { method: 'PUT', body: { email: 'Sam@example.test', enabled: true } });
  assert.equal(on.status, 200);
  assert.deepEqual(on.body, { sharing: true });
  assert.equal(db.prepare("SELECT sharing FROM users WHERE id='sam'").get().sharing, 1);
  assert.deepEqual((await household(request, 'household/sharing', { method: 'PUT', body: { email: 'sam@example.test', enabled: false } })).body, { sharing: false });
  assert.equal(db.prepare("SELECT sharing FROM users WHERE id='sam'").get().sharing, 0);
  assert.equal((await household(request, 'household/sharing', { method: 'PUT', body: { email: 'robin@example.test', enabled: true } })).status, 404);
  assert.equal(db.prepare("SELECT sharing FROM users WHERE id='robin'").get().sharing, 0);
  assert.equal((await household(request, 'household/sharing', { method: 'PUT', body: { email: 'sam@example.test', enabled: 'yes' } })).status, 400);
});

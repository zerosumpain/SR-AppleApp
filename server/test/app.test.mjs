import test from 'node:test';
import assert from 'node:assert/strict';
import { openStore, createUser, issue } from '../store.mjs';
import { createApp } from '../app.mjs';

async function fixture(t) {
  const db = openStore(':memory:');
  for (const [id, family] of [['alex', 'one'], ['sam', 'one'], ['robin', 'two']]) createUser(db, { id, family, email: `${id}@example.test`, name: id });
  const tokens = Object.fromEntries(['alex', 'sam', 'robin'].map(id => [id, issue(db, id, 'device', 'Test phone', 3600000)]));
  const app = createApp(db, { origin: 'http://localhost', demo: true });
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => app.close(resolve)); db.close(); });
  const request = async (path, { user = 'alex', method = 'GET', body, headers = {} } = {}) => {
    const response = await fetch(`http://127.0.0.1:${app.address().port}/api/apple/${path}`, { method, headers: { ...(user ? { Authorization: `Bearer ${tokens[user]}` } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json(), headers: response.headers };
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
  assert.deepEqual(Object.keys(profile.body).sort(), ['demo', 'email', 'id', 'name', 'sharing']);
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

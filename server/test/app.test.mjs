import test from 'node:test';
import assert from 'node:assert/strict';
import { openStore, createUser, issue } from '../store.mjs';
import { createApp } from '../app.mjs';

async function fixture(t) {
  const db = openStore(':memory:');
  for (const [id, family] of [['alex', 'one'], ['sam', 'one'], ['robin', 'two']]) createUser(db, { id, family, email: `${id}@example.test`, name: id, password: 'long-test-password' });
  const tokens = Object.fromEntries(['alex', 'sam', 'robin'].map(id => [id, issue(db, id, 'device', 'Test phone', 3600000)]));
  const app = createApp(db, { origin: 'http://localhost' });
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
  const login = await request('login', { user: null, method: 'POST', headers: { Origin: 'http://localhost' }, body: { email: 'alex@example.test', password: 'long-test-password' } });
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
  const login = await request('login', { user: null, method: 'POST', headers: { Origin: 'http://localhost' }, body: { email: 'alex@example.test', password: 'long-test-password' } });
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

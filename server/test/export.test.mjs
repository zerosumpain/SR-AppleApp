import test from 'node:test';
import assert from 'node:assert/strict';
import { openStore, createUser, issue } from '../store.mjs';
import { createApp } from '../app.mjs';

const TOKEN = 'service-token-for-tests';
async function lane(t, extra = {}) {
  const db = openStore(':memory:');
  createUser(db, { id: 'alex', family: 'one', email: 'alex@example.test', name: 'alex' });
  createUser(db, { id: 'sam', family: 'one', email: 'sam@example.test', name: 'sam' });
  const device = { alex: issue(db, 'alex', 'device', 'phone', 3600000), sam: issue(db, 'sam', 'device', 'phone', 3600000) };
  const app = createApp(db, { origin: 'http://localhost', demo: true, serviceToken: TOKEN, serviceOwner: 'Alex@Example.test', ...extra });
  await new Promise(r => app.listen(0, '127.0.0.1', r));
  t.after(async () => { await new Promise(r => app.close(r)); db.close(); });
  const base = `http://127.0.0.1:${app.address().port}/api/apple/`;
  const sync = async (user, health, deleted = []) => (await fetch(base + 'sync', { method: 'POST', headers: { Authorization: `Bearer ${device[user]}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ health, locations: [], deleted }) })).status;
  const exportPage = async (query = '', token = TOKEN) => { const r = await fetch(base + 'export' + query, { headers: { Authorization: `Bearer ${token}` } }); return { status: r.status, body: await r.json() }; };
  return { db, sync, exportPage };
}
const iso = s => new Date(Date.now() - s * 1000).toISOString();
const hr = (id, secondsAgo, value = 60) => ({ id, kind: 'heart_rate', start: iso(secondsAgo), end: iso(secondsAgo), value, unit: 'bpm', source: 'Watch', tz: 'Europe/London' });

test('the export is the configured owner\'s only, and needs the service token', async t => {
  const { sync, exportPage } = await lane(t);
  assert.equal(await sync('alex', [hr('a1', 600)]), 200);
  assert.equal(await sync('sam', [hr('s1', 600)]), 200);
  assert.equal((await exportPage('', 'wrong')).status, 401);
  const { body } = await exportPage();
  assert.deepEqual(body.records.map(r => r.id), ['a1']);
  assert.equal(body.earliest, body.records[0].start, 'earliest is the owner\'s oldest record');
  assert.equal((await exportPage('?user=sam')).status, 400);
});

test('earliest skips the legacy daily steps row and workout parts, which start hours before the phone\'s own history', async t => {
  const { sync, exportPage } = await lane(t);
  const steps = { id: 'daily-steps', kind: 'steps', start: iso(200000), end: iso(200000 - 86400), value: 4000, unit: 'count', source: 'HealthKit statistics' };
  await sync('alex', [steps, hr('a1', 600)]);
  const { body } = await exportPage();
  assert.equal(body.earliest, body.records.find(r => r.kind === 'heart_rate').start, 'earliest must not be pulled back by the legacy steps row');
});

test('an unconfigured lane has no export', async t => {
  const { exportPage } = await lane(t, { serviceToken: undefined, serviceOwner: undefined });
  assert.equal((await exportPage()).status, 404);
});

test('paging by cursor returns every record exactly once and never splits an upload', async t => {
  const { sync, exportPage } = await lane(t);
  await sync('alex', Array.from({ length: 30 }, (_, i) => hr(`a${i}`, 900 - i)));
  await new Promise(r => setTimeout(r, 5));
  await sync('alex', Array.from({ length: 30 }, (_, i) => hr(`b${i}`, 800 - i)));
  const first = await exportPage('?after=0&limit=10');
  assert.equal(first.body.records.length, 30, 'the first upload comes whole even though limit=10');
  assert.equal(first.body.more, true);
  const second = await exportPage(`?after=${first.body.next}&limit=10`);
  assert.deepEqual(second.body.records.map(r => r.id).sort(), Array.from({ length: 30 }, (_, i) => `b${i}`).sort());
  assert.equal(second.body.more, false);
  const third = await exportPage(`?after=${second.body.next}`);
  assert.equal(third.body.records.length, 0);
});

test('a workout travels whole, re-sent when its route arrives later', async t => {
  const { sync, exportPage } = await lane(t);
  const start = iso(4000), end = iso(400), t0 = Math.floor(Date.now() / 1000) - 3900;
  await sync('alex', [{ id: 'W1', kind: 'workout', start, end, value: 3600, unit: 'seconds', activity: 'Outdoor Run', source: 'Watch', indoor: false },
    { id: 'series:W1:heart_rate:0', kind: 'workout_series', start, end, source: 'Watch', workout: 'W1', metric: 'heart_rate', unit: 'bpm', chunk: 0, points: [[t0, 120], [t0 + 5, 125]] }]);
  const first = await exportPage('?after=0');
  assert.equal(first.body.workouts.length, 1);
  assert.deepEqual(first.body.workouts[0].route, []);
  assert.deepEqual(first.body.workouts[0].series.heart_rate.points, [[t0, 120], [t0 + 5, 125]]);
  await new Promise(r => setTimeout(r, 5));
  await sync('alex', [{ id: 'route:W1:1', kind: 'workout_route', start, end, source: 'Watch', workout: 'W1', chunk: 1, points: [[t0 + 10, 51.5002, -0.1, 11, 3, 5]] },
    { id: 'route:W1:0', kind: 'workout_route', start, end, source: 'Watch', workout: 'W1', chunk: 0, points: [[t0, 51.5, -0.1, 10, 3, 5]] }]);
  const second = await exportPage(`?after=${first.body.next}`);
  assert.equal(second.body.workouts.length, 1);
  assert.deepEqual(second.body.workouts[0].route.map(p => p[0]), [t0, t0 + 10], 'chunks are joined in chunk order');
  assert.equal(second.body.workouts[0].workout.id, 'W1');
});

test('tombstones ride the same cursor', async t => {
  const { sync, exportPage } = await lane(t);
  await sync('alex', [hr('a1', 600)]);
  const first = await exportPage('?after=0');
  await new Promise(r => setTimeout(r, 5));
  await sync('alex', [], ['a1']);
  const second = await exportPage(`?after=${first.body.next}`);
  assert.deepEqual(second.body.tombstones.map(s => [s.id, s.kind]), [['a1', 'heart_rate']]);
});

test('an owner upload rings the doorbell once per burst; a family upload does not', async t => {
  const DOORBELL_TOKEN = 'doorbell-token-for-tests';
  const calls = [];
  let release;
  const gate = new Promise(r => { release = r; });
  const fetchImpl = async (url, init) => { calls.push([url, init.headers.authorization]); await gate; return { ok: true }; };
  const { sync } = await lane(t, { doorbellUrl: 'https://example.test/api/health/apple/companion/pull', doorbellToken: DOORBELL_TOKEN, fetchImpl });
  await sync('alex', [hr('a1', 600)]);
  await sync('alex', [hr('a2', 500)]);
  await sync('alex', [hr('a3', 400)]);
  await sync('sam', [hr('s1', 400)]);
  release();
  await new Promise(r => setTimeout(r, 20));
  assert.equal(calls.length, 2, 'one ring, plus one follow-up for everything that arrived while it was in flight');
  // The doorbell carries its OWN ring-only token, never the service token
  // that /health's read lane accepts (R5) — a leaked ring can only trigger a
  // pull, not a read.
  assert.deepEqual(calls[0], ['https://example.test/api/health/apple/companion/pull', `Bearer ${DOORBELL_TOKEN}`]);
});

test('the page query is answered from the cursor index, not a scan of the owner\'s history', t => {
  const db = openStore(':memory:');
  t.after(() => db.close());
  // The exact SQL export.mjs's page query runs (export.mjs's first `SELECT`).
  const plan = db.prepare(`EXPLAIN QUERY PLAN SELECT id, kind, payload, received FROM health WHERE user_id=? AND received>? ORDER BY received, id LIMIT ?`).all('alex', '1970-01-01T00:00:00.000Z', 10);
  const detail = plan.map(r => r.detail).join('\n');
  assert.match(detail, /health_user_received/, 'the page query should search the received index, not scan by user_id alone');
  assert.doesNotMatch(detail, /USE TEMP B-TREE/, 'the ORDER BY should be satisfied by the index, not a temp sort');
});

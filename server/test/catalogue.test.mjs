import test from 'node:test';
import assert from 'node:assert/strict';
import { catalogue, KINDS, validateHealthRecord, ROUTE_POINT_LIMIT } from '../catalogue.mjs';

const at = (offsetS = 0) => new Date(Date.now() - 3600_000 + offsetS * 1000).toISOString();
const base = (kind, extra = {}) => ({ id: `${kind}-1`, kind, start: at(), end: at(60), source: 'Watch', ...extra });

test('every group kind is catalogued and every catalogued kind has a group', () => {
  const grouped = Object.values(catalogue.groups).flatMap(g => g.kinds);
  assert.deepEqual(new Set(grouped), KINDS);
  for (const legacy of Object.keys(catalogue.legacyKinds)) assert.ok(KINDS.has(legacy), legacy);
});

test('a sample must carry the catalogued unit and stay inside its bounds', () => {
  assert.equal(validateHealthRecord(base('heart_rate_variability', { value: 48.2, unit: 'ms' })).value, 48.2);
  assert.throws(() => validateHealthRecord(base('heart_rate_variability', { value: 48.2, unit: 'bpm' })), { status: 400 });
  assert.throws(() => validateHealthRecord(base('oxygen_saturation', { value: 0.97, unit: '%' })), { status: 400 });
});

test('unknown kinds and unknown fields are refused', () => {
  assert.throws(() => validateHealthRecord(base('blood_glucose', { value: 5, unit: 'mmol/L' })), { status: 400 });
  assert.throws(() => validateHealthRecord(base('heart_rate', { value: 60, unit: 'bpm', mood: 'fine' })), { status: 400 });
});

test('sleep keeps the stage vocabulary', () => {
  assert.equal(validateHealthRecord(base('sleep', { stage: 'rem' })).stage, 'rem');
  assert.throws(() => validateHealthRecord(base('sleep', { stage: 'napping' })), { status: 400 });
});

test('a workout carries optional depth fields, each bounded', () => {
  const w = validateHealthRecord(base('workout', {
    value: 1800, unit: 'seconds', activity: 'Outdoor Run', distance: 5000, energy: 400, tz: 'Europe/London',
    indoor: false, elevation: 42, mets: 9.1, temperature: 14.5, humidity: 70, effort: 7,
    events: [{ type: 'pause', start: at(600), end: at(660) }, { type: 'lap', start: at(0), end: at(300) }],
  }));
  assert.equal(w.events.length, 2);
  assert.throws(() => validateHealthRecord(base('workout', { value: 1800, unit: 'seconds', activity: 'Run', effort: 11 })), { status: 400 });
  assert.throws(() => validateHealthRecord(base('workout', { value: 1800, unit: 'seconds', activity: 'Run', events: [{ type: 'nap', start: at(), end: at() }] })), { status: 400 });
});

test('route chunks name their workout and stay under the point limit', () => {
  const point = [Math.floor(Date.now() / 1000) - 3000, 51.5, -0.12, 20, 2.8, 5];
  const ok = validateHealthRecord(base('workout_route', { workout: 'W1', chunk: 0, points: [point, point] }));
  assert.equal(ok.points.length, 2);
  assert.throws(() => validateHealthRecord(base('workout_route', { workout: 'W1', chunk: 0, points: Array(ROUTE_POINT_LIMIT + 1).fill(point) })), { status: 400 });
  assert.throws(() => validateHealthRecord(base('workout_route', { workout: 'W1', chunk: 0, points: [[1, 91, 0, null, null, null]] })), { status: 400 });
});

test('series chunks must use a catalogued series metric', () => {
  const t = Math.floor(Date.now() / 1000) - 3000;
  assert.equal(validateHealthRecord(base('workout_series', { workout: 'W1', metric: 'power', unit: 'W', chunk: 0, points: [[t, 250]] })).metric, 'power');
  assert.throws(() => validateHealthRecord(base('workout_series', { workout: 'W1', metric: 'lactate', unit: 'mM', chunk: 0, points: [[t, 2]] })), { status: 400 });
  assert.throws(() => validateHealthRecord(base('workout_series', { workout: 'W1', metric: 'power', unit: 'kW', chunk: 0, points: [[t, 2]] })), { status: 400 });
});

test('tz, when present, must be an IANA-looking zone', () => {
  assert.equal(validateHealthRecord(base('heart_rate', { value: 60, unit: 'bpm', tz: 'America/New_York' })).tz, 'America/New_York');
  assert.throws(() => validateHealthRecord(base('heart_rate', { value: 60, unit: 'bpm', tz: '<script>' })), { status: 400 });
});

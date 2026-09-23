// The ONE list of health kinds, shared with the iPhone app's tests (P2 loads
// the same JSON), so a kind the phone sends and a kind this server accepts
// cannot drift apart without a red test on one side.
import { readFileSync } from 'node:fs';

export const catalogue = JSON.parse(readFileSync(new URL('./health-catalogue.json', import.meta.url), 'utf8'));
export const KINDS = new Set(Object.keys(catalogue.kinds));
export const SERIES_UNITS = catalogue.series;
export const ROUTE_POINT_LIMIT = 2000;
export const SERIES_POINT_LIMIT = 5000;
export const EVENT_LIMIT = 500;

const FIELDS = ['id', 'kind', 'start', 'end', 'value', 'unit', 'source', 'stage', 'activity', 'distance', 'energy', 'tz',
  'indoor', 'elevation', 'mets', 'temperature', 'humidity', 'effort', 'events', 'workout', 'metric', 'chunk', 'points'];
const iso = v => typeof v === 'string' && /^\d{4}-\d\d-\d\dT/.test(v) && Number.isFinite(Date.parse(v));
const bounded = (x, lo, hi) => typeof x === 'number' && Number.isFinite(x) && x >= lo && x <= hi;
const optional = (x, lo, hi) => x == null || bounded(x, lo, hi);
const string = (x, max = 200) => typeof x === 'string' && x.length > 0 && x.length <= max;
const zone = x => x == null || (typeof x === 'string' && /^[A-Za-z_]+(?:\/[A-Za-z0-9_+\-]+){0,2}$/.test(x) && x.length <= 64);
function fail(message) { throw Object.assign(new Error(message), { status: 400 }); }
const epoch = t => Number.isInteger(t) && t > 1e9 && t < Date.now() / 1000 + 300;

export function validateHealthRecord(r) {
  if (!r || typeof r !== 'object' || Array.isArray(r) || Object.keys(r).some(k => !FIELDS.includes(k))) fail('Unexpected fields');
  const spec = catalogue.kinds[r.kind];
  if (!spec) fail('Unknown health category');
  if (!string(r.id) || !iso(r.start) || !iso(r.end) || Date.parse(r.end) < Date.parse(r.start) || Date.parse(r.end) > Date.now() + 300000 || !string(r.source)) fail('Invalid health record');
  if (!zone(r.tz)) fail('Invalid time zone');
  switch (spec.shape) {
    case 'sample': case 'hourly': case 'event': case 'daily': case 'workout':
      if (!bounded(r.value, spec.min, spec.max) || r.unit !== spec.unit) fail(`Invalid ${r.kind}`);
      break;
    case 'sleep':
      if (!catalogue.sleepStages.includes(r.stage)) fail('Invalid sleep stage');
      break;
    case 'route':
      if (!string(r.workout, 64) || !Number.isInteger(r.chunk) || r.chunk < 0 || !Array.isArray(r.points) || !r.points.length || r.points.length > ROUTE_POINT_LIMIT) fail('Invalid route chunk');
      for (const p of r.points) {
        if (!Array.isArray(p) || p.length !== 6 || !epoch(p[0]) || !bounded(p[1], -90, 90) || !bounded(p[2], -180, 180) || !optional(p[3], -500, 9000) || !optional(p[4], 0, 400) || !optional(p[5], 0, 10000)) fail('Invalid route point');
      }
      break;
    case 'series':
      if (!string(r.workout, 64) || !Number.isInteger(r.chunk) || r.chunk < 0 || SERIES_UNITS[r.metric] === undefined || r.unit !== SERIES_UNITS[r.metric] || !Array.isArray(r.points) || !r.points.length || r.points.length > SERIES_POINT_LIMIT) fail('Invalid series chunk');
      for (const p of r.points) if (!Array.isArray(p) || p.length !== 2 || !epoch(p[0]) || !bounded(p[1], -1e6, 1e6)) fail('Invalid series point');
      break;
  }
  if (spec.shape === 'workout') {
    if (!string(r.activity, 80)) fail('Invalid workout');
    if (!optional(r.distance, 0, 10000000) || !optional(r.energy, 0, 100000) || !optional(r.elevation, 0, 20000) || !optional(r.mets, 0, 30)
      || !optional(r.temperature, -60, 70) || !optional(r.humidity, 0, 100) || !optional(r.effort, 1, 10)
      || (r.indoor != null && typeof r.indoor !== 'boolean')) fail('Invalid workout');
    if (r.events != null) {
      if (!Array.isArray(r.events) || r.events.length > EVENT_LIMIT) fail('Invalid workout events');
      for (const e of r.events) if (!e || !catalogue.workoutEventTypes.includes(e.type) || !iso(e.start) || !iso(e.end) || Object.keys(e).some(k => !['type', 'start', 'end'].includes(k))) fail('Invalid workout events');
    }
  } else if (r.distance != null || r.energy != null || r.events != null || r.activity != null) fail('Unexpected fields');
  return { ...r, start: new Date(r.start).toISOString(), end: new Date(r.end).toISOString() };
}

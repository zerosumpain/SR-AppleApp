import test from 'node:test';
import assert from 'node:assert/strict';
import { SEGMENT_GAP_SECONDS, activitiesOf, binSeries, dayBounds, dayIndex, haversineMetres, localDate, movingSeconds, recordedMetres, segmentsOf } from '../movement.mjs';

/** [lng, lat, epochSeconds, accuracy, moving, speed] */
const point = (lng, lat, t, moving = 1) => [lng, lat, t, 5, moving, 1.4];

test('a track splits where the phone stopped recording, not where it stopped moving', () => {
  const base = 1758000000;
  const points = [
    point(-1.57, 54.52, base),
    point(-1.571, 54.521, base + 30),
    point(-1.572, 54.522, base + 60),
    // Eight hours of nothing: the gate let iOS suspend the app overnight.
    point(-1.58, 54.53, base + 60 + 8 * 3600),
    point(-1.581, 54.531, base + 90 + 8 * 3600),
  ];
  assert.deepEqual(segmentsOf(points), [[0, 2], [3, 4]]);
  // A pause at a junction is not a new segment.
  assert.deepEqual(segmentsOf([point(0, 51, base), point(0, 51, base + SEGMENT_GAP_SECONDS)]), [[0, 1]]);
  assert.deepEqual(segmentsOf([point(0, 51, base), point(0, 51, base + SEGMENT_GAP_SECONDS + 1)]), [[0, 0], [1, 1]]);
  assert.deepEqual(segmentsOf([]), []);
  assert.deepEqual(segmentsOf([point(0, 51, base)]), [[0, 0]]);
});

test('distance is measured along recorded fixes and never across a gap', () => {
  const base = 1758000000;
  const near = [point(-1.57, 54.52, base), point(-1.57, 54.521, base + 30)];
  const oneHop = recordedMetres(near);
  assert.ok(oneHop > 100 && oneHop < 120, `expected ~111 m, got ${oneHop}`);

  // The same two points, but with a mile of separation crossed while asleep.
  const withGap = [...near, point(-1.60, 54.55, base + 30 + 4 * 3600), point(-1.601, 54.551, base + 60 + 4 * 3600)];
  const total = recordedMetres(withGap);
  // Only the two walked hops count; the jump between segments is not a journey
  // anybody took, and adding it would report a distance that never happened.
  assert.ok(total < oneHop * 2 + 20, `gap was counted as travel: ${total}`);
  assert.ok(total > oneHop, 'the second segment was dropped entirely');
});

test('a hop of a known size measures the size it is', () => {
  // One minute of latitude is a nautical mile, near enough, anywhere.
  const metres = haversineMetres([0, 51], [0, 51 + 1 / 60]);
  assert.ok(Math.abs(metres - 1852) < 5, `expected ~1852 m, got ${metres}`);
});

test('moving time counts only the pairs the phone called movement', () => {
  const base = 1758000000;
  const points = [point(0, 51, base, 0), point(0, 51, base + 60, 0), point(0, 51, base + 120, 1), point(0, 51, base + 180, 1)];
  assert.equal(movingSeconds(points), 120);
});

test('days are bucketed in the reader timezone, not UTC', () => {
  // 00:30 British Summer Time on 22 September is 23:30 UTC on the 21st. A
  // walk then belongs to the 22nd, which is the day the reader lived it.
  const justAfterMidnightBST = Date.parse('2026-09-21T23:30:00Z') / 1000;
  assert.equal(localDate(justAfterMidnightBST, 0), '2026-09-21');
  assert.equal(localDate(justAfterMidnightBST, -60), '2026-09-22');

  const [from, to] = dayBounds('2026-09-22', -60);
  assert.equal(new Date(from * 1000).toISOString(), '2026-09-21T23:00:00.000Z');
  assert.equal(to - from, 86400);
  assert.ok(justAfterMidnightBST >= from && justAfterMidnightBST < to);
});

test('the day index reports each day once, newest first, with its own distance', () => {
  const day = (iso, n) => Array.from({ length: n }, (_, i) => point(-1.57 + i / 1000, 54.52, Date.parse(iso) / 1000 + i * 30));
  const points = [...day('2026-09-20T09:00:00Z', 3), ...day('2026-09-22T09:00:00Z', 4)];
  const index = dayIndex(points, 0);
  assert.deepEqual(index.map((d) => d.date), ['2026-09-22', '2026-09-20']);
  assert.deepEqual(index.map((d) => d.fixes), [4, 3]);
  assert.ok(index[0].metres > 0);
  // A day nobody recorded is absent rather than zero: the phone was off, which
  // is not the same as having stood still all day.
  assert.equal(index.find((d) => d.date === '2026-09-21'), undefined);
});

test('binning averages inside a bucket and leaves an empty one out', () => {
  const from = 1758000000;
  const records = [
    { start: new Date((from + 10) * 1000).toISOString(), value: 60 },
    { start: new Date((from + 20) * 1000).toISOString(), value: 80 },
    // Nothing in the second bucket — the watch was off the wrist.
    { start: new Date((from + 2 * 300 + 5) * 1000).toISOString(), value: 100 },
    // Outside the window entirely.
    { start: new Date((from - 60) * 1000).toISOString(), value: 999 },
  ];
  const { seconds, bins } = binSeries(records, from, from + 900, 3);
  assert.equal(seconds, 300);
  assert.deepEqual(bins, [[from, 70], [from + 600, 100]]);
});

test('an activity ends where MOVEMENT stops, not where the data does', () => {
  const base = 1758000000;
  const walk = (from, n, step = 30) => Array.from({ length: n }, (_, i) => [-1.57 + (from + i) / 3000, 54.52, base + from * 60 + i * step, 5, 1, 1.4]);
  // Out, then an hour at a desk the phone kept SAMPLING through — no gap
  // anywhere over ten minutes — then home again.
  const desk = Array.from({ length: 30 }, (_, i) => [-1.53, 54.52, base + 1200 + i * 120, 5, 0, 0]);
  const points = [...walk(0, 40), ...desk, ...walk(80, 40)];
  const activities = activitiesOf(points);
  assert.deepEqual(activities.map(a => a.kind), ['journey', 'stop', 'journey']);
  assert.equal(activities[1].seconds > 3000, true, 'the stop should be about an hour');
  // The gap rule alone cannot see this: every fix is within ten minutes of the
  // last one, so the whole day is a single run of continuous recording.
  assert.equal(segmentsOf(points).length, 1);
});

test('standing still is a stop, not a list of one-point activities', () => {
  const base = 1758000000;
  // A real morning: three lone stationary fixes while the phone dozed, then a
  // walk. The old rule called that four segments, three of them nought metres.
  const still = [0, 1130, 2460].map((offset) => [-1.57, 54.52, base + offset, 12, 0, 0]);
  const walk = Array.from({ length: 30 }, (_, i) => [-1.57 + i / 3000, 54.52, base + 4000 + i * 35, 4, 1, 1.5]);
  const points = [...still, ...walk];
  assert.equal(segmentsOf(points).length, 4);
  const activities = activitiesOf(points);
  assert.deepEqual(activities.map(a => a.kind), ['stop', 'journey']);
  assert.equal(activities[0].fixes, 4, 'the stop runs up to the fix the walk starts from');
  assert.equal(activities[1].metres > 500, true);
});

test('a twitch is not a journey, and a day with no movement is one stop', () => {
  const base = 1758000000;
  // Four fixes of GPS drift at a window: flagged moving, going nowhere.
  const drift = Array.from({ length: 4 }, (_, i) => [-1.57 + i / 400000, 54.52, base + i * 30, 30, 1, 0.2]);
  assert.deepEqual(activitiesOf(drift).map(a => a.kind), ['stop']);
  const parked = Array.from({ length: 6 }, (_, i) => [-1.57, 54.52, base + i * 400, 8, 0, 0]);
  assert.deepEqual(activitiesOf(parked).map(a => a.kind), ['stop']);
  assert.deepEqual(activitiesOf([]), []);
  assert.deepEqual(activitiesOf([[0, 51, base, 5, 1, 1]]), []);
});

test('a stop is pinned by the median of its fixes, not dragged by one bad one', () => {
  const base = 1758000000;
  const walkIn = Array.from({ length: 20 }, (_, i) => [-1.60 + i / 2000, 54.52, base + i * 35, 4, 1, 1.5]);
  const settled = [-1.59, 54.52];
  const held = [
    [settled[0], settled[1], base + 5000, 6, 0, 0],
    [settled[0], settled[1], base + 5600, 6, 0, 0],
    // One fix half a kilometre away, which a mean would happily average in.
    [settled[0] + 0.008, settled[1], base + 6200, 180, 0, 0],
    [settled[0], settled[1], base + 6800, 6, 0, 0],
  ];
  const stops = activitiesOf([...walkIn, ...held]).filter(a => a.kind === 'stop');
  assert.equal(stops.length, 1);
  assert.equal(stops[0].lng, settled[0]);
});

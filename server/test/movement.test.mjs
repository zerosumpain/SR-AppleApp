import test from 'node:test';
import assert from 'node:assert/strict';
import { SEGMENT_GAP_SECONDS, binSeries, dayBounds, dayIndex, haversineMetres, localDate, movingSeconds, recordedMetres, segmentsOf } from '../movement.mjs';

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

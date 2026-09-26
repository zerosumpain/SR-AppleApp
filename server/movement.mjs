/**
 * Pure geometry and binning over a recorded track.
 *
 * No database, no network, no HTTP — so the day index, the day itself and the
 * tests all share ONE definition of what "a day's movement" means. The handler
 * in `app.mjs` is then only the URL contract, the same way `$lib/news/desk.ts`
 * is to the news page.
 *
 * A point is a TUPLE, matching what goes on the wire:
 *
 *     [lng, lat, epochSeconds, accuracyMetres, moving (0|1), speedMetresPerSecond]
 *
 * Tuple rather than object because a month of fixes is roughly 40% smaller that
 * way and the shape never varies — the same reasoning, and the same ordering
 * convention (lng first, as GeoJSON has it), as the site's own track store.
 */

const EARTH_RADIUS_M = 6371008.8;

/**
 * Longer than this between two fixes and the phone was ASLEEP, not walking.
 *
 * This constant is the difference between an honest map and a lie. The motion
 * gate lets iOS suspend the app while you are still, so a day's track is bursts
 * of fixes 30 seconds apart separated by hours of nothing — in production the
 * median gap is 37 seconds and the largest is eight and a half hours, which is
 * a night's sleep. Joining those two ends with a straight line draws a journey
 * that never happened, straight through whatever is between the two points.
 *
 * Ten minutes is comfortably longer than the app's own stationary recording
 * interval and far shorter than any real gate-induced sleep, so it separates
 * "paused at a junction" from "the sensor was off".
 */
export const SEGMENT_GAP_SECONDS = 600;

/** Great-circle distance in metres between two [lng, lat] pairs. */
export function haversineMetres(a, b) {
  const φ1 = (a[1] * Math.PI) / 180;
  const φ2 = (b[1] * Math.PI) / 180;
  const Δφ = ((b[1] - a[1]) * Math.PI) / 180;
  const Δλ = ((b[0] - a[0]) * Math.PI) / 180;
  const sinΔφ = Math.sin(Δφ / 2);
  const sinΔλ = Math.sin(Δλ / 2);
  const h = sinΔφ * sinΔφ + Math.cos(φ1) * Math.cos(φ2) * sinΔλ * sinΔλ;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * Split a chronological list of points into runs of continuous recording.
 *
 * Returns inclusive `[firstIndex, lastIndex]` pairs. A lone fix between two
 * long gaps is its own one-point segment: it is a real observation, it just has
 * no line to draw.
 */
export function segmentsOf(points, gapSeconds = SEGMENT_GAP_SECONDS) {
  const segments = [];
  let start = 0;
  for (let i = 1; i < points.length; i++) {
    if (points[i][2] - points[i - 1][2] > gapSeconds) {
      segments.push([start, i - 1]);
      start = i;
    }
  }
  if (points.length) segments.push([start, points.length - 1]);
  return segments;
}

/**
 * Distance along the RECORDED track, in metres.
 *
 * Summed within segments only, never across a gap. That makes the number an
 * undercount whenever the phone slept through a journey — which is the honest
 * direction to be wrong in, and why nothing here calls it "distance travelled".
 */
export function recordedMetres(points, segments = segmentsOf(points)) {
  let total = 0;
  for (const [from, to] of segments) {
    for (let i = from + 1; i <= to; i++) total += haversineMetres(points[i - 1], points[i]);
  }
  return total;
}

/** Seconds spanned by segments in which the phone reported itself moving. */
export function movingSeconds(points, segments = segmentsOf(points)) {
  let total = 0;
  for (const [from, to] of segments) {
    for (let i = from + 1; i <= to; i++) {
      if (points[i][4] || points[i - 1][4]) total += points[i][2] - points[i - 1][2];
    }
  }
  return total;
}

/**
 * The calendar date an instant falls on, for a reader `offsetMinutes` from UTC.
 *
 * `offsetMinutes` is `Date.prototype.getTimezoneOffset()` as the BROWSER
 * reports it — minutes BEHIND UTC, so British Summer Time is -60. Local time is
 * therefore UTC minus the offset.
 *
 * Bucketing has to happen in the reader's timezone or a walk that started at
 * half past midnight in summer appears on the previous day. One offset is used
 * for the whole window, so across a clock change (late October here) an hour of
 * fixes lands on the neighbouring day. Twice a year, for one hour, on a private
 * movement map: named rather than engineered around.
 */
export function localDate(epochSeconds, offsetMinutes) {
  return new Date((epochSeconds - offsetMinutes * 60) * 1000).toISOString().slice(0, 10);
}

/** Start and end instants of a local calendar date, as epoch seconds. */
export function dayBounds(date, offsetMinutes) {
  const start = Date.parse(`${date}T00:00:00Z`) / 1000 + offsetMinutes * 60;
  return [start, start + 86400];
}

/**
 * One row per local day that has a fix, newest first.
 *
 * Days with nothing are omitted rather than returned empty: the strip that
 * reads this draws the whole retention window itself, and a day with no fixes
 * is a day the phone was off, not a day with a zero in it.
 */
export function dayIndex(points, offsetMinutes) {
  const byDate = new Map();
  for (const point of points) {
    const date = localDate(point[2], offsetMinutes);
    if (!byDate.has(date)) byDate.set(date, []);
    byDate.get(date).push(point);
  }
  return [...byDate.entries()]
    .map(([date, day]) => {
      const segments = segmentsOf(day);
      return {
        date,
        fixes: day.length,
        journeys: activitiesOf(day).filter((a) => a.kind === 'journey').length,
        metres: Math.round(recordedMetres(day, segments)),
        movingSeconds: movingSeconds(day, segments),
        firstAt: day[0][2],
        lastAt: day[day.length - 1][2],
      };
    })
    .sort((a, b) => b.date.localeCompare(a.date));
}

/**
 * Below these, a run of fixes is GPS twitching rather than somebody going
 * somewhere. A walk to the postbox clears both comfortably.
 */
export const MIN_JOURNEY_METRES = 60;
export const MIN_JOURNEY_SECONDS = 60;

/**
 * The day as a list of JOURNEYS and the STOPS between them.
 *
 * ## Why this is not `segmentsOf`
 *
 * A segment is a run of continuous RECORDING, and that is the right thing to
 * decide where a line may be drawn. It is the wrong thing to call an activity,
 * for two reasons that both showed up in one real day:
 *
 *  - A stop the phone kept sampling through is invisible to it. Standing at a
 *    desk from nine to five with a fix every two minutes has no gap over ten
 *    minutes anywhere in it, so the walk in and the walk home come out as ONE
 *    segment — a single journey that never happened.
 *  - A stop the phone slept through produces lone stationary fixes, and each
 *    becomes a "segment" of one point and nought metres. A real day came out
 *    as seven segments, five of which were somebody standing still.
 *
 * So a break is judged on MOVEMENT, not on the presence of data. Two fixes are
 * joined into a journey when they are close enough in time AND at least one of
 * them reported moving — the flag the phone's own movement policy sets, which
 * is the only thing that can tell a parked car from a slow one.
 *
 * Returns journeys and stops interleaved in time, covering first fix to last.
 * A stop SHARES its end fixes with the journeys either side: the point you
 * arrive at is the point you later set off from.
 */
export function activitiesOf(points, { breakSeconds = SEGMENT_GAP_SECONDS, minMetres = MIN_JOURNEY_METRES, minSeconds = MIN_JOURNEY_SECONDS } = {}) {
  if (points.length < 2) return [];
  const travelling = (a, b) => b[2] - a[2] <= breakSeconds && Boolean(a[4] || b[4]);
  const runs = [];
  let open = null;
  for (let i = 1; i < points.length; i++) {
    if (travelling(points[i - 1], points[i])) open ??= i - 1;
    else if (open !== null) { runs.push([open, i - 1]); open = null; }
  }
  if (open !== null) runs.push([open, points.length - 1]);

  const journeys = runs.filter(([first, last]) =>
    points[last][2] - points[first][2] >= minSeconds &&
    recordedMetres(points.slice(first, last + 1)) >= minMetres);

  const stop = (first, last) => {
    // The median of each coordinate rather than the mean: one wild fix in a
    // stationary cluster should not drag the pin down the road.
    const mid = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
    const held = points.slice(first, last + 1);
    return {
      kind: 'stop', first, last,
      from: points[first][2], to: points[last][2],
      seconds: points[last][2] - points[first][2],
      fixes: held.length,
      lng: mid(held.map((p) => p[0])),
      lat: mid(held.map((p) => p[1])),
    };
  };

  const activities = [];
  let cursor = 0;
  for (const [first, last] of journeys) {
    if (first > cursor) activities.push(stop(cursor, first));
    activities.push({
      kind: 'journey', first, last,
      from: points[first][2], to: points[last][2],
      seconds: points[last][2] - points[first][2],
      metres: Math.round(recordedMetres(points.slice(first, last + 1))),
      fixes: last - first + 1,
    });
    cursor = last;
  }
  if (cursor < points.length - 1) activities.push(stop(cursor, points.length - 1));
  return activities;
}

/**
 * Average a series of instantaneous readings into fixed-width buckets.
 *
 * EMPTY BUCKETS ARE OMITTED, not returned as null. A month of heart rate is
 * ~24,000 records and no chart can draw them, but the gaps between them are
 * information — the watch was off the wrist — and a line drawn straight across
 * one would invent a reading. The caller gets `seconds` back so it can tell a
 * missing bucket from an adjacent one.
 *
 * @param records `{ start: ISO string, value: number }`
 * @returns `{ seconds, bins: [[bucketStartEpochSeconds, mean], ...] }`
 */
export function binSeries(records, fromSeconds, toSeconds, buckets) {
  const seconds = Math.max(1, Math.round((toSeconds - fromSeconds) / buckets));
  const totals = new Map();
  for (const record of records) {
    const at = Date.parse(record.start) / 1000;
    if (!Number.isFinite(at) || at < fromSeconds || at >= toSeconds) continue;
    const bucket = Math.floor((at - fromSeconds) / seconds);
    const running = totals.get(bucket) ?? { sum: 0, count: 0 };
    running.sum += record.value;
    running.count++;
    totals.set(bucket, running);
  }
  return {
    seconds,
    bins: [...totals.entries()]
      .sort((a, b) => a[0] - b[0])
      .map(([bucket, { sum, count }]) => [fromSeconds + bucket * seconds, Math.round(sum / count)]),
  };
}

/** Sleep stages that are asleep, as opposed to in bed or awake. */
export const ASLEEP_STAGES = ['asleep', 'core', 'deep', 'rem'];

/**
 * Total time covered by a set of `[start, end]` spans (epoch seconds), clipped
 * to a window and counted ONCE.
 *
 * A union rather than a sum because sleep stages overlap across sources, so
 * adding a watch's `deep` to a phone's `asleep` reports a night longer than the
 * night was. Clipped because a stage is selected when it overlaps the window,
 * and the part of it that fell outside belongs to the neighbouring day.
 */
export function unionSeconds(spans, from, to) {
  let total = 0;
  let covered = from;
  for (const [start, end] of [...spans].sort((a, b) => a[0] - b[0])) {
    const open = Math.max(start, from, covered);
    const close = Math.min(end, to);
    if (close > open) { total += close - open; covered = close; }
  }
  return total;
}

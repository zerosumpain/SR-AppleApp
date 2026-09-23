// The owner's health, handed to /health's COPY (spec E1/E2). Paged by the
// server's own `received` clock, never by HealthKit's dates: a late Watch sync
// arrives with old dates and a new `received`, and must still be handed on.
const PARTS = "kind IN ('workout_route','workout_series')";

export function exportPage(db, userId, { after, limit }) {
  const afterISO = new Date(after).toISOString();
  let rows = db.prepare(`SELECT id, kind, payload, received FROM health WHERE user_id=? AND received>? ORDER BY received, id LIMIT ?`).all(userId, afterISO, limit + 1);
  const truncated = rows.length > limit;
  let end;
  if (truncated) {
    // Never split one upload across pages: a batch shares one `received`, and a
    // cursor taken from the middle of it would skip the rest for good.
    end = rows[limit - 1].received;
    rows = rows.filter(r => r.received < end).concat(db.prepare('SELECT id, kind, payload, received FROM health WHERE user_id=? AND received=? ORDER BY id').all(userId, end));
  } else {
    const lastStone = db.prepare('SELECT max(deleted) d FROM health_deleted WHERE user_id=? AND deleted>?').get(userId, afterISO).d;
    end = [rows.at(-1)?.received, lastStone, afterISO].filter(Boolean).sort().at(-1);
  }
  // `more` asks "is there anything after THIS page's end", not "did the
  // over-fetch spill past the limit" — those disagree exactly when a whole
  // truncated upload is folded back in (R1): the over-fetch can be bigger than
  // `limit` while nothing on either table sits beyond `end`.
  const moreHealth = db.prepare('SELECT 1 FROM health WHERE user_id=? AND received>? LIMIT 1').get(userId, end);
  const moreDeleted = db.prepare('SELECT 1 FROM health_deleted WHERE user_id=? AND deleted>? LIMIT 1').get(userId, end);
  const more = !!(moreHealth || moreDeleted);
  const records = [], touched = new Set();
  for (const r of rows) {
    const p = JSON.parse(r.payload);
    if (r.kind === 'workout') touched.add(r.id);
    else if (r.kind === 'workout_route' || r.kind === 'workout_series') touched.add(p.workout);
    else records.push(p);
  }
  const workouts = [];
  for (const id of touched) {
    const head = db.prepare("SELECT payload FROM health WHERE user_id=? AND id=? AND kind='workout'").get(userId, id);
    if (!head) continue; // a route can land before its workout; the workout's own upload re-sends it whole
    const parts = db.prepare(`SELECT payload FROM health WHERE user_id=? AND ${PARTS} AND json_extract(payload,'$.workout')=?`).all(userId, id).map(r => JSON.parse(r.payload));
    const route = parts.filter(p => p.kind === 'workout_route').sort((a, b) => a.chunk - b.chunk).flatMap(p => p.points);
    const series = {};
    for (const p of parts.filter(p => p.kind === 'workout_series').sort((a, b) => a.chunk - b.chunk)) {
      (series[p.metric] ??= { unit: p.unit, points: [] }).points.push(...p.points);
    }
    workouts.push({ workout: JSON.parse(head.payload), route, series });
  }
  const tombstones = db.prepare('SELECT id, kind, start, deleted FROM health_deleted WHERE user_id=? AND deleted>? AND deleted<=? ORDER BY deleted').all(userId, afterISO, end).map(r => ({ ...r }));
  // Where the owner's history on this server begins. /health's one-off switch
  // replaces the webhook's rows from here on (spec E10) and keeps those before.
  //
  // The legacy daily `steps` row starts at local midnight — up to ~20h before
  // the phone's own historyStart — and route/series chunks carry a workout's
  // start, not the phone's collection start. Counting either would pull
  // `earliest` back before any record the switch is meant to protect, and
  // /health would delete webhook data this export never replaces (R4).
  const earliest = db.prepare(`SELECT min(start) e FROM health WHERE user_id=? AND kind NOT IN ('steps','workout_route','workout_series')`).get(userId).e ?? null;
  // The single scalar above hides which KIND it came from. Live data showed
  // a resting_heart_rate sample whose interval starts ~20h before heart_rate
  // itself does — pulling `earliest` back that far would make /health delete
  // hours of webhook heart-rate rows nothing here replaces (R10). Per-kind
  // mins let a future rebase move each metric from its own history start
  // rather than one borrowed from an unrelated kind.
  const earliestByKind = Object.fromEntries(db.prepare(
    `SELECT kind, min(start) e FROM health WHERE user_id=? AND kind NOT IN ('steps','workout_route','workout_series') GROUP BY kind`
  ).all(userId).map(r => [r.kind, r.e]));
  return { after, next: Date.parse(end), more, earliest, earliestByKind, records, workouts, tombstones };
}

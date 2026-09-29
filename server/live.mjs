import { EventEmitter } from 'node:events';
import { hash } from './store.mjs';

/** Notifications carry no data: every response rechecks the current grant. */
export function liveSignals() {
  const events = new EventEmitter(); events.setMaxListeners(0);
  return {
    changed(family) { events.emit(family); },
    wait(family, response, milliseconds = 20_000) {
      return new Promise(resolve => {
        const done = () => { clearTimeout(timer); events.off(family, done); response.off('close', done); resolve(); };
        const timer = setTimeout(done, milliseconds); timer.unref();
        events.once(family, done); response.once('close', done);
      });
    },
  };
}

export function putLive(db, user, record) {
  // Late/out-of-order route batches cannot move a pin backwards in time.
  return db.prepare(`INSERT INTO live_locations VALUES (?,?,?) ON CONFLICT(user_id)
    DO UPDATE SET recorded=excluded.recorded,payload=excluded.payload
    WHERE excluded.recorded>live_locations.recorded`).run(user, record.recorded, JSON.stringify(record)).changes > 0;
}

/** Only subjects in this recipient's fresh, revision-matched view can move. */
export function scopedLive(db, row, users, now = Date.now()) {
  if (!row) return { revision: 'unavailable', positions: [] };
  const view = JSON.parse(row.payload);
  const sources = JSON.parse(row.sources || '[]');
  const allowed = new Set((view.viewer === 'none' ? [] : view.people ?? []).filter(p => p.status !== 'off').map(p => p.subject));
  const members = new Map(users.filter(u => u.sharing && !u.delete_requested).map(u => [u.email, u]));
  const positions = [];
  for (const source of sources) {
    const member = members.get(source.email);
    if (!allowed.has(source.subject) || !member) continue;
    const saved = db.prepare('SELECT payload FROM live_locations WHERE user_id=?').get(member.id);
    if (!saved) continue;
    const fix = JSON.parse(saved.payload);
    const age = now - Date.parse(fix.recorded);
    if (age < -5_000 || age > 120_000) continue;
    // Match the existing site precision; freshness must not widen access.
    const round = n => Math.round(n * 1e4) / 1e4;
    positions.push({ subject: source.subject, position: { lat: round(fix.latitude), lon: round(fix.longitude), at: fix.recorded, accuracy: Math.max(12, fix.accuracy) }, moving: fix.moving, speed: fix.speed, battery: fix.battery ?? null });
  }
  return { revision: hash(JSON.stringify([row.revision, positions])), scope: row.revision, positions };
}

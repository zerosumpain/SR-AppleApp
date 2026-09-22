import { openStore, createUser } from './store.mjs';
import { randomUUID } from 'node:crypto';
const db = openStore(process.env.DATABASE_PATH ?? './data/apple.sqlite');
/**
 * A few days of plausible movement and health, so the Movement tab has
 * something to draw in the local preview.
 *
 * The live service records one fix every thirty seconds or so while you are
 * moving and then goes quiet for hours, which is what makes the map's gap
 * handling worth testing at all — a seed of evenly spaced points would draw a
 * clean line and prove nothing. So each day here is three short walks with
 * real gaps between them, and a night's sleep across the boundary.
 *
 * Local time throughout, matching the browser on the same machine: the day
 * strip buckets by the reader's offset, so a seed written in UTC would land a
 * walk on the wrong column every British summer.
 */
const DEMO_DAYS = 6;
const WALKS = [[8, 0, 42], [12, 30, 24], [18, 5, 50]];

function routePoint(origin, phase) {
  // A wandering loop rather than a straight line, so the trace has corners to
  // simplify away and a shape to recognise when it is drawn.
  const t = phase * Math.PI * 2;
  return [
    origin[0] + 0.0042 * Math.sin(t) + 0.0016 * Math.sin(t * 2.7),
    origin[1] + 0.0067 * Math.cos(t * 0.8) - 0.0021 * Math.cos(t * 3.1),
  ];
}

function seedMovement(db, userId, origin) {
  const midnight = new Date();
  midnight.setHours(0, 0, 0, 0);
  const health = db.prepare('INSERT INTO health VALUES (?,?,?,?,?,?,?) ON CONFLICT(user_id,id) DO UPDATE SET payload=excluded.payload,start=excluded.start,end=excluded.end');
  const location = db.prepare('INSERT OR IGNORE INTO locations VALUES (?,?,?,?,?)');
  const received = new Date().toISOString();
  for (let back = 0; back < DEMO_DAYS; back++) {
    const dayStart = new Date(midnight.getTime() - back * 86400000);
    const date = `${dayStart.getFullYear()}-${String(dayStart.getMonth() + 1).padStart(2, '0')}-${String(dayStart.getDate()).padStart(2, '0')}`;
    let steps = 0;
    let rest = null;
    WALKS.forEach(([hour, minute, minutes], walk) => {
      const from = dayStart.getTime() + hour * 3600000 + minute * 60000;
      const fixes = Math.round((minutes * 60) / 30);
      if (from > Date.now()) return;
      // Between walks, stand still somewhere. The FIRST break is sampled the
      // whole way through — every four minutes, never a gap over ten — so it
      // is invisible to a rule that splits on missing data and only a movement
      // rule separates the two walks. The SECOND break is left as a genuine
      // recording gap, which is the other way a break shows up. The preview
      // has to contain both or it only proves half of this.
      if (rest) {
        const every = walk === 1 ? 240000 : 3300000;
        for (let at = rest.at + every; at < from; at += every) {
          if (at > Date.now()) break;
          const record = {
            id: `demo-${userId}-${date}-rest-${walk}-${at}`,
            recorded: new Date(at).toISOString(),
            latitude: rest.lat, longitude: rest.lng,
            accuracy: Number((6 + Math.abs(Math.sin(at / 1e7)) * 9).toFixed(1)),
            speed: 0, moving: false,
          };
          location.run(userId, record.id, record.recorded, JSON.stringify(record), received);
        }
      }
      steps += minutes * 105;
      for (let i = 0; i <= fixes; i++) {
        const at = from + i * 30000;
        if (at > Date.now()) break;
        const [lat, lng] = routePoint(origin, (back * 0.17 + i / fixes) % 1);
        const record = {
          id: `demo-${userId}-${date}-${hour}-${i}`,
          recorded: new Date(at).toISOString(),
          latitude: Number(lat.toFixed(6)),
          longitude: Number(lng.toFixed(6)),
          accuracy: Number((4 + Math.abs(Math.sin(i * 1.7)) * 9).toFixed(1)),
          speed: Number((1.1 + Math.abs(Math.sin(i / 4)) * 0.9).toFixed(2)),
          moving: i > 0 && i < fixes,
        };
        location.run(userId, record.id, record.recorded, JSON.stringify(record), received);
        rest = { at, lat: record.latitude, lng: record.longitude };
      }
      const end = Math.min(Date.now(), from + minutes * 60000);
      if (minutes >= 40) {
        const workout = { id: `demo-${userId}-workout-${date}-${hour}`, kind: 'workout', start: new Date(from).toISOString(), end: new Date(end).toISOString(), value: Math.round((end - from) / 1000), unit: 'seconds', activity: 'Walking', distance: minutes * 78, source: 'Synthetic workout example' };
        health.run(userId, workout.id, workout.kind, workout.start, workout.end, JSON.stringify(workout), received);
      }
    });
    // Every five minutes while awake, the way a watch reports it: lifted by the
    // walks, lowest in the small hours.
    for (let minute = 0; minute < 1440; minute += 5) {
      const at = dayStart.getTime() + minute * 60000;
      if (at > Date.now()) break;
      const hour = minute / 60;
      const walking = WALKS.some(([h, m, length]) => hour >= h + m / 60 && hour <= h + m / 60 + length / 60);
      const asleep = hour < 7 || hour >= 23;
      const value = Math.round((asleep ? 51 : walking ? 104 : 71) + Math.sin(minute / 23) * 6);
      const stamp = new Date(at).toISOString();
      const record = { id: `demo-${userId}-hr-${date}-${minute}`, kind: 'heart_rate', start: stamp, end: stamp, value, unit: 'bpm', source: 'Synthetic Watch example' };
      health.run(userId, record.id, record.kind, record.start, record.end, JSON.stringify(record), received);
    }
    const stepRecord = { id: `demo-${userId}-steps-${date}`, kind: 'steps', start: dayStart.toISOString(), end: new Date(Math.min(Date.now(), dayStart.getTime() + 86399000)).toISOString(), value: steps + back * 137, unit: 'count', source: 'HealthKit daily statistics' };
    health.run(userId, stepRecord.id, stepRecord.kind, stepRecord.start, stepRecord.end, JSON.stringify(stepRecord), received);
    const resting = { id: `demo-${userId}-rhr-${date}`, kind: 'resting_heart_rate', start: new Date(dayStart.getTime() + 6 * 3600000).toISOString(), end: new Date(dayStart.getTime() + 6 * 3600000).toISOString(), value: 54 + (back % 4), unit: 'bpm', source: 'Synthetic Watch example' };
    if (Date.parse(resting.start) <= Date.now()) health.run(userId, resting.id, resting.kind, resting.start, resting.end, JSON.stringify(resting), received);
    // Sleep starts the evening BEFORE the day it belongs to, which is exactly
    // the case the timeline selects by overlap rather than by start.
    for (const [stage, fromHour, toHour] of [['core', -1, 1.5], ['deep', 1.5, 3], ['rem', 3, 4.5], ['core', 4.5, 6.4], ['awake', 6.4, 6.7]]) {
      const start = dayStart.getTime() + fromHour * 3600000;
      const end = dayStart.getTime() + toHour * 3600000;
      if (end > Date.now()) continue;
      const record = { id: `demo-${userId}-sleep-${date}-${stage}-${fromHour}`, kind: 'sleep', start: new Date(start).toISOString(), end: new Date(end).toISOString(), stage, source: 'Synthetic sleep example' };
      health.run(userId, record.id, record.kind, record.start, record.end, JSON.stringify(record), received);
    }
  }
}

if (process.argv[2] === 'demo') {
  if (process.env.DEMO_MODE !== '1') throw new Error('DEMO_MODE=1 is required; never seed a real service');
  const stamp = new Date().toISOString();
  const origins = { alex: [51.5074, -0.1278], sam: [51.509, -0.1305], robin: [53.4808, -2.2426] };
  for (const [id, name, family] of [['alex', 'Alex', 'demo-family'], ['sam', 'Sam', 'demo-family'], ['robin', 'Robin', 'other-family']]) {
    if (!db.prepare('SELECT id FROM users WHERE id=?').get(id)) {
      createUser(db, { id, email: `${id}@example.test`, name, family });
      db.prepare('UPDATE users SET sharing=1 WHERE id=?').run(id);
      const records = [
        { id: 'rhr-demo', kind: 'resting_heart_rate', start: stamp, end: stamp, value: 58, unit: 'bpm', source: 'Synthetic Watch example' }
      ];
      for (const r of records) db.prepare('INSERT INTO health VALUES (?,?,?,?,?,?,?)').run(id, r.id, r.kind, r.start, r.end, JSON.stringify(r), stamp);
      const location = { id: randomUUID(), recorded: stamp, latitude: origins[id][0], longitude: origins[id][1], accuracy: 20, speed: 0, moving: false };
      db.prepare('INSERT INTO locations VALUES (?,?,?,?,?)').run(id, location.id, stamp, JSON.stringify(location), stamp);
    }
    // Idempotent, and run every time: topping up an existing preview database
    // with today's movement is the usual reason to run this twice.
    seedMovement(db, id, origins[id]);
  }
  console.log(`Synthetic accounts ready with ${DEMO_DAYS} days of movement: alex@example.test, sam@example.test, robin@example.test.`);
  console.log('There is no password — the preview signs in by naming one of these, and only on a non-https origin with DEMO_MODE=1.');
} else if (process.argv[2] === 'create-user') {
  const [email, name, family] = process.argv.slice(3);
  if (!email || !name || !family) throw new Error('Usage: node server/admin.mjs create-user EMAIL NAME FAMILY');
  // No password to choose. EMAIL must be the Google address the person signs in
  // to strangeramblings.com with — that is the whole credential now, and a
  // mistyped one simply never matches.
  createUser(db, { id: randomUUID(), email, name, family });
  console.log(`Added ${email} to family ${family}. Location sharing is off.`);
  console.log('They must also be able to sign in to strangeramblings.com — owner or guest on the allow-list.');
} else throw new Error('Choose demo or create-user');
db.close();

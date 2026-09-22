import { openStore, createUser } from './store.mjs';
import { randomUUID } from 'node:crypto';
const db = openStore(process.env.DATABASE_PATH ?? './data/apple.sqlite');
if (process.argv[2] === 'demo') {
  if (process.env.DEMO_MODE !== '1') throw new Error('DEMO_MODE=1 is required; never seed a real service');
  const stamp = new Date().toISOString();
  for (const [id, name, family] of [['alex', 'Alex', 'demo-family'], ['sam', 'Sam', 'demo-family'], ['robin', 'Robin', 'other-family']]) {
    if (db.prepare('SELECT id FROM users WHERE id=?').get(id)) continue;
    createUser(db, { id, email: `${id}@example.test`, name, family });
    db.prepare('UPDATE users SET sharing=1 WHERE id=?').run(id);
    const records = [
      { id: 'steps-demo', kind: 'steps', start: stamp, end: stamp, value: id === 'alex' ? 6420 : 3810, unit: 'count', source: 'Synthetic HealthKit example' },
      { id: 'hr-demo', kind: 'heart_rate', start: stamp, end: stamp, value: 74, unit: 'bpm', source: 'Synthetic Watch example' },
      { id: 'rhr-demo', kind: 'resting_heart_rate', start: stamp, end: stamp, value: 58, unit: 'bpm', source: 'Synthetic Watch example' },
      { id: 'sleep-demo', kind: 'sleep', start: new Date(Date.now() - 8 * 3600000).toISOString(), end: stamp, stage: 'asleep', source: 'Synthetic sleep example' },
      { id: 'workout-demo', kind: 'workout', start: new Date(Date.now() - 3600000).toISOString(), end: stamp, value: 3600, unit: 'seconds', activity: 'Walking', distance: 4800, source: 'Synthetic workout example' }
    ];
    for (const r of records) db.prepare('INSERT INTO health VALUES (?,?,?,?,?,?,?)').run(id, r.id, r.kind, r.start, r.end, JSON.stringify(r), stamp);
    const location = { id: randomUUID(), recorded: stamp, latitude: id === 'alex' ? 51.5074 : 51.509, longitude: -0.1278, accuracy: 20, speed: 0, moving: false };
    db.prepare('INSERT INTO locations VALUES (?,?,?,?,?)').run(id, location.id, stamp, JSON.stringify(location), stamp);
  }
  console.log('Synthetic accounts ready: alex@example.test, sam@example.test, robin@example.test.');
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

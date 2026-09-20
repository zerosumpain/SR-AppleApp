import { openStore, createUser } from './store.mjs';
import { randomUUID } from 'node:crypto';
const db = openStore(process.env.DATABASE_PATH ?? './data/apple.sqlite');
if (process.argv[2] === 'demo') {
  if (process.env.DEMO_MODE !== '1') throw new Error('DEMO_MODE=1 is required; never seed a real service');
  const stamp = new Date().toISOString();
  for (const [id, name, family] of [['alex', 'Alex', 'demo-family'], ['sam', 'Sam', 'demo-family'], ['robin', 'Robin', 'other-family']]) {
    if (db.prepare('SELECT id FROM users WHERE id=?').get(id)) continue;
    createUser(db, { id, email: `${id}@example.test`, name, family, password: 'SR-local-demo-only!' });
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
  console.log('Synthetic accounts ready: alex@example.test, sam@example.test, robin@example.test. Password: SR-local-demo-only!');
} else if (process.argv[2] === 'create-user') {
  const [email, name, family] = process.argv.slice(3);
  if (!email || !name || !family || !process.env.NEW_USER_PASSWORD || process.env.NEW_USER_PASSWORD.length < 14) throw new Error('Usage: NEW_USER_PASSWORD=<14+ chars> node server/admin.mjs create-user EMAIL NAME FAMILY');
  createUser(db, { id: randomUUID(), email, name, family, password: process.env.NEW_USER_PASSWORD });
  console.log('User created. Location sharing is off.');
} else throw new Error('Choose demo or create-user');
db.close();

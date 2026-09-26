import { DatabaseSync } from 'node:sqlite';
import { randomBytes, createHash } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
export const hash = value => createHash('sha256').update(value).digest('hex');
export const secret = () => randomBytes(32).toString('base64url');
export function openStore(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
      family TEXT NOT NULL, sharing INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS credentials (
      hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
      kind TEXT NOT NULL, label TEXT NOT NULL, expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS health (
      user_id TEXT NOT NULL REFERENCES users(id), id TEXT NOT NULL,
      kind TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL,
      payload TEXT NOT NULL, received TEXT NOT NULL,
      PRIMARY KEY(user_id, id));
    CREATE TABLE IF NOT EXISTS locations (
      user_id TEXT NOT NULL REFERENCES users(id), id TEXT NOT NULL,
      recorded TEXT NOT NULL, payload TEXT NOT NULL, received TEXT NOT NULL,
      PRIMARY KEY(user_id, id));
    CREATE INDEX IF NOT EXISTS locations_user_time ON locations(user_id, recorded);
    -- The household lane (app.mjs GET /api/apple/household) pages ACROSS
    -- users by (received, user_id, id) — locations_user_time above is led by
    -- user_id, so it cannot answer that ORDER BY without a scan + temp sort.
    -- id trails so the ORDER BY needs no temp b-tree, same trick as
    -- health_user_received below.
    CREATE INDEX IF NOT EXISTS locations_received ON locations(received, user_id, id);
    CREATE INDEX IF NOT EXISTS health_user_kind_time ON health(user_id, kind, start);
    -- The export cursor pages by received (id trailing so its ORDER BY needs no
    -- temp sort) and earliest by start, neither led by kind.
    CREATE INDEX IF NOT EXISTS health_user_received ON health(user_id, received, id);
    CREATE INDEX IF NOT EXISTS health_user_start ON health(user_id, start);
    CREATE TABLE IF NOT EXISTS health_deleted (
      user_id TEXT NOT NULL REFERENCES users(id), id TEXT NOT NULL,
      kind TEXT NOT NULL, start TEXT NOT NULL, deleted TEXT NOT NULL,
      PRIMARY KEY(user_id, id));
    CREATE INDEX IF NOT EXISTS health_deleted_time ON health_deleted(user_id, deleted);
    -- Household alerts (arrivals/departures forwarded from SR-Main). One row
    -- per (recipient, event id) so a retried events POST is INSERT OR IGNORE
    -- idempotent; 'acked' is NULL until the recipient's own device/browser
    -- acknowledges it, and the pending-first index below is what the alerts
    -- GET and the 7-day prune both walk.
    CREATE TABLE IF NOT EXISTS alerts (
      user_id TEXT NOT NULL REFERENCES users(id), id TEXT NOT NULL,
      payload TEXT NOT NULL, created TEXT NOT NULL, acked TEXT,
      PRIMARY KEY(user_id, id));
    CREATE INDEX IF NOT EXISTS alerts_user_pending ON alerts(user_id, acked, created);
    -- What each person's Family tab shows, built and scoped by SR-Main and
    -- pushed whole every observe cycle (app.mjs POST
    -- /api/apple/household/views). One row per person, replaced, never
    -- appended: this is a view, not a history. The phone reads only its own.
    CREATE TABLE IF NOT EXISTS household_views (
      user_id TEXT PRIMARY KEY REFERENCES users(id),
      payload TEXT NOT NULL, updated TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS health_workout_parts ON health(user_id, json_extract(payload, '$.workout'))
      WHERE kind IN ('workout_route', 'workout_series');
  `);
  // Sign-in moved to the main site's Google session, so the stored scrypt hashes
  // authenticate nothing. They are DROPPED rather than left in place: a password
  // hash is credential material whether or not anything still reads it, and a
  // password chosen for this pilot may well be one used somewhere else.
  //
  // Guarded because CREATE TABLE above already omits the column on a fresh
  // database, and DROP COLUMN on a missing column is an error, not a no-op.
  const columns = db.prepare('PRAGMA table_info(users)').all();
  if (columns.some((c) => c.name === 'password')) {
    db.exec('ALTER TABLE users DROP COLUMN password');
  }
  return db;
}
/**
 * Add somebody to a family.
 *
 * No password: the email IS the credential now, matched against whoever the main
 * site says is signed in. Provisioning stays deliberate rather than happening on
 * first sign-in, because `family` decides who can see a location and there is
 * nothing in a Google login to infer it from.
 */
export function createUser(db, { id, email, name, family }) {
  db.prepare('INSERT INTO users(id,email,name,family) VALUES (?,?,?,?)')
    .run(id, email.toLowerCase(), name, family);
}
export function issue(db, user, kind, label, ttl) {
  const token = secret();
  db.prepare('INSERT INTO credentials VALUES (?,?,?,?,?)').run(hash(token), user, kind, label, Date.now() + ttl);
  return token;
}

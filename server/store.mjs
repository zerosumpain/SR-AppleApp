import { DatabaseSync } from 'node:sqlite';
import { randomBytes, createHash, randomUUID } from 'node:crypto';
import { mkdirSync, chmodSync } from 'node:fs';
import { dirname } from 'node:path';
export const hash = value => createHash('sha256').update(value).digest('hex');
export const secret = () => randomBytes(32).toString('base64url');
export function openStore(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(path);
  if (path !== ':memory:') chmodSync(path, 0o600);
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
    CREATE TABLE IF NOT EXISTS live_locations (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      recorded TEXT NOT NULL,
      payload TEXT NOT NULL
    );
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
  // When a member's phone last asked for a SITE credential (app.mjs POST
  // /api/apple/site-pair), or NULL once it has one. SR-Main reads it through
  // the household lane and answers by putting a one-time site pairing code in
  // that person's pushed view — the phone never talks to the site's owner-only
  // device minting itself. Added by ALTER rather than in CREATE TABLE so an
  // existing database gains it; guarded because ADD COLUMN on a column that
  // already exists is an error, not a no-op.
  if (!columns.some((c) => c.name === 'site_pair_wanted')) {
    db.exec('ALTER TABLE users ADD COLUMN site_pair_wanted TEXT');
  }
  for (const [name, definition] of Object.entries({
    access_version: "TEXT NOT NULL DEFAULT 'legacy'",
    access_allowed: 'INTEGER NOT NULL DEFAULT 1',
    privacy_version: 'INTEGER NOT NULL DEFAULT 0',
    steps_sharing: 'INTEGER NOT NULL DEFAULT 0'
  })) {
    if (!columns.some(c => c.name === name)) db.exec(`ALTER TABLE users ADD COLUMN ${name} ${definition}`);
  }
  if (!db.prepare('PRAGMA table_info(credentials)').all().some(c => c.name === 'access_version')) {
    db.exec("ALTER TABLE credentials ADD COLUMN access_version TEXT NOT NULL DEFAULT 'legacy'");
  }
  if (!db.prepare('PRAGMA table_info(household_views)').all().some(c => c.name === 'sources')) {
    db.exec("ALTER TABLE household_views ADD COLUMN sources TEXT NOT NULL DEFAULT '[]'");
  }
  if (!db.prepare('PRAGMA table_info(household_views)').all().some(c => c.name === 'revision')) {
    db.exec("ALTER TABLE household_views ADD COLUMN revision TEXT NOT NULL DEFAULT ''");
  }
  if (!db.prepare('PRAGMA table_info(alerts)').all().some(c => c.name === 'revision')) {
    db.exec("ALTER TABLE alerts ADD COLUMN revision TEXT NOT NULL DEFAULT ''");
  }
  db.exec(`CREATE TABLE IF NOT EXISTS deletion_jobs (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL, email TEXT NOT NULL, family TEXT NOT NULL,
    created TEXT NOT NULL, main_done INTEGER NOT NULL DEFAULT 0,
    health_done INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS deletion_items (job_id TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL, start TEXT NOT NULL, deleted TEXT NOT NULL, PRIMARY KEY(job_id,id));
    CREATE TRIGGER IF NOT EXISTS consent_invalidates_views AFTER UPDATE OF sharing,steps_sharing ON users
    WHEN OLD.sharing<>NEW.sharing OR OLD.steps_sharing<>NEW.steps_sharing BEGIN
      UPDATE users SET privacy_version=privacy_version+1 WHERE id=NEW.id;
      DELETE FROM household_views; DELETE FROM alerts;
    END;`);
  // Jobs must outlive account deletion. Earlier previews referenced users;
  // retain every job while removing that FK and snapshotting its family.
  if (db.prepare('PRAGMA foreign_key_list(deletion_jobs)').all().length) {
    db.exec(`BEGIN IMMEDIATE;
      ALTER TABLE deletion_jobs RENAME TO deletion_jobs_old;
      CREATE TABLE deletion_jobs (id TEXT PRIMARY KEY,user_id TEXT NOT NULL,email TEXT NOT NULL,
        family TEXT NOT NULL,created TEXT NOT NULL,main_done INTEGER NOT NULL DEFAULT 0,health_done INTEGER NOT NULL DEFAULT 0);
      INSERT INTO deletion_jobs SELECT j.id,j.user_id,j.email,u.family,j.created,j.main_done,j.health_done
        FROM deletion_jobs_old j JOIN users u ON u.id=j.user_id;
      DROP TABLE deletion_jobs_old; COMMIT;`);
  }
  for (const column of ['account_requested', 'account_done']) {
    if (!db.prepare('PRAGMA table_info(deletion_jobs)').all().some(c => c.name === column)) {
      db.exec(`ALTER TABLE deletion_jobs ADD COLUMN ${column} INTEGER NOT NULL DEFAULT 0`);
    }
  }
  // When a person asked, from their own phone, for their account to be
  // deleted (app.mjs POST /api/apple/account/delete), or NULL. Their uploaded
  // data is wiped at once; SR-Main reads the flag through the household lane
  // and deletes the rest — site account and all — then deletes this row
  // (household/users/delete). Same ALTER-guard as site_pair_wanted above.
  if (!columns.some((c) => c.name === 'delete_requested')) {
    db.exec('ALTER TABLE users ADD COLUMN delete_requested TEXT');
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
/**
 * Add somebody to a family, or find them if they are already in it.
 *
 * The household lane's way in (SR-Main's /welcome). The family is always the
 * caller's to name, never the request's, and somebody already in a DIFFERENT
 * family is never moved — that would hand their location to people they did
 * not choose — so they come back as `conflict` rather than being touched.
 * A new person starts with sharing off: the phone asks at pairing.
 */
export function ensureUser(db, { email, name, family }) {
  const lower = email.toLowerCase();
  const existing = db.prepare('SELECT id,email,name,family FROM users WHERE email=?').get(lower);
  if (existing) {
    if (existing.family !== family) return { conflict: true };
    // A name already on file wins: the site sends whatever its sign-in holds,
    // and that must not overwrite one the owner chose.
    const kept = existing.name || name;
    if (!existing.name) db.prepare('UPDATE users SET name=? WHERE id=?').run(name, existing.id);
    return { id: existing.id, email: existing.email, name: kept, created: false };
  }
  const id = randomUUID();
  createUser(db, { id, email: lower, name, family });
  return { id, email: lower, name, created: true };
}
/** How long a paired phone's device token lives. */
export const DEVICE_TTL = 90 * 86400000;
/** How long a one-time pairing code lives. */
export const PAIR_CODE_TTL = 600000;
/**
 * A fresh one-time pairing code for somebody, replacing any they had — one
 * definition shared by the browser's own "pair a phone" and the household
 * lane's onboarding, so the two cannot drift on lifetime or on "one live code
 * per person".
 */
export function mintPairCode(db, user) {
  db.prepare("DELETE FROM credentials WHERE user_id=? AND kind='pair'").run(user);
  return issue(db, user, 'pair', 'One-time pairing', PAIR_CODE_TTL);
}
/**
 * Wipe everything a person's phone uploaded, and unpair it.
 *
 * One definition for the two ways in: the person's own "delete my data"
 * (`DELETE /api/apple/data`) and SR-Main's /welcome asking on their behalf over
 * the household lane. Health, its tombstones, location history, queued alerts,
 * device tokens and any live pairing code go; sharing is switched off so a
 * phone that re-pairs starts from "ask first". The account row stays — family
 * membership is the owner's decision, not the uploader's. Returns what was
 * removed, per table, so a caller can say it honestly.
 */
export function deleteUserData(db, user, ownerEmail) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const account = db.prepare('SELECT email,family FROM users WHERE id=?').get(user);
    const pending = db.prepare('SELECT id FROM deletion_jobs WHERE user_id=? AND (main_done=0 OR health_done=0)').get(user);
    if (!pending) db.prepare('INSERT INTO deletion_jobs(id,user_id,email,family,created,health_done) VALUES(?,?,?,?,?,?)')
      .run(randomUUID(), user, account.email, account.family, new Date().toISOString(), Number(account.email !== ownerEmail?.toLowerCase()));
    // Tombstones survive deletion until the downstream consumer acknowledges.
    db.prepare(`INSERT OR REPLACE INTO health_deleted(user_id,id,kind,start,deleted)
      SELECT user_id,id,kind,start,? FROM health WHERE user_id=?`).run(new Date().toISOString(), user);
    const job = db.prepare('SELECT id,created FROM deletion_jobs WHERE user_id=? AND (main_done=0 OR health_done=0)').get(user);
    db.prepare('INSERT OR IGNORE INTO deletion_items(job_id,id,kind,start,deleted) SELECT ?,id,kind,start,? FROM health_deleted WHERE user_id=?').run(job.id,job.created,user);
    db.prepare('DELETE FROM live_locations WHERE user_id=?').run(user);
    const deleted = {
      health: db.prepare('DELETE FROM health WHERE user_id=?').run(user).changes,
      tombstones: 0,
      locations: db.prepare('DELETE FROM locations WHERE user_id=?').run(user).changes,
      alerts: db.prepare('DELETE FROM alerts WHERE user_id=?').run(user).changes,
      credentials: db.prepare("DELETE FROM credentials WHERE user_id=? AND kind IN ('device','pair')").run(user).changes,
    };
    db.prepare('DELETE FROM household_views').run();
    db.prepare('DELETE FROM alerts').run();
    db.prepare('UPDATE users SET sharing=0,steps_sharing=0,privacy_version=privacy_version+1,site_pair_wanted=NULL WHERE id=?').run(user);
    db.exec('COMMIT');
    return deleted;
  } catch (error) { db.exec('ROLLBACK'); throw error; }
}
/**
 * Delete a person outright: everything `deleteUserData` wipes, plus their
 * pushed Family view, EVERY credential they hold (any kind), and the account
 * row itself. SR-Main's in-app "Delete account" asks for this over the
 * household lane (App Store guideline 5.1.1(v)). The caller decides whether
 * the person may be deleted — the owner never is (app.mjs refuses). Returns
 * what was removed, per table.
 */
export function deleteUser(db, user) {
  const views = db.prepare('SELECT count(*) n FROM household_views WHERE user_id=?').get(user).n;
  const raw = deleteUserData(db, user);
  db.exec('BEGIN IMMEDIATE');
  try {
    // The Main account deletion may fail after this account row disappears.
    // Keep a separate acknowledgement so its independent timer can retry.
    db.prepare('UPDATE deletion_jobs SET account_requested=1 WHERE user_id=? AND main_done=0').run(user);
    db.prepare('DELETE FROM live_locations WHERE user_id=?').run(user);
    const deleted = {
      health: db.prepare('DELETE FROM health WHERE user_id=?').run(user).changes,
      tombstones: db.prepare('DELETE FROM health_deleted WHERE user_id=?').run(user).changes,
      locations: db.prepare('DELETE FROM locations WHERE user_id=?').run(user).changes,
      alerts: db.prepare('DELETE FROM alerts WHERE user_id=?').run(user).changes,
      credentials: db.prepare('DELETE FROM credentials WHERE user_id=?').run(user).changes,
      users: db.prepare('DELETE FROM users WHERE id=?').run(user).changes,
      ...raw, views,
    };
    db.exec('COMMIT');
    return deleted;
  } catch (error) { db.exec('ROLLBACK'); throw error; }
}
export function issue(db, user, kind, label, ttl) {
  const token = secret();
  db.prepare('INSERT INTO credentials(hash,user_id,kind,label,expires,access_version) VALUES (?,?,?,?,?,(SELECT access_version FROM users WHERE id=?))').run(hash(token), user, kind, label, Date.now() + ttl, user);
  return token;
}

/** Independent of new uploads: abandoned devices cannot defeat retention. */
export function pruneStore(db, now = Date.now()) {
  db.prepare('DELETE FROM locations WHERE recorded<?').run(new Date(now - 30 * 86400000).toISOString());
  db.prepare('DELETE FROM alerts WHERE created<?').run(new Date(now - 7 * 86400000).toISOString());
  db.prepare('DELETE FROM household_views WHERE updated<?').run(new Date(now - 5 * 60000).toISOString());
  db.prepare('DELETE FROM credentials WHERE expires<?').run(now);
}

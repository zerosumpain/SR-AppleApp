import { DatabaseSync } from 'node:sqlite';
import { randomBytes, scryptSync, timingSafeEqual, createHash } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
export const hash = value => createHash('sha256').update(value).digest('hex');
export const secret = () => randomBytes(32).toString('base64url');
export function passwordHash(password) {
  const salt = randomBytes(16).toString('hex');
  return `${salt}:${scryptSync(password, salt, 64).toString('hex')}`;
}
export function passwordMatches(password, stored) {
  const [salt, expected] = stored.split(':');
  return timingSafeEqual(scryptSync(password, salt, 64), Buffer.from(expected, 'hex'));
}
export function openStore(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
      family TEXT NOT NULL, password TEXT NOT NULL, sharing INTEGER NOT NULL DEFAULT 0);
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
    CREATE INDEX IF NOT EXISTS health_user_kind_time ON health(user_id, kind, start);
  `);
  return db;
}
export function createUser(db, { id, email, name, family, password }) {
  db.prepare('INSERT INTO users(id,email,name,family,password) VALUES (?,?,?,?,?)')
    .run(id, email.toLowerCase(), name, family, passwordHash(password));
}
export function issue(db, user, kind, label, ttl) {
  const token = secret();
  db.prepare('INSERT INTO credentials VALUES (?,?,?,?,?)').run(hash(token), user, kind, label, Date.now() + ttl);
  return token;
}

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { hash, issue, passwordHash, passwordMatches } from './store.mjs';
const dummyPassword = passwordHash('unused-account-enumeration-protection');
const kinds = new Set(['steps', 'heart_rate', 'resting_heart_rate', 'sleep', 'workout']);
const iso = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT/.test(value) && Number.isFinite(Date.parse(value));
const bounded = (x, lo, hi) => typeof x === 'number' && Number.isFinite(x) && x >= lo && x <= hi;
const string = (x, max = 200) => typeof x === 'string' && x.length > 0 && x.length <= max;
function fail(status, message) { throw Object.assign(new Error(message), { status }); }
function exactKeys(obj, allowed) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj) || Object.keys(obj).some(k => !allowed.includes(k))) fail(400, 'Unexpected fields');
}
function healthRecord(r) {
  exactKeys(r, ['id', 'kind', 'start', 'end', 'value', 'unit', 'source', 'stage', 'activity', 'distance', 'energy']);
  if (!string(r.id) || !kinds.has(r.kind) || !iso(r.start) || !iso(r.end) || Date.parse(r.end) < Date.parse(r.start) || Date.parse(r.end) > Date.now() + 300000 || !string(r.source)) fail(400, 'Invalid health record');
  if (r.kind === 'steps' && (!bounded(r.value, 0, 300000) || r.unit !== 'count')) fail(400, 'Invalid steps');
  if (['heart_rate', 'resting_heart_rate'].includes(r.kind) && (!bounded(r.value, 1, 350) || r.unit !== 'bpm')) fail(400, 'Invalid heart rate');
  if (r.kind === 'sleep' && !['in_bed', 'awake', 'asleep', 'core', 'deep', 'rem'].includes(r.stage)) fail(400, 'Invalid sleep stage');
  if (r.kind === 'workout' && (!string(r.activity, 80) || !bounded(r.value, 0, 604800) || r.unit !== 'seconds')) fail(400, 'Invalid workout');
  if (r.distance != null && !bounded(r.distance, 0, 10000000)) fail(400, 'Invalid distance');
  if (r.energy != null && !bounded(r.energy, 0, 100000)) fail(400, 'Invalid energy');
  return { ...r, start: new Date(r.start).toISOString(), end: new Date(r.end).toISOString() };
}
function locationRecord(r) {
  exactKeys(r, ['id', 'recorded', 'latitude', 'longitude', 'accuracy', 'speed', 'moving']);
  if (!string(r.id) || !iso(r.recorded) || Date.parse(r.recorded) > Date.now() + 300000 || !bounded(r.latitude, -90, 90) || !bounded(r.longitude, -180, 180) || !bounded(r.accuracy, 0, 10000) || !bounded(r.speed, 0, 400) || typeof r.moving !== 'boolean') fail(400, 'Invalid location');
  return { ...r, recorded: new Date(r.recorded).toISOString() };
}
export function createApp(db, { origin = 'http://127.0.0.1:5295', demo = false } = {}) {
  const rate = new Map();
  const csrfOrigin = new URL(origin).origin;
  const secure = csrfOrigin.startsWith('https:');
  function limit(key) {
    const now = Date.now();
    for (const [k, v] of rate) if (now > v.until) rate.delete(k);
    const value = rate.get(key) ?? { count: 0, until: now + 60000 };
    value.count++;
    rate.set(key, value);
    if (value.count > 20) fail(429, 'Too many attempts. Try again in a minute.');
  }
  return createServer(async (req, res) => {
    const send = (status, body) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    if (secure) res.setHeader('Strict-Transport-Security', 'max-age=31536000');
    try {
      const url = new URL(req.url, origin);
      const path = url.pathname;
      const method = req.method;
      if (method === 'GET' && path === '/healthz') return send(200, { ok: true });
      const assets = { '/apple-app': 'index.html', '/apple-app/': 'index.html', '/apple-app/app.js': 'app.js', '/apple-app/style.css': 'style.css' };
      if (method === 'GET' && assets[path]) {
        const contents = await readFile(fileURLToPath(new URL(`./public/${assets[path]}`, import.meta.url)));
        res.setHeader('Content-Type', path.endsWith('.js') ? 'text/javascript' : path.endsWith('.css') ? 'text/css' : 'text/html');
        return res.end(contents);
      }
      if (path === '/' && method === 'GET') { res.writeHead(302, { Location: '/apple-app/' }); return res.end(); }
      if (!path.startsWith('/api/apple/')) fail(404, 'Not found');
      const readJSON = async () => {
        if (!(req.headers['content-type'] ?? '').startsWith('application/json')) fail(415, 'JSON required');
        let size = 0, parts = [];
        for await (const part of req) { size += part.length; if (size > 1048576) fail(413, 'Batch too large'); parts.push(part); }
        try { return JSON.parse(Buffer.concat(parts).toString()); } catch { fail(400, 'Invalid JSON'); }
      };
      if (method !== 'GET' && req.headers.origin && req.headers.origin !== csrfOrigin) fail(403, 'Origin not allowed');
      if (path === '/api/apple/login' && method === 'POST') {
        limit(req.socket.remoteAddress);
        const body = await readJSON(); exactKeys(body, ['email', 'password']);
        if (!string(body.email) || !string(body.password, 1024)) fail(400, 'Email and password required');
        const user = db.prepare('SELECT * FROM users WHERE email = ?').get(body.email.toLowerCase());
        const valid = passwordMatches(body.password, user?.password ?? dummyPassword);
        if (!user || !valid) fail(401, 'Email or password incorrect');
        const token = issue(db, user.id, 'session', 'Browser', 12 * 3600000);
        res.setHeader('Set-Cookie', `sr_apple=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200${secure ? '; Secure' : ''}`);
        return send(200, { ok: true });
      }
      if (path === '/api/apple/pair' && method === 'POST') {
        limit(req.socket.remoteAddress);
        const body = await readJSON(); exactKeys(body, ['code', 'label']);
        if (!string(body.code) || !string(body.label, 80)) fail(400, 'Pairing code and device name required');
        db.exec('BEGIN IMMEDIATE');
        try {
          const code = db.prepare("SELECT * FROM credentials WHERE hash=? AND kind='pair' AND expires>?").get(hash(body.code), Date.now());
          if (!code) fail(401, 'Pairing code expired or invalid');
          db.prepare('DELETE FROM credentials WHERE hash=?').run(code.hash);
          const token = issue(db, code.user_id, 'device', body.label, 90 * 86400000);
          db.exec('COMMIT');
          return send(200, { token, userId: code.user_id });
        } catch (error) { db.exec('ROLLBACK'); throw error; }
      }
      const bearer = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
      const cookie = req.headers.cookie?.match(/(?:^|; )sr_apple=([^;]+)/)?.[1];
      const auth = db.prepare('SELECT c.*, u.email,u.name,u.family,u.sharing FROM credentials c JOIN users u ON u.id=c.user_id WHERE c.hash=? AND c.expires>? AND c.kind=?')
        .get(hash(bearer ?? cookie ?? ''), Date.now(), bearer ? 'device' : 'session');
      if (!auth) fail(401, 'Sign in or pair this device');
      if (method !== 'GET' && !bearer && req.headers.origin !== csrfOrigin) fail(403, 'Origin required');
      if (path === '/api/apple/logout' && method === 'POST') {
        db.prepare('DELETE FROM credentials WHERE hash=?').run(auth.hash);
        res.setHeader('Set-Cookie', `sr_apple=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0${secure ? '; Secure' : ''}`);
        return send(200, { ok: true });
      }
      if (path === '/api/apple/me' && method === 'GET') return send(200, { id: auth.user_id, name: auth.name, email: auth.email, sharing: !!auth.sharing, demo });
      if (path === '/api/apple/pair-code' && method === 'POST' && auth.kind === 'session') {
        db.prepare("DELETE FROM credentials WHERE user_id=? AND kind='pair'").run(auth.user_id);
        return send(200, { code: issue(db, auth.user_id, 'pair', 'One-time pairing', 600000), expiresIn: 600 });
      }
      if (path === '/api/apple/devices' && method === 'GET') return send(200, { devices: db.prepare("SELECT hash AS id,label,expires FROM credentials WHERE user_id=? AND kind='device' AND expires>?").all(auth.user_id, Date.now()) });
      if (path.startsWith('/api/apple/devices/') && method === 'DELETE' && auth.kind === 'session') {
        db.prepare("DELETE FROM credentials WHERE hash=? AND user_id=? AND kind='device'").run(path.split('/').at(-1), auth.user_id);
        return send(200, { ok: true });
      }
      if (path === '/api/apple/sharing' && method === 'PUT') {
        const body = await readJSON(); exactKeys(body, ['enabled']);
        if (typeof body.enabled !== 'boolean') fail(400, 'enabled must be boolean');
        db.prepare('UPDATE users SET sharing=? WHERE id=?').run(Number(body.enabled), auth.user_id);
        return send(200, { sharing: body.enabled });
      }
      if (path === '/api/apple/summary' && method === 'GET') {
        const records = [...kinds].flatMap(kind => {
          const row = db.prepare('SELECT payload,received FROM health WHERE user_id=? AND kind=? ORDER BY start DESC LIMIT 1').get(auth.user_id, kind);
          return row ? [{ ...JSON.parse(row.payload), received: row.received }] : [];
        });
        return send(200, { records });
      }
      if (path === '/api/apple/health' && method === 'GET') {
        if ([...url.searchParams.keys()].some(k => !['kind', 'before'].includes(k))) fail(400, 'Health can only be read for the signed-in user');
        const kind = url.searchParams.get('kind');
        if (kind && !kinds.has(kind)) fail(400, 'Unknown health category');
        const before = url.searchParams.get('before') ?? '9999';
        const rows = db.prepare('SELECT payload, received FROM health WHERE user_id=? AND (? IS NULL OR kind=?) AND start<? ORDER BY start DESC LIMIT 501').all(auth.user_id, kind, kind, before);
        return send(200, { records: rows.slice(0, 500).map(r => ({ ...JSON.parse(r.payload), received: r.received })), truncated: rows.length > 500 });
      }
      if (path === '/api/apple/family' && method === 'GET') {
        const members = db.prepare('SELECT id,name,sharing FROM users WHERE family=? ORDER BY name').all(auth.family);
        return send(200, { members: members.map(u => {
          const row = u.sharing ? db.prepare('SELECT payload,received FROM locations WHERE user_id=? ORDER BY recorded DESC LIMIT 1').get(u.id) : null;
          return { id: u.id, name: u.name, sharing: !!u.sharing, location: row ? { ...JSON.parse(row.payload), received: row.received } : null };
        }) });
      }
      if (path === '/api/apple/sync' && method === 'POST' && auth.kind === 'device') {
        const body = await readJSON(); exactKeys(body, ['health', 'locations', 'deleted']);
        if (![body.health, body.locations, body.deleted].every(Array.isArray) || body.health.length + body.locations.length + body.deleted.length > 500) fail(400, 'Maximum 500 records per batch');
        const health = body.health.map(healthRecord), locations = body.locations.map(locationRecord);
        if (!body.deleted.every(id => string(id))) fail(400, 'Invalid deletion IDs');
        if (locations.length && !auth.sharing) fail(409, 'Location sharing is paused');
        const received = new Date().toISOString();
        db.exec('BEGIN IMMEDIATE');
        try {
          const put = db.prepare('INSERT INTO health VALUES (?,?,?,?,?,?,?) ON CONFLICT(user_id,id) DO UPDATE SET kind=excluded.kind,start=excluded.start,end=excluded.end,payload=excluded.payload,received=excluded.received');
          for (const r of health) put.run(auth.user_id, r.id, r.kind, r.start, r.end, JSON.stringify(r), received);
          for (const id of body.deleted) db.prepare('DELETE FROM health WHERE user_id=? AND id=?').run(auth.user_id, id);
          for (const r of locations) db.prepare('INSERT OR IGNORE INTO locations VALUES (?,?,?,?,?)').run(auth.user_id, r.id, r.recorded, JSON.stringify(r), received);
          // Location history is deliberately bounded; family API exposes latest only.
          db.prepare('DELETE FROM locations WHERE recorded<?').run(new Date(Date.now() - 30 * 86400000).toISOString());
          db.exec('COMMIT');
        } catch (error) { db.exec('ROLLBACK'); throw error; }
        return send(200, { accepted: health.length + locations.length + body.deleted.length, received });
      }
      if (path === '/api/apple/data' && method === 'DELETE') {
        db.exec('BEGIN IMMEDIATE');
        try {
          db.prepare('DELETE FROM health WHERE user_id=?').run(auth.user_id);
          db.prepare('DELETE FROM locations WHERE user_id=?').run(auth.user_id);
          db.prepare("DELETE FROM credentials WHERE user_id=? AND kind IN ('device','pair')").run(auth.user_id);
          db.prepare('UPDATE users SET sharing=0 WHERE id=?').run(auth.user_id);
          db.exec('COMMIT');
        } catch (error) { db.exec('ROLLBACK'); throw error; }
        return send(200, { ok: true });
      }
      fail(404, 'Not found');
    } catch (error) {
      // Never include records, credentials or request bodies in logs/errors.
      send(error.status ?? 500, { error: error.status ? error.message : 'Internal server error' });
    }
  });
}

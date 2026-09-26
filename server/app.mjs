import QRCode from 'qrcode';
import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { hash, issue } from './store.mjs';
import { demoIdentity, sessionIdentity } from './session.mjs';
import { SEGMENT_GAP_SECONDS, activitiesOf, binSeries, dayBounds, dayIndex, movingSeconds, recordedMetres, segmentsOf } from './movement.mjs';
import { KINDS, catalogue, validateHealthRecord } from './catalogue.mjs';
import { exportPage } from './export.mjs';
import { createDoorbell } from './doorbell.mjs';
/**
 * How long a location history is kept, in days. Enforced by the prune in
 * `sync`, reported by `track` so the day strip can draw the right number of
 * columns — one constant rather than a 30 written in two places that drift.
 */
const RETENTION_DAYS = 30;
/**
 * A ceiling on one track response, so a future change of recording policy
 * cannot turn this endpoint into a megabyte. At the motion gate's present
 * density (~120 fixes a day) the whole retention window is well inside it;
 * the newest points are the ones kept if it is ever hit.
 */
const TRACK_LIMIT = 20000;
const round = (value, places) => Math.round(value * 10 ** places) / 10 ** places;
const iso = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT/.test(value) && Number.isFinite(Date.parse(value));
const bounded = (x, lo, hi) => typeof x === 'number' && Number.isFinite(x) && x >= lo && x <= hi;
const string = (x, max = 200) => typeof x === 'string' && x.length > 0 && x.length <= max;
function fail(status, message) { throw Object.assign(new Error(message), { status }); }
/**
 * One origin is allowed beyond `'self'`, and only for IMAGES.
 *
 * The movement map draws Mapbox raster tiles as plain `<img>` elements rather
 * than running a WebGL map library, and that choice is what keeps this header
 * as tight as it is: a GL map would need `connect-src` for the tile fetches,
 * `worker-src blob:` for its workers and, in practice, a loosened `style-src`.
 * None of that is here. `script-src 'self'` still means the only code that can
 * run on a page showing a month of somebody's whereabouts is code this
 * repository serves.
 *
 * The token itself is the site's public `pk.` one, fetched from Main's
 * `/api/maps/config` on the same origin — so `connect-src 'self'` covers it and
 * this server never holds a Mapbox credential of its own.
 */
const CSP = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: https://api.mapbox.com; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";
function exactKeys(obj, allowed) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj) || Object.keys(obj).some(k => !allowed.includes(k))) fail(400, 'Unexpected fields');
}
const healthRecord = validateHealthRecord;
function locationRecord(r) {
  exactKeys(r, ['id', 'recorded', 'latitude', 'longitude', 'accuracy', 'speed', 'moving']);
  if (!string(r.id) || !iso(r.recorded) || Date.parse(r.recorded) > Date.now() + 300000 || !bounded(r.latitude, -90, 90) || !bounded(r.longitude, -180, 180) || !bounded(r.accuracy, 0, 10000) || !bounded(r.speed, 0, 400) || typeof r.moving !== 'boolean') fail(400, 'Invalid location');
  return { ...r, recorded: new Date(r.recorded).toISOString() };
}
export function createApp(db, { origin = 'http://127.0.0.1:5295', demo = false, authSecret = process.env.AUTH_SECRET, serviceToken = process.env.APPLE_SERVICE_TOKEN, serviceOwner = process.env.APPLE_SERVICE_OWNER, doorbellUrl = process.env.APPLE_DOORBELL_URL, doorbellToken = process.env.APPLE_DOORBELL_TOKEN, fetchImpl = fetch } = {}) {
  const rate = new Map();
  // Its OWN ring-only secret, never the service token — that token can READ
  // the owner's export, and this URL is not guaranteed to stay on loopback the
  // way the service lane is (R5). Unset token or URL = no ring, as before.
  // A misconfiguration that sets the ring token to the SAME value as the
  // service token is treated the same as unset (R9): the read-capable token
  // must never travel over the ring, whatever the operator's env file says.
  const ringToken = doorbellToken && serviceToken && doorbellToken === serviceToken ? undefined : doorbellToken;
  const ring = createDoorbell({ url: doorbellUrl, token: ringToken, fetchImpl });
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
    res.setHeader('Content-Security-Policy', CSP);
    if (secure) res.setHeader('Strict-Transport-Security', 'max-age=31536000');
    try {
      const url = new URL(req.url, origin);
      const path = url.pathname;
      const method = req.method;
      if (method === 'GET' && path === '/healthz') return send(200, { ok: true });
      const assets = { '/apple-app': 'index.html', '/apple-app/': 'index.html', '/apple-app/app.js': 'app.js', '/apple-app/map.js': 'map.js', '/apple-app/movement.js': 'movement.js', '/apple-app/style.css': 'style.css' };
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
      // What the sign-in screen needs before anyone is signed in: which lane
      // exists, and where to send them. Public by necessity — a page that has to
      // authenticate to find out how to authenticate cannot draw itself — and it
      // discloses nothing but a boolean and a URL.
      if (path === '/api/apple/context' && method === 'GET') {
        return send(200, { demo: demo && !secure, signInUrl: `${csrfOrigin}/login?callbackUrl=%2Fapple-app%2F` });
      }
      // The local preview's stand-in for signing in to the main site. Refused
      // outright unless BOTH demo mode is on and the origin is not https, so it
      // cannot exist on production — see session.mjs for why that is two
      // conditions rather than one.
      if (path === '/api/apple/demo-signin' && method === 'POST') {
        if (!demo || secure) fail(404, 'Not found');
        limit(req.socket.remoteAddress);
        const body = await readJSON(); exactKeys(body, ['email']);
        if (!string(body.email, 320)) fail(400, 'Email required');
        res.setHeader('Set-Cookie', `sr_apple_demo=${encodeURIComponent(body.email.toLowerCase())}; HttpOnly; SameSite=Strict; Path=/; Max-Age=43200`);
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
      // THE SERVICE LANE — /health on the same host, reading the owner's
      // journeys so they can sit in its activity list beside the workouts.
      //
      // A third way in, and a deliberately narrow one: ONE endpoint, GET only,
      // ONE person. The token opens nothing else on this server — it is checked
      // here, before the device and browser lanes, and every other path falls
      // through to them as if the token were a stale device credential. The
      // person is fixed by configuration, not by the caller: there is no user
      // parameter, so the family's tracks cannot be asked for by anyone.
      //
      // Read-through, never a copy. /health asks every time and keeps nothing,
      // so this server's thirty-day retention and "delete my data" still mean
      // what they say — a journey pruned here is gone from /health on its next
      // read.
      //
      // Unset token or owner = the endpoint does not exist (404), which is the
      // state of every environment that has not opted in.
      // The service lane's gate, shared by its two endpoints. Returns the
      // configured owner's user id, or null when that person has no account.
      const serviceOwnerId = (allowedParams) => {
        if (!serviceToken || !serviceOwner) fail(404, 'Not found');
        const presented = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1] ?? '';
        // Compared as digests so the lengths always match and the comparison
        // leaks nothing about the token through its timing.
        if (!timingSafeEqual(Buffer.from(hash(presented), 'hex'), Buffer.from(hash(serviceToken), 'hex'))) fail(401, 'Not authorised');
        if ([...url.searchParams.keys()].some(k => !allowedParams.includes(k))) fail(400, 'Only the configured owner can be read');
        return db.prepare('SELECT id FROM users WHERE email=?').get(serviceOwner.toLowerCase())?.id ?? null;
      };
      if (path === '/api/apple/journeys' && method === 'GET') {
        const ownerId = serviceOwnerId(['from', 'to']);
        const now = Math.floor(Date.now() / 1000);
        const rawFrom = url.searchParams.get('from'), rawTo = url.searchParams.get('to');
        const to = rawTo === null || rawTo === '' ? now : Number(rawTo);
        const from = rawFrom === null || rawFrom === '' ? to - RETENTION_DAYS * 86400 : Number(rawFrom);
        if (!Number.isInteger(from) || !Number.isInteger(to) || to <= from || to - from > (RETENTION_DAYS + 1) * 86400) fail(400, 'Invalid window');
        if (!ownerId) return send(200, { from, to, retentionDays: RETENTION_DAYS, journeys: [], workouts: [], truncated: false });
        const fromISO = new Date(from * 1000).toISOString(), toISO = new Date(to * 1000).toISOString();
        const rows = db.prepare(`SELECT payload FROM locations WHERE user_id=? AND recorded>=? AND recorded<? ORDER BY recorded LIMIT ${TRACK_LIMIT + 1}`).all(ownerId, fromISO, toISO);
        const points = rows.slice(0, TRACK_LIMIT).map(r => {
          const p = JSON.parse(r.payload);
          return [round(p.longitude, 6), round(p.latitude, 6), Math.round(Date.parse(p.recorded) / 1000), round(p.accuracy, 1), p.moving ? 1 : 0, round(p.speed, 2)];
        });
        const beats = db.prepare("SELECT payload FROM health WHERE user_id=? AND kind='heart_rate' AND start>=? AND start<? ORDER BY start").all(ownerId, fromISO, toISO)
          .map(r => JSON.parse(r.payload)).map(h => [Math.round(Date.parse(h.start) / 1000), h.value]);
        // The same journeys the map draws — `activitiesOf` is the one definition
        // of what a day's movement was. What counts as an ACTIVITY (on foot,
        // long enough, not already a workout) is /health's decision, not this
        // server's, so the journeys go out whole with their fixes.
        const journeys = activitiesOf(points).filter(a => a.kind === 'journey').map(a => ({
          from: a.from, to: a.to, seconds: a.seconds, metres: a.metres, fixes: a.fixes,
          points: points.slice(a.first, a.last + 1),
          heartRate: beats.filter(([t]) => t >= a.from && t <= a.to),
        }));
        // The phone's own record of the workouts, which reaches this server
        // within the hour. /health's copy arrives through Health Auto Export
        // and can lag it by a day, so without these a walk the Watch recorded
        // would show twice until that export caught up.
        const workouts = db.prepare("SELECT payload FROM health WHERE user_id=? AND kind='workout' AND start<? AND end>? ORDER BY start").all(ownerId, toISO, fromISO)
          .map(r => JSON.parse(r.payload)).map(w => ({ activity: w.activity, start: w.start, end: w.end, source: w.source }));
        return send(200, { from, to, retentionDays: RETENTION_DAYS, journeys, workouts, truncated: rows.length > TRACK_LIMIT });
      }
      // A COPY, unlike journeys (spec E1, E14). Health figures only — location
      // never leaves through here, and "delete my data" does not reach the copy.
      if (path === '/api/apple/export' && method === 'GET') {
        const ownerId = serviceOwnerId(['after', 'limit']);
        const after = Number(url.searchParams.get('after') ?? 0), limit = Number(url.searchParams.get('limit') ?? 2000);
        if (!Number.isInteger(after) || after < 0 || !Number.isInteger(limit) || limit < 1 || limit > 5000) fail(400, 'Invalid cursor');
        if (!ownerId) return send(200, { after, next: after, more: false, earliest: null, earliestByKind: {}, records: [], workouts: [], tombstones: [] });
        return send(200, exportPage(db, ownerId, { after, limit }));
      }
      // Two ways in, and only two.
      //
      //  * A PAIRED IPHONE presents a device token it got from a pairing code.
      //    Unchanged, and deliberately so: the phone has no browser session and
      //    background sync runs while the phone is locked.
      //  * A BROWSER presents the main site's Google session. Same cookie,
      //    same account, same sign-out as the rest of strangeramblings.com.
      //
      // Authentication says WHO; the users table says WHETHER. A signed-in
      // visitor with no row here is a real person who is not in a family on this
      // server, and they get told that rather than being auto-enrolled into one —
      // family membership decides who can see a location, so it is not something
      // to infer from a successful Google login.
      const bearer = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
      let auth = null;
      if (bearer) {
        auth = db.prepare('SELECT c.*, u.email,u.name,u.family,u.sharing FROM credentials c JOIN users u ON u.id=c.user_id WHERE c.hash=? AND c.expires>? AND c.kind=?')
          .get(hash(bearer), Date.now(), 'device') ?? null;
        if (!auth) fail(401, 'Pair this iPhone again');
      } else {
        const email = demoIdentity(req.headers.cookie, { demo, secure })
          ?? (authSecret ? await sessionIdentity(req.headers.cookie, authSecret) : null);
        if (!email) fail(401, 'Sign in at strangeramblings.com');
        const user = db.prepare('SELECT id,email,name,family,sharing FROM users WHERE email=?').get(email);
        if (!user) fail(403, 'This account is not set up on the companion. Ask the owner to add it.');
        // Shaped like a credential row so every handler below reads the same
        // fields whichever lane it arrived on. There is no credential row for a
        // browser any more, so `hash` is null and only the device lane can
        // delete one.
        auth = { hash: null, user_id: user.id, kind: 'session', label: 'Browser', ...user };
      }
      if (method !== 'GET' && !bearer && req.headers.origin !== csrfOrigin) fail(403, 'Origin required');
      if (path === '/api/apple/logout' && method === 'POST') {
        // A device revokes itself. A browser's session belongs to the main site,
        // so signing out happens there — clearing it from here would log the
        // visitor out of a companion that never issued them anything, and leave
        // the real session standing.
        if (auth.kind === 'device') {
          db.prepare('DELETE FROM credentials WHERE hash=?').run(auth.hash);
          return send(200, { ok: true });
        }
        if (demo && !secure) {
          // The preview's session is a cookie THIS server set, and clearing it
          // above has already ended it. Handing back the main site's sign-out
          // URL as well sends the preview to a path this server does not serve,
          // so the browser lands on a 404 having successfully signed out.
          res.setHeader('Set-Cookie', 'sr_apple_demo=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0');
          return send(200, { ok: true });
        }
        return send(200, { ok: true, signOutAt: `${csrfOrigin}/auth/signout` });
      }
      // `owner` is derived here rather than stored, so re-pointing
      // APPLE_SERVICE_OWNER at a different family member changes who the app
      // treats as owner on the next request, with nothing to migrate.
      if (path === '/api/apple/me' && method === 'GET') return send(200, { id: auth.user_id, name: auth.name, email: auth.email, sharing: !!auth.sharing, demo, owner: !!serviceOwner && auth.email === serviceOwner.toLowerCase() });
      if (path === '/api/apple/pair-code' && method === 'POST' && auth.kind === 'session') {
        db.prepare("DELETE FROM credentials WHERE user_id=? AND kind='pair'").run(auth.user_id);
        const code = issue(db, auth.user_id, 'pair', 'One-time pairing', 600000);
        const payload = JSON.stringify({ type: 'sr-companion-pair', version: 1, server: csrfOrigin, code });
        const qr = await QRCode.toDataURL(payload, { errorCorrectionLevel: 'M', margin: 4, scale: 6 });
        return send(200, { code, qr, expiresIn: 600 });
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
        // The dashboard's tiles only ever draw the legacy kinds (labels exist
        // for those five, nothing else); looping every catalogued kind meant
        // up to 35 point lookups a call for tiles nothing shows.
        const records = Object.keys(catalogue.legacyKinds).flatMap(kind => {
          const row = db.prepare('SELECT payload,received FROM health WHERE user_id=? AND kind=? ORDER BY start DESC LIMIT 1').get(auth.user_id, kind);
          return row ? [{ ...JSON.parse(row.payload), received: row.received }] : [];
        });
        return send(200, { records });
      }
      if (path === '/api/apple/health' && method === 'GET') {
        if ([...url.searchParams.keys()].some(k => !['kind', 'before'].includes(k))) fail(400, 'Health can only be read for the signed-in user');
        const kind = url.searchParams.get('kind');
        if (kind && !KINDS.has(kind)) fail(400, 'Unknown health category');
        const before = url.searchParams.get('before') ?? '9999';
        // Unfiltered, this fed the dashboard's list — which has no way to draw a
        // route/series chunk and no `value` to show for one (see app.js). An
        // explicit `?kind=workout_route` still reads them; only the "everything"
        // view excludes the megabyte-sized `points` arrays.
        const rows = db.prepare(`SELECT payload, received FROM health WHERE user_id=? AND ((? IS NULL AND kind NOT IN ('workout_route','workout_series')) OR kind=?) AND start<? ORDER BY start DESC LIMIT 501`).all(auth.user_id, kind, kind, before);
        return send(200, { records: rows.slice(0, 500).map(r => ({ ...JSON.parse(r.payload), received: r.received })), truncated: rows.length > 500 });
      }
      // Your own movement, for the map on the dashboard.
      //
      // OWNER-SCOPED, like /health, and for a sharper reason than /health has.
      // `family` shares a LATEST position; this shares a HISTORY, and the two
      // are not the same disclosure. A pin says where somebody is now. A month
      // of pins says where they sleep, where they work, which school gate they
      // stand at and who they visit on a Tuesday. So there is no user
      // parameter here to reject — only the signed-in person's own track
      // exists as far as this endpoint is concerned, on either lane.
      //
      // Reading your own history does NOT depend on the sharing switch: that
      // switch governs uploading and what the family can see, and turning it
      // off should not lock you out of what you already recorded.
      if (path === '/api/apple/track' && method === 'GET') {
        if ([...url.searchParams.keys()].some(k => !['offset', 'date'].includes(k))) fail(400, 'Movement can only be read for the signed-in user');
        // `Number(null)` and `Number('')` are both 0 rather than NaN, so an
        // absent or empty parameter has to be recognised BEFORE the conversion.
        // The native lane shipped that bug into review once already.
        const raw = url.searchParams.get('offset');
        const offset = raw === null || raw === '' ? 0 : Number(raw);
        if (!Number.isInteger(offset) || Math.abs(offset) > 840) fail(400, 'Invalid timezone offset');
        const date = url.searchParams.get('date');
        if (date !== null && !/^\d{4}-\d\d-\d\d$/.test(date)) fail(400, 'Invalid date');
        const rows = db.prepare(`SELECT payload FROM locations WHERE user_id=? ORDER BY recorded DESC LIMIT ${TRACK_LIMIT + 1}`).all(auth.user_id);
        const points = rows.slice(0, TRACK_LIMIT).reverse().map(r => {
          const p = JSON.parse(r.payload);
          return [round(p.longitude, 6), round(p.latitude, 6), Math.round(Date.parse(p.recorded) / 1000), round(p.accuracy, 1), p.moving ? 1 : 0, round(p.speed, 2)];
        });
        const body = { days: dayIndex(points, offset), truncated: rows.length > TRACK_LIMIT, gapSeconds: SEGMENT_GAP_SECONDS, retentionDays: RETENTION_DAYS };
        if (date === null) return send(200, body);
        const [from, to] = dayBounds(date, offset);
        const day = points.filter(p => p[2] >= from && p[2] < to);
        const segments = segmentsOf(day);
        // `segments` says where a LINE may be drawn — continuous recording.
        // `activities` says what the day was — journeys and the stops between
        // them, judged on movement rather than on the presence of data. They
        // are different questions and the map needs both.
        const activities = activitiesOf(day);
        return send(200, { ...body, date, from, to, points: day, segments, activities, totals: { fixes: day.length, metres: Math.round(recordedMetres(day, segments)), movingSeconds: movingSeconds(day, segments), journeys: activities.filter(a => a.kind === 'journey').length } });
      }
      // The health that goes UNDER the map: one window, every signal that can
      // be laid against a track.
      //
      // Separate from /health because it answers a different question. /health
      // pages backwards through raw records 500 at a time; this bins a window
      // into something a chart can draw — a day holds roughly 800 heart-rate
      // samples and no axis 700 pixels wide can honestly show them all.
      if (path === '/api/apple/timeline' && method === 'GET') {
        if ([...url.searchParams.keys()].some(k => !['from', 'to', 'bins'].includes(k))) fail(400, 'Health can only be read for the signed-in user');
        const from = Number(url.searchParams.get('from'));
        const to = Number(url.searchParams.get('to'));
        if (!Number.isInteger(from) || !Number.isInteger(to) || to <= from || to - from > 8 * 86400) fail(400, 'Invalid window');
        const rawBins = url.searchParams.get('bins');
        const bins = rawBins === null || rawBins === '' ? 288 : Number(rawBins);
        if (!Number.isInteger(bins) || bins < 1 || bins > 1440) fail(400, 'Invalid bin count');
        const fromISO = new Date(from * 1000).toISOString(), toISO = new Date(to * 1000).toISOString();
        const started = kind => db.prepare('SELECT payload FROM health WHERE user_id=? AND kind=? AND start>=? AND start<? ORDER BY start').all(auth.user_id, kind, fromISO, toISO).map(r => JSON.parse(r.payload));
        // Sleep, workouts and a daily step total are SPANS, not instants. A
        // night that began before midnight belongs to the morning it ends in
        // as much as to the evening it started in, so they are selected by
        // OVERLAP. Selecting them by start alone loses every night's sleep.
        const spanning = kind => db.prepare('SELECT payload FROM health WHERE user_id=? AND kind=? AND start<? AND end>? ORDER BY start').all(auth.user_id, kind, toISO, fromISO).map(r => JSON.parse(r.payload));
        const resting = db.prepare("SELECT payload FROM health WHERE user_id=? AND kind='resting_heart_rate' AND start<? ORDER BY start DESC LIMIT 1").get(auth.user_id, toISO);
        return send(200, {
          from, to,
          heartRate: binSeries(started('heart_rate'), from, to, bins),
          restingHeartRate: resting ? { value: JSON.parse(resting.payload).value, at: JSON.parse(resting.payload).start } : null,
          // Returned as RECORDS rather than a total on purpose. The phone
          // uploads one cumulative-sum row per calendar day, so a window can
          // legitimately overlap two of them, and adding those together would
          // report a number neither day ever had. The caller picks the record
          // that matches the day it is drawing and says whose total it is.
          steps: spanning('steps').map(s => ({ value: s.value, start: s.start, end: s.end, source: s.source })),
          workouts: spanning('workout').map(w => ({ activity: w.activity, start: w.start, end: w.end, seconds: w.value, distance: w.distance ?? null, energy: w.energy ?? null, source: w.source })),
          sleep: spanning('sleep').map(s => ({ stage: s.stage, start: s.start, end: s.end, source: s.source }))
        });
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
        // Resolved once per request rather than per call site: the tombstone
        // gate below and the doorbell ring at the end of this handler both
        // need "is this upload from the configured owner", and a stale second
        // lookup could answer it differently mid-request.
        const ownerId = serviceOwner ? db.prepare('SELECT id FROM users WHERE email=?').get(serviceOwner.toLowerCase())?.id ?? null : null;
        db.exec('BEGIN IMMEDIATE');
        try {
          const put = db.prepare('INSERT INTO health VALUES (?,?,?,?,?,?,?) ON CONFLICT(user_id,id) DO UPDATE SET kind=excluded.kind,start=excluded.start,end=excluded.end,payload=excluded.payload,received=excluded.received');
          const unstone = db.prepare('DELETE FROM health_deleted WHERE user_id=? AND id=?');
          for (const r of health) { put.run(auth.user_id, r.id, r.kind, r.start, r.end, JSON.stringify(r), received); unstone.run(auth.user_id, r.id); }
          // A deletion must reach /health's COPY, so it is remembered as a
          // tombstone the export hands on (spec E8). A workout's route and
          // series chunks go with it: they have no HealthKit identity of their
          // own, and /health drops them through the activity's cascade.
          //
          // Only the configured owner's deletions are worth remembering this
          // way (R7): /health only ever reads the owner's export, so a
          // tombstone for anyone else — or for an unconfigured lane — would
          // sit in the table forever, read by nobody. The deletion itself
          // still applies to every uploader.
          const find = db.prepare('SELECT kind, start FROM health WHERE user_id=? AND id=?');
          const stone = db.prepare('INSERT INTO health_deleted VALUES (?,?,?,?,?) ON CONFLICT(user_id,id) DO UPDATE SET kind=excluded.kind,start=excluded.start,deleted=excluded.deleted');
          for (const id of body.deleted) {
            const row = find.get(auth.user_id, id);
            if (!row) continue;
            if (ownerId && auth.user_id === ownerId) stone.run(auth.user_id, id, row.kind, row.start, received);
            db.prepare('DELETE FROM health WHERE user_id=? AND id=?').run(auth.user_id, id);
            if (row.kind === 'workout') db.prepare("DELETE FROM health WHERE user_id=? AND kind IN ('workout_route','workout_series') AND json_extract(payload,'$.workout')=?").run(auth.user_id, id);
          }
          for (const r of locations) db.prepare('INSERT OR IGNORE INTO locations VALUES (?,?,?,?,?)').run(auth.user_id, r.id, r.recorded, JSON.stringify(r), received);
          // Location history is deliberately bounded; family API exposes latest
          // only, and `track` exposes this window to its owner and nobody else.
          db.prepare('DELETE FROM locations WHERE recorded<?').run(new Date(Date.now() - RETENTION_DAYS * 86400000).toISOString());
          db.exec('COMMIT');
        } catch (error) { db.exec('ROLLBACK'); throw error; }
        if ((health.length || body.deleted.length) && ownerId && auth.user_id === ownerId) ring();
        return send(200, { accepted: health.length + locations.length + body.deleted.length, received });
      }
      if (path === '/api/apple/data' && method === 'DELETE') {
        db.exec('BEGIN IMMEDIATE');
        try {
          db.prepare('DELETE FROM health WHERE user_id=?').run(auth.user_id);
          db.prepare('DELETE FROM health_deleted WHERE user_id=?').run(auth.user_id);
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

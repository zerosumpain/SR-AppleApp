import { openStore, pruneStore } from './store.mjs';
import { createApp } from './app.mjs';
const port = Number(process.env.PORT ?? 5295);
if (!process.env.APP_ORIGIN) throw new Error('APP_ORIGIN is required');
const demo = process.env.DEMO_MODE === '1';
const secure = new URL(process.env.APP_ORIGIN).protocol === 'https:';
// The browser authority keeps AUTH_SECRET; the companion holds one audience key.
if (secure && (!process.env.SESSION_INTROSPECTION_URL || (process.env.SESSION_INTROSPECTION_TOKEN?.length ?? 0) < 32 || !process.env.SESSION_INTROSPECTION_AUDIENCE)) {
  throw new Error('Session introspection configuration is required');
}
process.umask(0o077);
const db = openStore(process.env.DATABASE_PATH ?? './data/apple.sqlite');
pruneStore(db);
const retention = setInterval(() => pruneStore(db), 60 * 60_000);
retention.unref();
const app = createApp(db, { origin: process.env.APP_ORIGIN, demo, authSecret: process.env.AUTH_SECRET });
app.listen(port, process.env.APPLE_BIND || '0.0.0.0', () => console.log(`SR AppleApp listening on ${port}`));
process.on('SIGTERM', () => app.close(() => { db.close(); process.exit(0); }));

import { openStore } from './store.mjs';
import { createApp } from './app.mjs';
const port = Number(process.env.PORT ?? 5295);
if (!process.env.APP_ORIGIN) throw new Error('APP_ORIGIN is required');
const demo = process.env.DEMO_MODE === '1';
const secure = new URL(process.env.APP_ORIGIN).protocol === 'https:';
// Browsers sign in with the main site's session, which cannot be read without
// this. Refusing to start is the point: without it every browser request 401s
// and the service looks healthy while nobody can get in — the phone would keep
// syncing on its device token and hide the fault for days.
if (secure && !process.env.AUTH_SECRET) {
  throw new Error('AUTH_SECRET is required — it is how the main site\'s session is verified. Copy it from the site\'s environment.');
}
const db = openStore(process.env.DATABASE_PATH ?? './data/apple.sqlite');
const app = createApp(db, { origin: process.env.APP_ORIGIN, demo, authSecret: process.env.AUTH_SECRET });
app.listen(port, '0.0.0.0', () => console.log(`SR AppleApp listening on ${port}`));
process.on('SIGTERM', () => app.close(() => { db.close(); process.exit(0); }));

import { openStore } from './store.mjs';
import { createApp } from './app.mjs';
const port = Number(process.env.PORT ?? 5295);
if (!process.env.APP_ORIGIN) throw new Error('APP_ORIGIN is required');
const db = openStore(process.env.DATABASE_PATH ?? './data/apple.sqlite');
const app = createApp(db, { origin: process.env.APP_ORIGIN, demo: process.env.DEMO_MODE === '1' });
app.listen(port, '0.0.0.0', () => console.log(`SR AppleApp listening on ${port}`));
process.on('SIGTERM', () => app.close(() => { db.close(); process.exit(0); }));

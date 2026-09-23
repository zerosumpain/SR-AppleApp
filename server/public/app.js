const $ = id => document.getElementById(id);
const labels = { steps: 'Steps', heart_rate: 'Heart rate', resting_heart_rate: 'Resting heart rate', sleep: 'Sleep', workout: 'Workouts' };
const when = stamp => new Date(stamp).toLocaleString();
const node = (tag, text, className) => { const n = document.createElement(tag); n.textContent = text; if (className) n.className = className; return n; };
function error(message) { $('error').textContent = message; $('error').hidden = !message; }
async function api(path, method = 'GET', body) {
  const response = await fetch(`/api/apple/${path}`, { method, headers: body === undefined ? {} : { 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Request failed');
  return result;
}
async function action(fn) { error(''); try { await fn(); } catch (e) { error(e.message); } }
function value(r) {
  if (r.kind === 'sleep') return `${r.stage.replaceAll('_', ' ')} · ${((Date.parse(r.end) - Date.parse(r.start)) / 3600000).toFixed(1)} h`;
  if (r.kind === 'workout') return `${r.activity} · ${Math.round(r.value / 60)} min`;
  // A workout_route/workout_series chunk has no `value` — an explicit
  // `?kind=` can still return one, and it must not throw the row away.
  if (r.value === undefined) return `${r.points?.length ?? 0} points`;
  return `${r.value.toLocaleString()} ${r.unit}`;
}
async function health() {
  const category = $('category').value;
  const { records, truncated } = await api(`health${category ? `?kind=${category}` : ''}`);
  $('records').replaceChildren();
  if (!records.length) $('records').append(node('p', 'No uploaded records in this category. Pair your iPhone and sync to get started.'));
  for (const r of records) {
    const row = node('div', '', 'row'), description = node('div', ''), timing = node('div', '');
    description.append(node('strong', `${labels[r.kind] ?? r.kind.replace(/_/g, ' ')} · ${value(r)}`), node('p', r.source, 'muted'));
    timing.append(node('time', when(r.start)), node('p', `Received ${when(r.received)}`, 'muted'));
    row.append(description, timing); $('records').append(row);
  }
  if (truncated) $('records').append(node('p', 'Showing the latest 500 records. Choose a category to narrow the view.', 'muted'));
  if (!category) {
    const summary = await api('summary');
    $('metrics').replaceChildren();
    for (const [kind, label] of Object.entries(labels)) {
      const r = summary.records.find(x => x.kind === kind), tile = node('div', '', 'metric');
      tile.append(node('small', label.toUpperCase()), node('strong', r ? value(r) : '—'), node('small', r ? `Latest record · ${when(r.start)}` : 'No uploaded data', 'when'));
      $('metrics').append(tile);
    }
  }
}
async function family() {
  const { members } = await api('family'); $('members').replaceChildren();
  for (const m of members) {
    const row = node('div', '', 'row'), left = node('div', ''); left.append(node('h3', m.name));
    if (!m.sharing) left.append(node('p', 'Location sharing is paused.'));
    else if (!m.location) left.append(node('p', 'Waiting for a first location.'));
    else {
      const l = m.location, stale = Date.now() - Date.parse(l.recorded) > 20 * 60000;
      left.append(node('p', `${l.latitude.toFixed(5)}, ${l.longitude.toFixed(5)} · accuracy ±${Math.round(l.accuracy)} m`));
      left.append(node('p', `${stale ? 'Stale location' : 'Last recorded'} · ${when(l.recorded)} · ${l.moving ? 'Moving' : 'Stationary'}`, 'muted'));
      left.append(node('p', `Received ${when(l.received)}`, 'muted'));
      const link = node('a', 'Open in Apple Maps ↗'); link.href = `https://maps.apple.com/?ll=${l.latitude},${l.longitude}`; link.target = '_blank'; link.rel = 'noopener noreferrer'; left.append(link);
    }
    row.append(left); $('members').append(row);
  }
}
async function devices() {
  const result = await api('devices'); $('devices').replaceChildren();
  if (!result.devices.length) $('devices').append(node('p', 'No paired devices yet.'));
  for (const d of result.devices) {
    const row = node('div', '', 'row'), revoke = node('button', 'Revoke');
    revoke.onclick = () => action(async () => { await api(`devices/${d.id}`, 'DELETE'); await devices(); });
    row.append(node('p', `${d.label} · expires ${when(d.expires)}`), revoke); $('devices').append(row);
  }
}
async function load() {
  const me = await api('me'); $('login').hidden = true; $('dashboard').hidden = false; $('logout').hidden = false;
  $('owner').textContent = `${me.name} · only you can view these health records.`;
  $('sharing').checked = me.sharing; $('server-address').value = location.origin;
  $('notice').hidden = !me.demo;
  $('notice').textContent = 'LOCAL TEST ENVIRONMENT · Synthetic family and health data. This preview is separate from the live Strange Ramblings site.';
  await Promise.all([
    health(),
    family(),
    devices(),
    // Best effort: this one talks to a different process, and the companion's
    // own dashboard must still render if the main site is down.
    siteDevices().catch(() => { $('site-devices').replaceChildren(node('p', 'Could not reach the main site for the chat and news devices.', 'muted')); })
  ]);
}
// The local preview's sign-in. The endpoint behind it 404s on production, so
// revealing the form there would be an invitation to a door that is not real —
// `demoAvailable` is reported by the server, never guessed from the hostname.
// The preview lane changes identity WITHOUT a page load, so anything already
// drawn from the last account has to go before the next one's data arrives.
$('demo-form').onsubmit = e => { e.preventDefault(); action(async () => { await api('demo-signin', 'POST', { email: $('email').value }); window.SRMovement.reset(); await load(); }); };
// Signing out belongs to the main site: this server never issued the session, so
// clearing anything here would leave the real one standing.
$('logout').onclick = () => action(async () => { const r = await api('logout', 'POST', {}); window.SRMovement.reset(); location.href = r.signOutAt ?? location.pathname; });
/**
 * The OTHER credential a phone can hold: the one that reads chat and the news
 * desk on the main site.
 *
 * Both pairings live on this page now, but only the UI moved. These calls go to
 * `/api/admin/native-devices`, which is served by the MAIN SITE on the same
 * hostname and sits behind its ordinary owner gate — so this server never mints,
 * stores or even sees a site credential. The QR arrives already rendered as a
 * data URL for the same reason: drawing it here would mean vendoring a QR
 * library into this server's bundle to handle a token that is none of its
 * business.
 */
async function siteApi(path = '', method = 'GET') {
  const response = await fetch(`/api/admin/native-devices${path}`, { method });
  const result = await response.json().catch(() => ({}));
  if (response.status === 401) throw new Error('Sign in to Strange Ramblings first.');
  if (!response.ok) throw new Error(result.error || 'The main site could not answer that.');
  return result;
}

async function siteDevices() {
  const target = $('site-devices');
  target.replaceChildren();
  const { devices } = await siteApi();
  if (!devices.length) { target.append(node('p', 'No iPhone is connected to chat and news yet.', 'muted')); return; }
  for (const d of devices) {
    const revoked = d.revokedAt || new Date(d.expiresAt) < new Date();
    const row = node('div', '', 'row');
    const label = `${d.label ?? 'iPhone'} · ${revoked ? 'revoked' : `last seen ${d.lastUsedAt ? when(d.lastUsedAt) : 'never'}`}`;
    row.append(node('p', label));
    if (!revoked) {
      const revoke = node('button', 'Revoke');
      revoke.onclick = () => action(async () => { await siteApi(`?id=${encodeURIComponent(d.id)}`, 'DELETE'); await siteDevices(); });
      row.append(revoke);
    }
    target.append(row);
  }
}

$('site-pair').onclick = () => action(async () => {
  const result = await siteApi('', 'POST');
  $('site-pair-qr').src = result.qr;
  $('site-pair-result').hidden = false;
  $('site-pair-expiry').textContent = `Single use. Expires ${when(result.expiresAt)}. Creating another cancels this one.`;
  await siteDevices();
});

$('refresh').onclick = () => action(load);
$('category').onchange = () => action(health);
let pairingExpiryTimer;
function clearPairing() {
  clearTimeout(pairingExpiryTimer);
  $('pair-result').hidden = true;
  $('pair-code').textContent = '';
  $('pair-qr').removeAttribute('src');
}
$('pair').onclick = () => action(async () => {
  $('pair').disabled = true;
  clearPairing();
  try {
    const result = await api('pair-code', 'POST', {});
    $('pair-code').textContent = result.code;
    $('pair-qr').src = result.qr;
    $('pair-result').hidden = false;
    $('pair-expiry').textContent = `Valid for one connection. Expires at ${new Date(Date.now() + result.expiresIn * 1000).toLocaleTimeString()}.`;
    $('pair').textContent = 'Create a new pairing QR code';
    pairingExpiryTimer = setTimeout(() => {
      $('pair-code').textContent = '';
      $('pair-qr').removeAttribute('src');
      $('pair-qr').hidden = true;
      $('pair-expiry').textContent = 'This pairing code has expired. Create a new one above.';
    }, result.expiresIn * 1000);
    $('pair-qr').hidden = false;
  } finally { $('pair').disabled = false; }
});
$('copy-code').onclick = () => action(async () => {
  if (!$('pair-code').textContent) throw new Error('Create a new pairing code first.');
  await navigator.clipboard.writeText($('pair-code').textContent);
  $('pair-expiry').textContent = 'Pairing code copied. Paste it into the iPhone app before it expires.';
});
$('sharing').onchange = () => action(async () => { try { await api('sharing', 'PUT', { enabled: $('sharing').checked }); } catch(e) { $('sharing').checked = !$('sharing').checked; throw e; } await family(); });
$('delete').onclick = () => { if (confirm('Delete all your uploaded health and location data and revoke your devices?')) action(async () => { await api('data', 'DELETE'); clearPairing(); await load(); }); };
for (const button of document.querySelectorAll('[data-tab]')) button.onclick = () => action(async () => {
  for (const b of document.querySelectorAll('[data-tab]')) { const active = b === button; b.setAttribute('aria-pressed', String(active)); $(b.dataset.tab).hidden = !active; }
  // Movement loads itself, and only when asked: it is the one tab that pulls a
  // month of geometry and a day of health, and most visits never open it.
  if (button.dataset.tab === 'movement') await window.SRMovement.open();
  if (button.dataset.tab === 'family') await family();
  if (button.dataset.tab === 'settings') await devices();
});
// Try to load. If nobody is signed in, draw the sign-in the SERVER says exists
// rather than the one the hostname suggests — the demo lane 404s on production,
// and offering a door that is not there is worse than offering none.
load().catch(async (e) => {
  const signInNeeded = /^Sign in at |^This account is not set up/.test(e.message);
  if (!signInNeeded) { error(e.message); return; }
  try {
    const context = await api('context');
    $('demo-form').hidden = !context.demo;
    $('login-link').hidden = context.demo;
    $('login-link').href = context.signInUrl;
    if (context.demo) $('login-copy').textContent = 'Local preview. There is no password — name one of the synthetic accounts.';
  } catch {
    // Context is best effort; the Google link in the markup is the safe default.
  }
  // "Not set up on the companion" is a different problem from "not signed in",
  // and telling somebody to sign in when they already have is a loop.
  if (/^This account is not set up/.test(e.message)) error(e.message);
});

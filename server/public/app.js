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
  return `${r.value.toLocaleString()} ${r.unit}`;
}
async function health() {
  const category = $('category').value;
  const { records, truncated } = await api(`health${category ? `?kind=${category}` : ''}`);
  $('records').replaceChildren();
  if (!records.length) $('records').append(node('p', 'No uploaded records in this category. Pair your iPhone and sync to get started.'));
  for (const r of records) {
    const row = node('div', '', 'row'), description = node('div', ''), timing = node('div', '');
    description.append(node('strong', `${labels[r.kind]} · ${value(r)}`), node('p', r.source, 'muted'));
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
  await Promise.all([health(), family(), devices()]);
}
$('login-form').onsubmit = e => { e.preventDefault(); action(async () => { await api('login', 'POST', { email: $('email').value, password: $('password').value }); $('password').value = ''; await load(); }); };
$('logout').onclick = () => action(async () => { await api('logout', 'POST', {}); location.reload(); });
$('refresh').onclick = () => action(load);
$('category').onchange = () => action(health);
$('pair').onclick = () => action(async () => { const result = await api('pair-code', 'POST', {}); $('pair-code').textContent = result.code; });
$('sharing').onchange = () => action(async () => { try { await api('sharing', 'PUT', { enabled: $('sharing').checked }); } catch(e) { $('sharing').checked = !$('sharing').checked; throw e; } await family(); });
$('delete').onclick = () => { if (confirm('Delete all your uploaded health and location data and revoke your devices?')) action(async () => { await api('data', 'DELETE'); $('pair-code').textContent = ''; await load(); }); };
for (const button of document.querySelectorAll('[data-tab]')) button.onclick = () => action(async () => {
  for (const b of document.querySelectorAll('[data-tab]')) { const active = b === button; b.setAttribute('aria-pressed', String(active)); $(b.dataset.tab).hidden = !active; }
  if (button.dataset.tab === 'family') await family();
  if (button.dataset.tab === 'settings') await devices();
});
load().catch(e => { if (e.message !== 'Sign in or pair this device') error(e.message); });

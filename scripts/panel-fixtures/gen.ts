// Golden desk fixtures for the iPhone's PanelReducer, produced by the REAL web
// code: Core's applyPanelOps + TurnDesk, then Main's nativePanel (the phone's
// keep() filter). Ops a web client would drop (panelOpSchema.safeParse fails)
// are dropped here exactly as ChatArea.deskTurnOp does.
// `@core` and `@main` are resolved by build.mjs to the two checkouts.
import { applyPanelOps } from '@core/jkai/panel/apply';
import { TurnDesk } from '@core/jkai/panel/turn-desk';
import { panelOpSchema, type PanelOp } from '@core/jkai/panel/schema';
import { nativePanel } from '@main/jkai/native-rich';
import { writeFileSync } from 'node:fs';

const out = process.argv[2];
const source = process.argv[3];

const ok = (data: unknown) => ({ success: true, data });
const search = (id: string, urls: string[]) => ({
  tool: 'web_search', args: { query: id }, result: ok({ web: urls.map((u) => ({ url: u, title: u })) }), status: 'done' as const, toolCallId: id,
});
const rows = (id: string, title = 'a') => ({ id, type: 'rows', rows: [{ id: 'r', title }] });

type Case = { name: string; note: string; ops: unknown[]; final?: unknown };
const cases: Case[] = [];

// 1. A real producer: what TurnDesk streams for a two-search turn, then its finish ops.
{
  const emitted: PanelOp[] = [];
  const desk = new TurnDesk((op) => emitted.push(op));
  desk.setRoute({ kind: 'task', domains: ['travel'], query: 'what time does the rome flight leave on monday' });
  desk.onToolResult(search('c1', ['https://a.example/1', 'https://b.example/2']));
  desk.onToolResult(search('c2', ['https://c.example/3']));
  const { page, ops } = desk.finish();
  cases.push({ name: 'turn-desk-two-searches', note: 'TurnDesk emitted ops for two web searches, then finish() ops; final is done.result.panel', ops: [...emitted, ...ops], final: page });
}
// 2. A health turn: readiness then a search (sections health-readiness, sources, health-next).
{
  const emitted: PanelOp[] = [];
  const desk = new TurnDesk((op) => emitted.push(op));
  desk.setRoute({ kind: 'task', domains: ['health'], query: 'current fitness level' });
  desk.onToolResult({ tool: 'health_readiness', args: {}, result: ok({ label: 'Ready', score: 73, factors: { recovery: { value: 51, weight: 0.4 } } }), status: 'done', toolCallId: 'h1' });
  desk.onToolResult(search('c1', ['https://a.example/1']));
  const { page, ops } = desk.finish();
  cases.push({ name: 'turn-desk-health', note: 'TurnDesk ops for a health turn with a search', ops: [...emitted, ...ops], final: page });
}
// 3. A casual turn: just quiet.
{
  const emitted: PanelOp[] = [];
  const desk = new TurnDesk((op) => emitted.push(op));
  desk.setRoute({ kind: 'casual', domains: [], query: '' });
  desk.finish();
  cases.push({ name: 'turn-desk-casual-quiet', note: 'a casual turn emits only quiet and has no page', ops: emitted, final: null });
}
cases.push({ name: 'upsert-in-place', note: 'apply.test.ts: replaces a block in place by id (replay-safe)',
  ops: [{ kind: 'upsert', section: 's', block: rows('a', 'one') }, { kind: 'upsert', section: 's', block: rows('b') }, { kind: 'upsert', section: 's', block: rows('a', 'two') }] });
cases.push({ name: 'upsert-moves-section', note: 'apply.test.ts: moves a block when upserted into another section (the emptied section stays in the raw page)',
  ops: [{ kind: 'upsert', section: 's1', sectionLabel: 'One', block: rows('a') }, { kind: 'upsert', section: 's2', sectionLabel: 'Two', block: rows('a') }] });
cases.push({ name: 'cap-40', note: 'apply.test.ts: caps the PAGE at MAX_BLOCKS_PER_PAGE (40) across sections; an existing id still updates. Kept to <=24 per section, the schema section cap, or nativePanel would refuse the page',
  ops: [
    ...Array.from({ length: 20 }, (_, i) => ({ kind: 'upsert', section: 's1', block: rows(`a${i}`) })),
    ...Array.from({ length: 25 }, (_, i) => ({ kind: 'upsert', section: 's2', block: rows(`b${i}`) })),
    { kind: 'upsert', section: 's2', block: rows('b3', 'updated') },
  ] });
cases.push({ name: 'head-quiet-remove-reset', note: 'apply.test.ts: head with producer, quiet cleared by an upsert, remove, reset',
  ops: [
    { kind: 'head', head: { kicker: 'Health', context: ['health'], title: 'Load' }, producer: 'context' },
    { kind: 'quiet' },
    { kind: 'upsert', section: 's', block: rows('a') },
    { kind: 'upsert', section: 't', sectionLabel: 'Later', block: rows('b') },
    { kind: 'remove', id: 'a' },
    { kind: 'reset' },
    { kind: 'upsert', section: 'm-lead', sectionLabel: 'Model', block: { id: 'm:p', type: 'prose', markdown: 'Rebuilt' } },
  ] });
cases.push({ name: 'replay-twice', note: 'a reconnect that replays ops already applied lands on the same page',
  ops: [
    { kind: 'head', head: { kicker: 'This turn', context: [], title: 'Mail' } },
    { kind: 'upsert', section: 'mail', sectionLabel: 'Mail', block: rows('m1', 'First') },
    { kind: 'upsert', section: 'mail', block: rows('m2', 'Second') },
    { kind: 'head', head: { kicker: 'This turn', context: [], title: 'Mail' } },
    { kind: 'upsert', section: 'mail', sectionLabel: 'Mail', block: rows('m1', 'First') },
    { kind: 'upsert', section: 'mail', block: rows('m2', 'Second') },
  ] });
cases.push({ name: 'phone-keep-filter', note: "Main nativePanel keep(): artifact blocks and non-ask/link actions never reach the phone; a section left empty is dropped",
  ops: [
    { kind: 'upsert', section: 'charts', sectionLabel: 'Charts', block: { id: 'art', type: 'artifact', artifact: { type: 'chart', spec: {} } } },
    { kind: 'upsert', section: 'mixed', block: { id: 'act', type: 'actions', items: [
      { id: 'p', label: 'Post', kind: 'post', endpoint: '/api/x' },
      { id: 'q', label: 'Ask', kind: 'ask', ask: { label: 'Draft', detail: 'Draft week 8' } },
    ] } },
    { kind: 'upsert', section: 'mixed', block: { id: 'only-post', type: 'actions', items: [{ id: 'c', label: 'Delete', kind: 'confirm', endpoint: '/api/y' }] } },
    { kind: 'upsert', section: 'mixed', block: { id: 'grp', type: 'group', blocks: [
      { id: 'g-art', type: 'artifact', artifact: {} },
      { id: 'g-kv', type: 'kv', items: [{ label: 'x', value: 'y' }] },
    ] } },
  ] });
cases.push({ name: 'dropped-ops', note: 'ops the web drops at safeParse (unknown kind, missing section, block without id) change nothing',
  ops: [
    { kind: 'upsert', section: 's', block: rows('a') },
    { kind: 'teleport', to: 'mars' },
    { kind: 'upsert', block: rows('b') },
    { kind: 'upsert', section: 's', block: { type: 'rows', rows: [] } },
    { kind: 'remove' },
    'not an op',
    null,
    { kind: 'upsert', section: 's', block: rows('c') },
  ] });

const fixtures = cases.map((c) => {
  const valid = c.ops.map((o) => panelOpSchema.safeParse(o)).filter((r) => r.success).map((r) => r.data as PanelOp);
  const raw = applyPanelOps(null, valid);
  const phone = raw ? nativePanel({ panel: raw }) : null;
  const final = c.final === undefined ? undefined : (c.final === null ? null : nativePanel({ panel: c.final }));
  return {
    name: c.name,
    note: c.note,
    ops: c.ops,
    // The web reducer's page, before the phone filter: section ids and block ids, in order.
    raw: raw ? raw.sections.map((s) => ({ id: s.id, label: s.label, blocks: s.blocks.map((b) => b.id) })) : null,
    rawQuiet: raw ? raw.quiet : null,
    rawProducer: raw ? raw.producer : null,
    // What the phone's drawer must show: nativePanel(applyPanelOps(null, ops)).
    page: phone,
    // done.result.panel for this turn (raw, as the server sends it) and what the phone shows for it.
    ...(c.final === undefined ? {} : { done: c.final, donePage: final }),
  };
});

writeFileSync(out, JSON.stringify({ source, generator: 'SR-AppleApp scripts/panel-fixtures/generate.sh', cases: fixtures }, null, 2) + '\n');
console.log(`wrote ${fixtures.length} cases to ${out}`);

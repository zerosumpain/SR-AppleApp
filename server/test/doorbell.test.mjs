import test from 'node:test';
import assert from 'node:assert/strict';
import { createDoorbell } from '../doorbell.mjs';

// R7 minors: a non-ok ring is logged by STATUS only (never the token), its
// response body is released rather than left dangling, and a rejection that
// isn't an Error (a thrown string, say) must not itself throw inside the catch.

test('a non-ok response is logged by status only, and its body is released', async () => {
  const logs = [];
  const log = { warn: (...args) => logs.push(args.join(' ')) };
  let cancelled = false;
  const fetchImpl = async () => ({ ok: false, status: 503, body: { cancel: () => { cancelled = true; } } });
  const ring = createDoorbell({ url: 'https://example.test/pull', token: 'secret-token', fetchImpl, log });
  ring();
  await new Promise(r => setTimeout(r, 10));
  assert.equal(logs.length, 1);
  assert.equal(logs[0], '[doorbell] 503');
  assert.ok(!logs[0].includes('secret-token'), 'the token must never be logged');
  assert.equal(cancelled, true, 'the response body must be released');
});

test('an ok response releases its body and logs nothing', async () => {
  const logs = [];
  const log = { warn: (...args) => logs.push(args.join(' ')) };
  let cancelled = false;
  const fetchImpl = async () => ({ ok: true, status: 200, body: { cancel: () => { cancelled = true; } } });
  const ring = createDoorbell({ url: 'https://example.test/pull', token: 'secret-token', fetchImpl, log });
  ring();
  await new Promise(r => setTimeout(r, 10));
  assert.equal(logs.length, 0);
  assert.equal(cancelled, true);
});

test('a cancel that rejects (an errored stream) never becomes an unhandled rejection (R8)', async () => {
  const logs = [];
  const log = { warn: (...args) => logs.push(args.join(' ')) };
  const fetchImpl = async () => ({ ok: true, body: { cancel: () => Promise.reject(new Error('reset')) } });
  const ring = createDoorbell({ url: 'https://example.test/pull', token: 'secret', fetchImpl, log });
  let unhandled = null;
  const onUnhandled = error => { unhandled = error; };
  process.on('unhandledRejection', onUnhandled);
  try {
    ring();
    await new Promise(r => setTimeout(r, 20));
  } finally {
    process.off('unhandledRejection', onUnhandled);
  }
  assert.equal(unhandled, null, 'a rejected cancel must never surface as an unhandled rejection');
});

test('a rejection that is not an Error does not itself throw inside the catch', async () => {
  const logs = [];
  const log = { warn: (...args) => logs.push(args.join(' ')) };
  const fetchImpl = async () => { throw 'boom'; };
  const ring = createDoorbell({ url: 'https://example.test/pull', token: 'secret', fetchImpl, log });
  assert.doesNotThrow(() => ring());
  await new Promise(r => setTimeout(r, 10));
  assert.deepEqual(logs, ['[doorbell] boom']);
});

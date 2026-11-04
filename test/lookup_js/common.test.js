'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, doc } = require('./helpers.js');

const C = load('common.js');

test('digits strips everything but digits', () => {
  assert.equal(C.digits('+98 (912) 000-0001'), '989120000001');
  assert.equal(C.digits(null), '');
});

test('clean drops null, undefined, empty string and empty objects but keeps false and 0', () => {
  const out = C.clean({ a: null, b: undefined, c: '', d: {}, e: false, f: 0, g: 'x', h: { k: 1 } });
  assert.deepEqual(out, { e: false, f: 0, g: 'x', h: { k: 1 } });
});

test('result: status always present, absent fields omitted, on_platform false survives', () => {
  const r = C.result('not_found', { on_platform: false, display_name: '' });
  assert.deepEqual(r, { status: 'not_found', on_platform: false });
  const e = C.fail('boom', 'detail');
  assert.equal(e.status, 'error');
  assert.equal(e.error, 'boom: detail');
});

test('poll returns the first truthy value and null on timeout', async () => {
  let n = 0;
  const v = await C.poll(() => (++n >= 3 ? 'ok' : null), { timeout: 2000, every: 5 });
  assert.equal(v, 'ok');
  const none = await C.poll(() => null, { timeout: 30, every: 5 });
  assert.equal(none, null);
});

test('poll survives a throwing probe', async () => {
  let n = 0;
  const v = await C.poll(() => {
    if (++n < 2) throw new Error('not yet');
    return 'fine';
  }, { timeout: 500, every: 5 });
  assert.equal(v, 'fine');
});

test('withTimeout: value, error, timeout', async () => {
  assert.deepEqual(await C.withTimeout(Promise.resolve(7), 100), { value: 7 });
  assert.deepEqual(await C.withTimeout(Promise.reject(new Error('x')), 100), { error: 'x' });
  assert.deepEqual(await C.withTimeout(new Promise(() => {}), 20), { timeout: true });
});

test('shrinkImage returns base64 without prefix when small enough', async () => {
  const d = doc({});
  const env = {
    document: d,
    fetch: async () => ({ ok: true, blob: async () => ({}) }),
    createImageBitmap: async () => ({ width: 2000, height: 1000 }),
  };
  const b64 = await C.shrinkImage('https://example.invalid/p.jpg', 300000, env);
  assert.equal(b64, 'QUJD');
});

test('shrinkImage gives up (null) when the image never fits, or on any error', async () => {
  const big = 'A'.repeat(1000);
  const d = doc({});
  d.createElement = () => ({ width: 0, height: 0, getContext: () => ({ drawImage() {} }), toDataURL: () => 'data:image/jpeg;base64,' + big });
  const env = { document: d, fetch: async () => ({ ok: true, blob: async () => ({}) }), createImageBitmap: async () => ({ width: 10, height: 10 }) };
  assert.equal(await C.shrinkImage('u', 100, env), null);
  const broken = { document: d, fetch: async () => { throw new Error('cors'); }, createImageBitmap: async () => ({}) };
  assert.equal(await C.shrinkImage('u', 100, broken), null);
});

test('firstText picks the first non-blank string', () => {
  assert.equal(C.firstText(null, '  ', ' hi ', 'x'), 'hi');
  assert.equal(C.firstText(null, 5), null);
});

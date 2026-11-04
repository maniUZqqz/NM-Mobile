'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('./helpers.js');

load('common.js');
const bale = load('bale.js');

const NUMBER = '989120000004'; // made-up

function fakeEnv(opts) {
  const o = opts || {};
  const users = { rows: o.existing ? o.existing.slice() : [{ k: '1', v: { id: 1, name: 'Someone Else' } }] };
  const full = { rows: o.full || [] };
  const navigated = [];
  const env = {
    localStorage: { getItem: (k) => (k === 'user' && !o.loggedOut ? '{"id":7}' : null) },
    navigate: (path) => {
      navigated.push(path);
      if (o.onNavigate) setTimeout(() => o.onNavigate(users, full), 5);
    },
    idb: {
      dbNames: async () => (o.noDb ? [] : ['bale-db']),
      read: async (db, store) => {
        const src = store === 'users' ? users : store === 'full_users' ? full : null;
        if (!src) return null;
        return { keys: src.rows.map((r) => r.k), values: src.rows.map((r) => r.v) };
      },
    },
    _navigated: navigated,
  };
  return env;
}

test('found: navigates the SPA to /+digits, picks the NEW user record, reads name, nick, about', async () => {
  const env = fakeEnv({
    onNavigate: (users, full) => {
      users.rows.push({ k: '88', v: { id: 88, name: 'علی رضایی', nick: 'ali_r', localName: 'Ali (me)' } });
      full.rows.push({ k: '88', v: { about: 'فروشنده' } });
    },
  });
  const r = await bale.run({ digits: NUMBER }, env);
  assert.deepEqual(env._navigated, ['/+' + NUMBER]);
  assert.equal(r.status, 'found');
  assert.equal(r.display_name, 'علی رضایی');
  assert.equal(r.username, 'ali_r');
  assert.equal(r.bio, 'فروشنده');
  assert.equal(r.deep_link_id, '88');
  assert.equal(r.extra.local_name, 'Ali (me)');
  assert.equal(r.extra.from_cache, false);
  assert.equal('avatar_b64' in r, false);
});

test('already cached contact: matched by a record that carries the number', async () => {
  const env = fakeEnv({
    existing: [{ k: '5', v: { id: 5, name: 'Sara', contact: { phone: '+' + NUMBER } } }],
  });
  const r = await bale.run({ digits: NUMBER }, env);
  assert.equal(r.status, 'found');
  assert.equal(r.display_name, 'Sara');
  assert.equal(r.extra.from_cache, true);
});

test('a record whose shape is not recognised is reported, with the key names for debugging', async () => {
  const env = fakeEnv({
    onNavigate: (users) => { users.rows.push({ k: '9', v: { zz: 1, yy: 2 } }); },
  });
  const r = await bale.run({ digits: NUMBER }, env);
  assert.equal(r.status, 'error');
  assert.equal(r.error, 'unknown_record_shape');
  assert.deepEqual(r.extra.keys, ['zz', 'yy']);
});

test('nothing new appears -> no_result_timeout (never a guess, never "not found")', async () => {
  const r = await bale.run({ digits: NUMBER, resolveTimeoutMs: 200 }, fakeEnv());
  assert.equal(r.status, 'error');
  assert.match(r.error, /^no_result_timeout/);
});

test('users store missing -> explicit error', async () => {
  const r = await bale.run({ digits: NUMBER, readyTimeoutMs: 200 }, fakeEnv({ noDb: true }));
  assert.match(r.error, /^no_users_store/);
});

test('not logged in -> login_required', async () => {
  const r = await bale.run({ digits: NUMBER }, fakeEnv({ loggedOut: true }));
  assert.equal(r.status, 'login_required');
});

test('bad number', async () => {
  assert.match((await bale.run({ digits: '9' }, fakeEnv())).error, /^bad_number/);
});

test('carriesNumber matches by the last 10 digits, also nested', () => {
  assert.equal(bale.carriesNumber({ a: { b: '+98 912 000 0004' } }, NUMBER), true);
  assert.equal(bale.carriesNumber({ a: '09120000009' }, NUMBER), false);
  assert.equal(bale.carriesNumber({ id: 4 }, NUMBER), false);
});

test('realIdb reads keys and values of a store via the IndexedDB API', async () => {
  const fakeDb = {
    objectStoreNames: { contains: (n) => n === 'users' },
    transaction: () => ({
      objectStore: () => ({
        getAllKeys: () => fire(['a', 'b']),
        getAll: () => fire([{ id: 1 }, { id: 2 }]),
      }),
    }),
    close() { this.closed = true; },
  };
  function fire(result) {
    const r = {};
    setTimeout(() => { r.result = result; r.onsuccess(); }, 1);
    return r;
  }
  const idb = bale.realIdb({
    databases: async () => [{ name: 'x' }, { name: null }],
    open: () => fire(fakeDb),
  });
  assert.deepEqual(await idb.dbNames(), ['x']);
  assert.deepEqual(await idb.read('x', 'users'), { keys: ['a', 'b'], values: [{ id: 1 }, { id: 2 }] });
  assert.equal(await idb.read('x', 'nope'), null);
  assert.equal(fakeDb.closed, true);
});

test('probe follows the "user" entry of local storage', () => {
  assert.equal(bale.probe(fakeEnv()).logged_in, true);
  assert.equal(bale.probe(fakeEnv({ loggedOut: true })).logged_in, false);
});

'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { el, doc, load } = require('./helpers.js');

load('common.js');
const wa = load('whatsapp.js');

const NUMBER = '989120000001'; // made-up

function registry(overrides) {
  const base = {
    WAWebWidFactory: {
      createUserWidOrThrow: (t) => ({ _serialized: t, user: t.split('@')[0] }),
    },
    WAWebQueryExistsJob: {
      queryPhoneExists: async (d) => ({ wid: { _serialized: d + '@c.us', user: d }, biz: false }),
    },
    WAWebCollections: {
      Contact: { get: () => ({ pushname: 'Ali', name: 'Ali Saved', isAddressBookContact: false }) },
      TextStatus: { find: async () => ({ status: 'hello there' }) },
    },
    WAWebContactProfilePicThumbBridge: {
      requestProfilePicFromServer: async () => ({ eurl: 'https://example.invalid/pic.jpg' }),
    },
  };
  return Object.assign(base, overrides || {});
}

function env(mods, opts) {
  const o = opts || {};
  const map = o.noChatList ? {} : { '#pane-side': el({}) };
  if (o.qr) map.canvas = el({});
  const self = { require: (name) => (mods[name] === undefined ? null : mods[name]) };
  return {
    self,
    document: doc(map, o.body || ''),
    settleMs: 0,
    shrinkImage: async () => 'QUJD',
  };
}

test('found: push name, about and picture are returned with a source per field', async () => {
  const r = await wa.run({ digits: NUMBER }, env(registry()));
  assert.equal(r.status, 'found');
  assert.equal(r.on_platform, true);
  assert.equal(r.display_name, 'Ali');
  assert.equal(r.bio, 'hello there');
  assert.equal(r.avatar_b64, 'QUJD');
  assert.equal(r.deep_link_id, NUMBER);
  assert.ok(r.field_sources.display_name.includes('push name'));
  assert.ok(r.field_sources.bio);
  assert.ok(r.field_sources.avatar);
  assert.equal(r.extra.saved_name, 'Ali Saved');
  assert.equal(r.extra.is_business, false);
});

test('not on WhatsApp -> not_found with on_platform=false and no profile fields', async () => {
  const mods = registry({ WAWebQueryExistsJob: { queryPhoneExists: async () => null } });
  const r = await wa.run({ digits: NUMBER }, env(mods));
  assert.equal(r.status, 'not_found');
  assert.equal(r.on_platform, false);
  assert.equal(r.display_name, undefined);
});

test('about / picture hidden by the person: fields are absent, not empty, still found', async () => {
  const mods = registry({
    WAWebCollections: { Contact: { get: () => ({ pushname: 'Sara' }) }, TextStatus: { find: async () => null, get: async () => null } },
    WAWebContactProfilePicThumbBridge: { requestProfilePicFromServer: async () => null },
  });
  const r = await wa.run({ digits: NUMBER }, env(mods));
  assert.equal(r.status, 'found');
  assert.equal(r.display_name, 'Sara');
  assert.equal('bio' in r, false);
  assert.equal('avatar_b64' in r, false);
  assert.deepEqual(Object.keys(r.field_sources), ['display_name']);
});

test('falls back to queryWidExists when queryPhoneExists throws', async () => {
  const mods = registry({
    WAWebQueryExistsJob: {
      queryPhoneExists: async () => { throw new Error('signature changed'); },
      queryWidExists: async (wid) => ({ wid }),
    },
  });
  const r = await wa.run({ digits: NUMBER }, env(mods));
  assert.equal(r.status, 'found');
  assert.equal(r.extra.via, 'queryWidExists');
});

test('error code no_query_module when the query module is missing', async () => {
  const mods = registry();
  delete mods.WAWebQueryExistsJob;
  const r = await wa.run({ digits: NUMBER }, env(mods));
  assert.equal(r.status, 'error');
  assert.match(r.error, /^no_query_module/);
});

test('error code no_usable_method when the module has none of the known functions', async () => {
  const r = await wa.run({ digits: NUMBER }, env(registry({ WAWebQueryExistsJob: {} })));
  assert.match(r.error, /^no_usable_method/);
});

test('QR screen -> login_required (the owner has to scan, we never do)', async () => {
  const r = await wa.run({ digits: NUMBER }, env(registry(), { noChatList: true, qr: true }));
  assert.equal(r.status, 'login_required');
});

test('browser rejected page is reported explicitly', async () => {
  const r = await wa.run({ digits: NUMBER }, env(registry(), { noChatList: true, body: 'WhatsApp works with Google Chrome 85+' }));
  assert.match(r.error, /^browser_rejected/);
});

test('signed in but module system never appears -> app_not_ready', async () => {
  const e = env({});
  const r = await wa.run({ digits: NUMBER, readyTimeoutMs: 200 }, e);
  assert.equal(r.status, 'error');
  assert.match(r.error, /^app_not_ready/);
});

test('bad numbers are refused before anything runs', async () => {
  assert.match((await wa.run({ digits: '12' }, env(registry()))).error, /^bad_number/);
  assert.match((await wa.run({}, env(registry()))).error, /^bad_number/);
});

test('avatar:false skips the picture entirely', async () => {
  let asked = false;
  const mods = registry({
    WAWebContactProfilePicThumbBridge: { requestProfilePicFromServer: async () => { asked = true; return { eurl: 'x' }; } },
  });
  const r = await wa.run({ digits: NUMBER, avatar: false }, env(mods));
  assert.equal(asked, false);
  assert.equal('avatar_b64' in r, false);
});

test('probe states', () => {
  assert.equal(wa.probe(env(registry())).stage, 'signed_in');
  assert.equal(wa.probe(env(registry(), { noChatList: true, qr: true })).stage, 'qr');
  assert.equal(wa.probe(env(registry(), { noChatList: true })).stage, 'loading');
});

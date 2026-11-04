'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { el, doc, load } = require('./helpers.js');

load('common.js');
const eitaa = load('eitaa.js');

const NUMBER = '989120000002'; // made-up

/**
 * Fake Web-K page. `behaviour(hashValue, dom)` runs when the adapter sets location.hash,
 * like the real client would react to `#?tgaddr=...`.
 */
function page(behaviour, opts) {
  const o = opts || {};
  const map = {};
  if (!o.loggedOut) map['#column-left .chatlist-container'] = el({});
  else map['#auth-pages'] = el({});
  const d = doc(map);
  const loc = {
    _hash: '',
    set hash(v) {
      this._hash = v;
      setTimeout(() => behaviour && behaviour(v, d), 5);
    },
    get hash() {
      return this._hash;
    },
  };
  return { document: d, location: loc, shrinkImage: async () => 'QUJD' };
}

function openChat(d, withProfile) {
  d.map['#column-center .chat-info .user-title .peer-title'] = el({ innerText: 'علی رضایی', attrs: { 'data-peer-id': '4242' } });
  const profile = el({
    children: {
      '.profile-name .peer-title': el({ innerText: 'علی رضایی' }),
      '.username-eng': el({ innerText: 'ali_r' }),
      '.row-title.pre-wrap': el({ innerText: 'مدیر فروش' }),
      '.avatar-photo': el({ src: 'blob:fake' }),
    },
  });
  if (withProfile === 'click') {
    d.map['#column-center .chat-info .person'] = el({
      onClick: () => { d.map['#column-right .profile-content'] = profile; },
    });
  } else if (withProfile) {
    d.map['#column-right .profile-content'] = profile;
  }
}

test('found: hash deep link is the tg://resolve?phone link, profile is read after opening the sidebar', async () => {
  let seen = '';
  const p = page((hash, d) => { seen = hash; openChat(d, 'click'); });
  const r = await eitaa.run({ digits: NUMBER }, p);
  assert.equal(seen, '#?tgaddr=' + encodeURIComponent('tg://resolve?phone=' + NUMBER));
  assert.equal(r.status, 'found');
  assert.equal(r.on_platform, true);
  assert.equal(r.display_name, 'علی رضایی');
  assert.equal(r.username, 'ali_r');
  assert.equal(r.bio, 'مدیر فروش');
  assert.equal(r.avatar_b64, 'QUJD');
  assert.equal(r.deep_link_id, '4242');
  assert.ok(r.field_sources.username);
});

test('found with the sidebar already open', async () => {
  const p = page((h, d) => openChat(d, true));
  const r = await eitaa.run({ digits: NUMBER }, p);
  assert.equal(r.status, 'found');
  assert.equal(r.username, 'ali_r');
});

test('sidebar never opens: still found, with the chat title only and a note', async () => {
  const p = page((h, d) => openChat(d, false));
  const r = await eitaa.run({ digits: NUMBER, resolveTimeoutMs: 400, profileTimeoutMs: 200 }, p);
  assert.equal(r.status, 'found');
  assert.equal(r.display_name, 'علی رضایی');
  assert.equal(r.extra.note, 'profile_sidebar_not_opened');
  assert.equal('username' in r, false);
});

test('no findable account: toast with text -> not_found', async () => {
  const p = page((h, d) => { d.map['.toast'] = el({ innerText: 'No user with this phone' }); });
  const r = await eitaa.run({ digits: NUMBER, resolveTimeoutMs: 300 }, p);
  assert.equal(r.status, 'not_found');
  assert.equal(r.on_platform, false);
});

test('an EMPTY toast container is not treated as "not found"', async () => {
  const p = page((h, d) => { d.map['.toast'] = el({ innerText: '' }); });
  const r = await eitaa.run({ digits: NUMBER, resolveTimeoutMs: 300 }, p);
  assert.equal(r.status, 'error');
  assert.match(r.error, /^no_result_timeout/);
});

test('nothing happens at all -> no_result_timeout error, never a guess', async () => {
  const p = page(null);
  const r = await eitaa.run({ digits: NUMBER, resolveTimeoutMs: 200 }, p);
  assert.equal(r.status, 'error');
});

test('not logged in -> login_required', async () => {
  const p = page(null, { loggedOut: true });
  const r = await eitaa.run({ digits: NUMBER, readyTimeoutMs: 200 }, p);
  assert.equal(r.status, 'login_required');
});

test('a chat that is already open aborts (page must be fresh)', async () => {
  const p = page(null);
  openChat(p.document, false);
  const r = await eitaa.run({ digits: NUMBER }, p);
  assert.match(r.error, /^chat_already_open/);
});

test('bad number', async () => {
  assert.match((await eitaa.run({ digits: '1' }, page(null))).error, /^bad_number/);
});

test('probe', () => {
  assert.equal(eitaa.probe(page(null)).logged_in, true);
  assert.equal(eitaa.probe(page(null, { loggedOut: true })).logged_in, false);
});

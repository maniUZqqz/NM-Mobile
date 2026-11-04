'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { el, doc, load } = require('./helpers.js');

load('common.js');
const splus = load('soroush.js');

const NUMBER = '989120000003'; // made-up

// The real module (id 13439) of https://web.splus.ir main bundle that exports getGlobal/getActions,
// copied as text so exportKeyFor is tested against what the real client contains.
const REAL_MODULE_SRC =
  '(function(e,t,n){"use strict";const s=(0,n(37932).cl)(),r=s.getGlobal,o=s.setGlobal,a=s.getActions,i=s.addActionHandler,c=s.withGlobal;n.d(t,["EK",0,c,"UF",0,o,"aJ",0,i,"ko",0,a,"mS",0,r])})';

test('exportKeyFor reads the real module text (array form)', () => {
  assert.equal(splus.exportKeyFor(REAL_MODULE_SRC, 'getActions'), 'ko');
  assert.equal(splus.exportKeyFor(REAL_MODULE_SRC, 'getGlobal'), 'mS');
  assert.equal(splus.exportKeyFor(REAL_MODULE_SRC, 'nothing'), null);
});

test('exportKeyFor also reads the object-getter form', () => {
  const src = 'function(e,t,n){const s=n(1).cl(),r=s.getGlobal,a=s.getActions;n.d(t,{GG:()=>r,AA:()=>a})}';
  assert.equal(splus.exportKeyFor(src, 'getActions'), 'AA');
  assert.equal(splus.exportKeyFor(src, 'getGlobal'), 'GG');
});

/** Builds a fake Web-A page with a webpack runtime and app state. */
function page(opts) {
  const o = opts || {};
  const state = {
    users: { byId: {}, fullInfoById: {} },
    byTabId: { t1: { messageLists: [], notifications: [] } },
  };
  const actions = {
    calls: [],
    openChatByPhoneNumber({ phoneNumber }) {
      actions.calls.push(phoneNumber);
      if (o.behaviour) setTimeout(() => o.behaviour(state, phoneNumber), 5);
    },
    loadFullUser: ({ userId }) => {
      if (o.fullBio) setTimeout(() => { state.users.fullInfoById[userId] = { bio: o.fullBio }; }, 5);
    },
  };
  const exportsObj = { ko: () => actions, mS: () => state, EK: () => null, UF: () => null, aJ: () => null };
  const mods = {};
  mods[13439] = eval(REAL_MODULE_SRC);
  mods[1] = function () { return 'unrelated'; };
  const req = (id) => (Number(id) === 13439 ? exportsObj : {});
  req.m = o.noModule ? { 1: mods[1] } : mods;
  const chunk = [];
  chunk.push = function (c) { c[2](req); return 1; };
  const self = o.noRuntime ? {} : { webpackChunkFake: chunk };
  const map = {};
  if (o.auth) map['#auth-qr-form'] = el({});
  else map['#LeftColumn .chat-list'] = el({});
  if (o.avatar) map['#MiddleColumn .MiddleHeader .Avatar img'] = el({ src: 'blob:fake' });
  return { self, document: doc(map), shrinkImage: async () => 'QUJD', _state: state, _actions: actions };
}

test('found: opens the chat by phone through the client action, reads name, username, bio, avatar', async () => {
  const p = page({
    avatar: true,
    fullBio: 'Sales manager',
    behaviour: (st) => {
      st.users.byId['555'] = { firstName: 'Ali', lastName: 'Rezaei', usernames: [{ username: 'ali_r', isActive: true }], isPremium: true };
      st.byTabId.t1.messageLists.push({ chatId: '0' });
      st.byTabId.t1.messageLists.push({ chatId: '555' });
    },
  });
  const r = await splus.run({ digits: NUMBER }, p);
  assert.deepEqual(p._actions.calls, [NUMBER]);
  assert.equal(r.status, 'found');
  assert.equal(r.display_name, 'Ali Rezaei');
  assert.equal(r.username, 'ali_r');
  assert.equal(r.bio, 'Sales manager');
  assert.equal(r.avatar_b64, 'QUJD');
  assert.equal(r.deep_link_id, '555');
  assert.equal(r.extra.is_premium, true);
  assert.ok(r.field_sources.bio);
});

test('not found: the client shows its "not found for {phone}" notification', async () => {
  const p = page({
    behaviour: (st, phone) => { st.byTabId.t1.notifications.push({ message: 'No Soroush user for ' + phone }); },
  });
  const r = await splus.run({ digits: NUMBER }, p);
  assert.equal(r.status, 'not_found');
  assert.equal(r.on_platform, false);
});

test('a placeholder chat "0" alone is not a result', async () => {
  const p = page({ behaviour: (st) => { st.byTabId.t1.messageLists.push({ chatId: '0' }); } });
  const r = await splus.run({ digits: NUMBER, resolveTimeoutMs: 200 }, p);
  assert.equal(r.status, 'error');
  assert.match(r.error, /^no_result_timeout/);
});

test('bio missing (privacy): found without bio', async () => {
  const p = page({
    behaviour: (st) => {
      st.users.byId['9'] = { firstName: 'Sara' };
      st.byTabId.t1.messageLists.push({ chatId: '9' });
    },
  });
  const r = await splus.run({ digits: NUMBER, fullTimeoutMs: 100 }, p);
  assert.equal(r.status, 'found');
  assert.equal('bio' in r, false);
  assert.equal('username' in r, false);
});

test('webpack runtime missing -> explicit error', async () => {
  const r = await splus.run({ digits: NUMBER }, page({ noRuntime: true }));
  assert.match(r.error, /^no_webpack_runtime/);
});

test('actions module not found -> explicit error (no guessing)', async () => {
  const r = await splus.run({ digits: NUMBER }, page({ noModule: true }));
  assert.match(r.error, /^no_actions_module/);
});

test('auth screen -> login_required', async () => {
  const r = await splus.run({ digits: NUMBER, readyTimeoutMs: 200 }, page({ auth: true }));
  assert.equal(r.status, 'login_required');
});

test('bad number', async () => {
  assert.match((await splus.run({ digits: 'abc' }, page())).error, /^bad_number/);
});

test('probe', () => {
  assert.equal(splus.probe(page()).logged_in, true);
  assert.equal(splus.probe(page({ auth: true })).stage, 'auth');
});

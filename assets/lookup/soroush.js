/* Soroush Plus Web adapter (web.splus.ir, a Telegram-Web-A (teact) based client; the OWNER is logged in).
 *
 * Method, grounded in the client's own code (read from the https://web.splus.ir bundles):
 *  - the client has a global action `openChatByPhoneNumber({phoneNumber})`: it calls its
 *    own "getChatByPhoneNumber" (MTProto contacts.resolvePhone), opens that chat, or shows a
 *    notification (lng_username_by_phone_not_found) when there is no findable account;
 *  - the app state (global.users.byId / fullInfoById) is read with the client's own
 *    getGlobal/getActions, which are reached through the webpack runtime
 *    (`window.webpackChunk*`), because Web A does not publish them on window in production.
 * Nothing is added to the address book, nothing is sent. Honours the person's privacy
 * settings: a hidden account looks like "not found".
 *
 * FRAGILE by nature: it depends on the internal module layout of one build. When that layout
 * changes the adapter answers {status:"error", error:"no_actions_module"} instead of guessing.
 * Status: not verified against a real logged-in session (docs/lookup.md).
 */
(function (root) {
  'use strict';

  const C = root.NMLookupCommon || require('./common.js');

  function envOf(env) {
    return env || { self: root, document: root.document, fetch: root.fetch && root.fetch.bind(root) };
  }

  const SEL = {
    signedIn: ['#LeftColumn .chat-list', '#LeftColumn .ChatFolders', '#MiddleColumn .MiddleHeader', '#MiddleColumn'],
    auth: ['#auth-qr-form', '#auth-phone-number-form', '#auth-code-form', '#auth-password-form', '.Auth'],
    avatarImg: ['#MiddleColumn .MiddleHeader .Avatar img', '#MiddleColumn .ChatInfo .Avatar img', '.MiddleHeader img'],
  };

  function first(env, list) {
    for (const s of list) {
      const el = env.document.querySelector(s);
      if (el) return el;
    }
    return null;
  }

  function probe(env) {
    env = envOf(env);
    if (first(env, SEL.auth)) return { logged_in: false, stage: 'auth' };
    if (first(env, SEL.signedIn)) return { logged_in: true, stage: 'signed_in' };
    return { logged_in: false, stage: 'loading' };
  }

  /** Gets webpack's require through the standard chunk-push runtime hook. */
  function getWebpackRequire(env) {
    const w = env.self;
    const key = Object.keys(w).find((k) => /^webpackChunk/.test(k) && Array.isArray(w[k]));
    if (!key) return null;
    let req = null;
    try {
      w[key].push([[Symbol('nm-lookup')], {}, (r) => { req = r; }]);
    } catch (e) {
      return null;
    }
    return req;
  }

  /** In the module source, which exported key points at `member` (e.g. getActions)? */
  function exportKeyFor(src, member) {
    const m = new RegExp('(\\w+)=\\w+\\.' + member + '(?![\\w$])').exec(src);
    if (!m) return null;
    const v = m[1];
    let k = new RegExp('"(\\w+)",0,' + v + '(?![\\w$])').exec(src);
    if (k) return k[1];
    k = new RegExp('(\\w+):\\(\\)=>' + v + '(?![\\w$])').exec(src);
    return k ? k[1] : null;
  }

  /** {getGlobal, getActions} of the client, or {error}. */
  function findState(env) {
    const req = getWebpackRequire(env);
    if (!req || !req.m) return { error: 'no_webpack_runtime' };
    for (const id of Object.keys(req.m)) {
      let src = '';
      try {
        src = Function.prototype.toString.call(req.m[id]);
      } catch (e) {
        continue;
      }
      if (src.length > 3000) continue;
      if (!/\.getActions(?![\w$])/.test(src) || !/\.getGlobal(?![\w$])/.test(src) || !/\.addActionHandler(?![\w$])/.test(src)) continue;
      const kA = exportKeyFor(src, 'getActions');
      const kG = exportKeyFor(src, 'getGlobal');
      if (!kA || !kG) continue;
      let exp = null;
      try {
        exp = req(id);
      } catch (e) {
        continue;
      }
      if (exp && typeof exp[kA] === 'function' && typeof exp[kG] === 'function') {
        return { getActions: exp[kA], getGlobal: exp[kG] };
      }
    }
    return { error: 'no_actions_module' };
  }

  function tabIds(g) {
    return Object.keys((g && g.byTabId) || {});
  }

  /** Chat id currently open in any tab ("0" is the placeholder the action opens first). */
  function openedChatId(g) {
    for (const t of tabIds(g)) {
      const lists = (g.byTabId[t] && g.byTabId[t].messageLists) || [];
      const last = lists[lists.length - 1];
      if (last && last.chatId && last.chatId !== '0') return String(last.chatId);
    }
    return null;
  }

  function notificationMentions(g, digits) {
    for (const t of tabIds(g)) {
      const list = (g.byTabId[t] && g.byTabId[t].notifications) || [];
      for (const n of list) {
        let text = '';
        try {
          text = JSON.stringify(n);
        } catch (e) {
          text = '';
        }
        if (text.includes(digits)) return true;
      }
    }
    return false;
  }

  async function run(args, env) {
    env = envOf(env);
    const digits = C.digits(args && args.digits);
    if (digits.length < 8 || digits.length > 15) return C.fail('bad_number');
    const timeout = (args && args.resolveTimeoutMs) || 15000;

    const logged = await C.poll(() => probe(env).logged_in, { timeout: (args && args.readyTimeoutMs) || 20000, every: 250 });
    if (!logged) {
      return probe(env).stage === 'auth'
        ? C.result('login_required', { error: 'splus_stage_auth' })
        : C.fail('app_not_ready');
    }

    const state = findState(env);
    if (state.error) return C.fail(state.error);
    const actions = state.getActions();
    if (!actions || typeof actions.openChatByPhoneNumber !== 'function') return C.fail('no_open_by_phone_action');

    const before = new Set(Object.keys((state.getGlobal().users || {}).byId || {}));
    actions.openChatByPhoneNumber({ phoneNumber: digits });

    const outcome = await C.poll(
      () => {
        const g = state.getGlobal();
        const chatId = openedChatId(g);
        if (chatId && g.users && g.users.byId && g.users.byId[chatId]) return { kind: 'found', id: chatId };
        if (notificationMentions(g, digits)) return { kind: 'not_found' };
        return null;
      },
      { timeout, every: 250 }
    );
    if (!outcome) return C.fail('no_result_timeout');
    if (outcome.kind === 'not_found') return C.result('not_found', { on_platform: false, extra: { note: 'no_findable_account' } });

    const id = outcome.id;
    if (typeof actions.loadFullUser === 'function') {
      try {
        actions.loadFullUser({ userId: id });
      } catch (e) {
        /* optional */
      }
    }
    const full = await C.poll(() => {
      const g = state.getGlobal();
      return (g.users.fullInfoById || {})[id] || null;
    }, { timeout: (args && args.fullTimeoutMs) || 6000, every: 250 });

    const g = state.getGlobal();
    const u = g.users.byId[id];
    const out = { on_platform: true, deep_link_id: id, extra: { is_new_to_cache: !before.has(id) } };
    const sources = {};
    const name = [u.firstName, u.lastName].filter(Boolean).join(' ').trim();
    if (name) {
      out.display_name = name;
      sources.display_name = 'سروش پلاس: نام پروفایل';
    }
    const uname = (u.usernames || []).find((x) => x && x.isActive) || (u.usernames || [])[0];
    if (uname && uname.username) {
      out.username = uname.username;
      sources.username = 'سروش پلاس: نام کاربری';
    }
    if (full && full.bio) {
      out.bio = String(full.bio).trim();
      sources.bio = 'سروش پلاس: بیوگرافی';
    }
    if (u.isPremium) out.extra.is_premium = true;
    const img = args && args.avatar === false ? null : first(env, SEL.avatarImg);
    const src = img && (img.currentSrc || img.src);
    if (src) {
      const shrink = env.shrinkImage || ((s) => C.shrinkImage(s, 300000, env));
      const b64 = await shrink(src);
      if (b64) {
        out.avatar_b64 = b64;
        sources.avatar = 'سروش پلاس: عکس پروفایل';
      }
    }
    out.field_sources = sources;
    return C.result('found', out);
  }

  root.__NM_LOOKUP = run;
  root.__NM_PROBE = probe;
  if (typeof module !== 'undefined' && module.exports) module.exports = { run, probe, exportKeyFor, findState };
})(typeof self !== 'undefined' ? self : globalThis);

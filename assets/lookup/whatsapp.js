/* WhatsApp Web adapter (runs inside web.whatsapp.com, in a WebView the OWNER logged into).
 *
 * Method: WhatsApp Web exposes its own internal module registry (`self.require`). We use the
 * same internal functions the web client itself uses to (1) ask WhatsApp whether a phone
 * number has an account, (2) read the push name / saved name, the "about" text and the
 * profile picture the platform returns to a normal user. Nothing is written, no message is
 * sent, no story is read. Module names/signatures change between WhatsApp builds, so every
 * step has fallbacks and explicit error codes.
 *
 * Unofficial access: the Persian ban-risk warning is shown by the app. Status:
 * not verified against a real logged-in session (documented in docs/lookup.md).
 */
(function (root) {
  'use strict';

  const C = root.NMLookupCommon || require('./common.js');

  function envOf(env) {
    return env || { self: root, document: root.document, fetch: root.fetch && root.fetch.bind(root) };
  }

  function mod(env, name) {
    try {
      const req = env.self && env.self.require;
      return typeof req === 'function' ? req(name) || null : null;
    } catch (e) {
      return null;
    }
  }

  function chatListVisible(env) {
    const d = env.document;
    const el =
      d.querySelector('#pane-side') ||
      d.querySelector('[data-testid="chat-list"]') ||
      d.querySelector('[aria-label="Chat list"]');
    return C.isVisible(el);
  }

  /** Login-state probe: {logged_in, stage}. stage: signed_in | qr | phone | code | browser_rejected | loading */
  function probe(env) {
    env = envOf(env);
    const d = env.document;
    const body = (d.body && (d.body.innerText || d.body.textContent)) || '';
    if (chatListVisible(env)) return { logged_in: true, stage: 'signed_in' };
    if (/works\s+with\s+google\s+chrome|update\s+google\s+chrome/i.test(body)) {
      return { logged_in: false, stage: 'browser_rejected' };
    }
    if (d.querySelector('[data-link-code]')) return { logged_in: false, stage: 'code' };
    const qr = d.querySelector('canvas') || d.querySelector('[data-ref]');
    if (C.isVisible(qr) || /scan\s+(to\s+log\s+in|the\s+qr)/i.test(body)) {
      return { logged_in: false, stage: 'qr' };
    }
    if (C.isVisible(d.querySelector('input[aria-label*="phone" i]'))) {
      return { logged_in: false, stage: 'phone' };
    }
    return { logged_in: false, stage: 'loading' };
  }

  function makeWid(env, text) {
    const W = mod(env, 'WAWebWidFactory');
    if (!W) return null;
    try {
      return W.createUserWidOrThrow ? W.createUserWidOrThrow(text) : W.createWid(text);
    } catch (e) {
      return null;
    }
  }

  /** Does this number have a WhatsApp account? Tries the known query functions in turn. */
  async function checkExists(env, digits) {
    const Q = mod(env, 'WAWebQueryExistsJob');
    if (!Q) return { error: 'no_query_module' };
    const attempts = [];
    if (typeof Q.queryPhoneExists === 'function') {
      attempts.push(['queryPhoneExists', () => Q.queryPhoneExists(digits)]);
    }
    if (typeof Q.queryWidExists === 'function') {
      const wid = makeWid(env, digits + '@c.us');
      if (wid) attempts.push(['queryWidExists', () => Q.queryWidExists(wid)]);
    }
    if (typeof Q.queryExist === 'function') {
      attempts.push(['queryExist', () => Q.queryExist(digits)]);
    }
    if (!attempts.length) return { error: 'no_usable_method' };
    let last = 'no_usable_method';
    for (const [via, fn] of attempts) {
      const r = await C.withTimeout(fn(), 15000);
      if (r.value !== undefined) return { via, data: r.value };
      last = r.timeout ? 'timeout' : r.error || last;
    }
    return { error: last };
  }

  function pickWid(res) {
    if (!res) return null;
    if (res.wid) return res.wid;
    if (res.jid) return res.jid;
    if (res._serialized || res.user) return res;
    return null;
  }

  async function readContact(env, digits) {
    const Col = mod(env, 'WAWebCollections');
    const wid = makeWid(env, digits + '@c.us');
    if (!Col || !Col.Contact || !wid) return null;
    let c = null;
    try {
      c = (Col.Contact.get && Col.Contact.get(wid)) || null;
      if (!c && Col.Contact.find) {
        const r = await C.withTimeout(Col.Contact.find(wid), 8000);
        c = r.value || null;
      }
    } catch (e) {
      c = null;
    }
    return c;
  }

  /** The "about" line. Empty when the person hides it from us: that is not an error. */
  async function readAbout(env, wid) {
    const Col = mod(env, 'WAWebCollections');
    if (!Col || !Col.TextStatus) return null;
    let model = null;
    for (const how of ['find', 'get']) {
      if (typeof Col.TextStatus[how] !== 'function') continue;
      const r = await C.withTimeout(Col.TextStatus[how](wid), 10000);
      if (r.value) {
        model = r.value;
        break;
      }
    }
    let raw = model ? model.status || model.text || null : null;
    if (!(typeof raw === 'string' && raw.trim())) {
      const T = mod(env, 'WAWebApiTextStatus');
      if (T && typeof T.updateExpiredTextStatusOfContact === 'function') {
        try {
          T.updateExpiredTextStatusOfContact(wid);
        } catch (e) {
          /* best effort */
        }
        await C.sleep(env.settleMs === undefined ? 1500 : env.settleMs);
        const again = Col.TextStatus.find || Col.TextStatus.get;
        if (again) {
          const r = await C.withTimeout(again.call(Col.TextStatus, wid), 6000);
          if (r.value) raw = r.value.status || raw;
        }
      }
    }
    return typeof raw === 'string' && raw.trim() ? raw.trim() : null;
  }

  async function readPicture(env, wid) {
    const B = mod(env, 'WAWebContactProfilePicThumbBridge');
    let rec = null;
    if (B && typeof B.requestProfilePicFromServer === 'function') {
      const r = await C.withTimeout(B.requestProfilePicFromServer(wid), 12000);
      rec = r.value || null;
    }
    if (!rec) {
      const P = mod(env, 'WAWebProfilePicThumbCollection');
      try {
        rec = (P && P.ProfilePicThumbCollection && P.ProfilePicThumbCollection.get(wid)) || null;
      } catch (e) {
        rec = null;
      }
    }
    const url = rec && (rec.eurl || rec.imgFull || rec.img);
    if (!url) return null;
    const shrink = env.shrinkImage || ((u) => C.shrinkImage(u, 300000, env));
    return await shrink(url);
  }

  async function run(args, env) {
    env = envOf(env);
    const digits = C.digits(args && args.digits);
    if (digits.length < 8 || digits.length > 15) return C.fail('bad_number');

    const st = probe(env);
    if (st.stage === 'browser_rejected') return C.fail('browser_rejected');
    if (['qr', 'phone', 'code'].includes(st.stage)) return C.result('login_required', { error: 'wa_stage_' + st.stage });

    const ready = await C.poll(() => mod(env, 'WAWebWidFactory') && chatListVisible(env), {
      timeout: (args && args.readyTimeoutMs) || 20000,
      every: 150,
    });
    if (!ready) {
      const again = probe(env);
      if (!again.logged_in && again.stage !== 'loading') return C.result('login_required', { error: 'wa_stage_' + again.stage });
      return C.fail('app_not_ready');
    }

    const ex = await checkExists(env, digits);
    if (ex.error) return C.fail(ex.error);
    const found = pickWid(ex.data);
    if (!found) return C.result('not_found', { on_platform: false, extra: { via: ex.via } });

    const contact = await readContact(env, digits);
    const pnWid = makeWid(env, digits + '@c.us') || found;
    const sources = {};
    const out = { on_platform: true, deep_link_id: digits, extra: { via: ex.via } };

    out.extra.is_business = !!(ex.data && (ex.data.biz || ex.data.isBusiness));
    if (contact) {
      out.extra.is_my_contact = !!contact.isAddressBookContact;
      const push = C.firstText(contact.pushname, contact.notifyName);
      const saved = C.firstText(contact.name, contact.verifiedName);
      out.display_name = push || saved;
      if (push) sources.display_name = 'واتساپ: نامی که خودش گذاشته (push name)';
      else if (saved) sources.display_name = 'واتساپ: نام ثبت‌شده/تأییدشده';
      if (saved && push && saved !== push) out.extra.saved_name = saved;
    }

    const [about, avatar] = await Promise.all([
      readAbout(env, pnWid).catch(() => null),
      args && args.avatar === false ? null : readPicture(env, found).catch(() => null),
    ]);
    if (about) {
      out.bio = about;
      sources.bio = 'واتساپ: متن «درباره» (about)';
    }
    if (avatar) {
      out.avatar_b64 = avatar;
      sources.avatar = 'واتساپ: عکس پروفایل';
    }
    out.field_sources = sources;
    return C.result('found', out);
  }

  root.__NM_LOOKUP = run;
  root.__NM_PROBE = probe;
  if (typeof module !== 'undefined' && module.exports) module.exports = { run, probe, checkExists };
})(typeof self !== 'undefined' ? self : globalThis);

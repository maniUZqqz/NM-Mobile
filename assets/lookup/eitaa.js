/* Eitaa Web adapter (web.eitaa.com, a Telegram-Web-K based client; the OWNER is logged in).
 *
 * Method, grounded in the client's own code (read from https://web.eitaa.com bundles):
 *  - the client handles a hash `#?tgaddr=<encoded tg:// link>` (onHashChange -> openUrl);
 *  - a `tg://resolve?phone=<digits>` link is the "USER_PHONE_NUMBER" internal link: the client
 *    calls its own `resolvePhone` (MTProto contacts.resolvePhone) and opens that chat; when the
 *    number has no (findable) account it shows a toast and opens nothing.
 *  - the profile sidebar renders name / @username / bio rows (.profile-name, .username-eng,
 *    .row-title.pre-wrap) which we read as text.
 * This is a normal "open the chat for this phone number" flow of the official web client, no
 * contact is added and nothing is sent. The page must be freshly loaded (no chat open).
 * Honours the person's own privacy settings: a hidden account looks like "not found".
 *
 * Status: not verified against a real logged-in session (docs/lookup.md).
 */
(function (root) {
  'use strict';

  const C = root.NMLookupCommon || require('./common.js');

  function envOf(env) {
    return env || { document: root.document, location: root.location, fetch: root.fetch && root.fetch.bind(root) };
  }

  const SEL = {
    signedIn: ['#column-left .chatlist-container', '#column-left .chatlist', '#column-center .chat-input', '#folders-container'],
    authPages: ['#auth-pages', '.page-sign', '.tabs-container.auth-pages'],
    peerTitle: ['#column-center .chat-info .user-title .peer-title', '#column-center .chat-info .peer-title', '.chat-info .peer-title'],
    chatInfo: ['#column-center .chat-info .person', '#column-center .chat-info', '.chat-info-container'],
    profile: ['#column-right .profile-content', '.sidebar-right .profile-content', '.profile-content'],
    toast: ['.toast', '.toast-container .toast', '[class*="toast"]'],
  };

  function q(env, list, root_) {
    const scope = root_ || env.document;
    for (const s of list) {
      const el = scope.querySelector(s);
      if (el) return el;
    }
    return null;
  }

  function probe(env) {
    env = envOf(env);
    if (q(env, SEL.signedIn)) return { logged_in: true, stage: 'signed_in' };
    const auth = q(env, SEL.authPages);
    if (auth) {
      const hasQr = !!(env.document.querySelector('.auth-image canvas, #auth-pages canvas, canvas.qr-canvas') || env.document.querySelector('.input-wrapper input[name="phone"], input[name="phone"]'));
      return { logged_in: false, stage: hasQr ? 'qr_or_phone' : 'auth' };
    }
    return { logged_in: false, stage: 'loading' };
  }

  async function readAvatar(env, scope) {
    const img = scope && scope.querySelector && (scope.querySelector('.avatar-photo, img.avatar-photo, .avatar img, img'));
    const src = img && (img.currentSrc || img.src);
    if (!src) return null;
    const shrink = env.shrinkImage || ((u) => C.shrinkImage(u, 300000, env));
    return await shrink(src);
  }

  async function run(args, env) {
    env = envOf(env);
    const digits = C.digits(args && args.digits);
    if (digits.length < 8 || digits.length > 15) return C.fail('bad_number');
    const timeout = (args && args.resolveTimeoutMs) || 14000;

    const loggedIn = await C.poll(() => probe(env).logged_in, { timeout: (args && args.readyTimeoutMs) || 20000, every: 250 });
    if (!loggedIn) {
      const st = probe(env);
      if (st.stage === 'auth' || st.stage === 'qr_or_phone') return C.result('login_required', { error: 'eitaa_stage_' + st.stage });
      return C.fail('app_not_ready');
    }
    // A chat that is already open would make "a chat opened" meaningless.
    if (q(env, SEL.peerTitle) && C.text(q(env, SEL.peerTitle))) {
      return C.fail('chat_already_open', 'reload the page before a lookup');
    }

    // Ask the web client itself to open the chat of this phone number.
    env.location.hash = '#?tgaddr=' + encodeURIComponent('tg://resolve?phone=' + digits);

    const opened = await C.poll(
      () => {
        const t = q(env, SEL.peerTitle);
        if (t && C.text(t)) return { kind: 'chat', el: t };
        return null;
      },
      { timeout, every: 250 }
    );
    if (!opened) {
      // only a toast that actually says something counts (empty containers always exist)
      const toast = SEL.toast.map((s) => env.document.querySelector(s)).find((el) => el && C.text(el));
      if (toast) return C.result('not_found', { on_platform: false, extra: { note: 'no_findable_account' } });
      return C.fail('no_result_timeout');
    }

    const out = { on_platform: true };
    const sources = {};
    const title = C.text(opened.el);
    const peerId = opened.el.getAttribute ? opened.el.getAttribute('data-peer-id') : null;
    if (peerId) out.deep_link_id = String(peerId);

    // Open the profile sidebar (same as tapping the chat header).
    let profile = q(env, SEL.profile);
    if (!profile) {
      const header = q(env, SEL.chatInfo);
      if (header && typeof header.click === 'function') header.click();
      profile = await C.poll(() => q(env, SEL.profile), { timeout: (args && args.profileTimeoutMs) || 6000, every: 250 });
    }

    if (profile) {
      const nameEl = profile.querySelector('.profile-name .peer-title') || profile.querySelector('.profile-name');
      const userEl = profile.querySelector('.username-eng');
      const bioEl = profile.querySelector('.row-title.pre-wrap');
      out.display_name = C.firstText(C.text(nameEl), title);
      if (C.text(userEl)) out.username = C.text(userEl).replace(/^@/, '');
      if (C.text(bioEl)) out.bio = C.text(bioEl);
      if (out.display_name) sources.display_name = 'ایتا: نام در پروفایل';
      if (out.username) sources.username = 'ایتا: نام کاربری';
      if (out.bio) sources.bio = 'ایتا: بیوگرافی';
      const avatar = args && args.avatar === false ? null : await readAvatar(env, profile);
      if (avatar) {
        out.avatar_b64 = avatar;
        sources.avatar = 'ایتا: عکس پروفایل';
      }
    } else {
      out.display_name = title;
      if (title) sources.display_name = 'ایتا: عنوان گفتگو';
      out.extra = { note: 'profile_sidebar_not_opened' };
    }
    out.field_sources = sources;
    return C.result('found', out);
  }

  root.__NM_LOOKUP = run;
  root.__NM_PROBE = probe;
  if (typeof module !== 'undefined' && module.exports) module.exports = { run, probe };
})(typeof self !== 'undefined' ? self : globalThis);

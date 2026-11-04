/* NM-Mobile lookup adapters: shared helpers.
 *
 * Injected into a messenger's web client (inside an Android WebView that the OWNER
 * logged into himself) right before the platform adapter. Pure helper code: no network
 * calls of its own, no credentials, nothing is sent anywhere from here.
 *
 * Every adapter returns ONE plain JSON object:
 *   { status, on_platform, display_name, username, bio, deep_link_id, avatar_b64,
 *     field_sources, extra, error }
 * status is one of: found | not_found | hidden | login_required | error
 * Fields the platform did not return are OMITTED (never empty strings).
 */
(function (root) {
  'use strict';

  const C = {};

  C.sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  /** Calls fn() until it returns something truthy; null on timeout. */
  C.poll = async (fn, opts) => {
    const timeout = (opts && opts.timeout) || 10000;
    const every = (opts && opts.every) || 200;
    const end = Date.now() + timeout;
    for (;;) {
      let value = null;
      try {
        value = await fn();
      } catch (e) {
        value = null;
      }
      if (value) return value;
      if (Date.now() >= end) return null;
      await C.sleep(every);
    }
  };

  /** Resolves to {value} | {error} | {timeout:true}; never rejects. */
  C.withTimeout = (promise, ms) => {
    let timer;
    return Promise.race([
      Promise.resolve(promise).then(
        (value) => ({ value }),
        (e) => ({ error: String((e && e.message) || e) })
      ),
      new Promise((resolve) => {
        timer = setTimeout(() => resolve({ timeout: true }), ms);
      }),
    ]).finally(() => clearTimeout(timer));
  };

  C.digits = (s) => String(s == null ? '' : s).replace(/\D/g, '');

  C.text = (el) => (el ? String(el.innerText || el.textContent || '').trim() : '');

  C.isVisible = (el) => !!(el && el.offsetParent !== null);

  /** Drops null / undefined / '' (and empty objects) so absent fields are really absent. */
  C.clean = (obj) => {
    const out = {};
    Object.keys(obj).forEach((k) => {
      const v = obj[k];
      if (v === null || v === undefined || v === '') return;
      if (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0) return;
      out[k] = v;
    });
    return out;
  };

  /** Builds the adapter result object. */
  C.result = (status, fields) => {
    const base = Object.assign({ status }, fields || {});
    if (base.on_platform === undefined) base.on_platform = null;
    return C.clean(Object.assign({}, base, { on_platform: base.on_platform }));
  };

  C.fail = (code, message) => C.result('error', { error: code + (message ? ': ' + message : '') });

  /**
   * Shrinks an image (Blob, or a URL/blob: URL string) to a JPEG of at most maxBytes and
   * returns base64 WITHOUT the data: prefix, or null if anything goes wrong. Uses an
   * in-page canvas only; the image never leaves the page except through the adapter result.
   */
  C.shrinkImage = async (source, maxBytes, env) => {
    try {
      const e = env || { document: root.document, fetch: root.fetch && root.fetch.bind(root) };
      const limit = maxBytes || 300000;
      let blob = source;
      if (typeof source === 'string') {
        const res = await e.fetch(source);
        if (!res.ok) return null;
        blob = await res.blob();
      }
      const bitmap = await (e.createImageBitmap || root.createImageBitmap)(blob);
      let side = 512;
      for (let attempt = 0; attempt < 5; attempt++) {
        const scale = Math.min(1, side / Math.max(bitmap.width, bitmap.height));
        const canvas = e.document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(bitmap.width * scale));
        canvas.height = Math.max(1, Math.round(bitmap.height * scale));
        const ctx = canvas.getContext('2d');
        ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
        for (const q of [0.85, 0.7, 0.55, 0.4]) {
          const dataUrl = canvas.toDataURL('image/jpeg', q);
          const b64 = String(dataUrl).split(',')[1] || '';
          if (b64 && (b64.length * 3) / 4 <= limit) return b64;
        }
        side = Math.round(side * 0.7);
      }
      return null;
    } catch (err) {
      return null;
    }
  };

  /** First non-empty string of the arguments (trimmed), else null. */
  C.firstText = function () {
    for (let i = 0; i < arguments.length; i++) {
      const v = arguments[i];
      if (typeof v === 'string' && v.trim()) return v.trim();
    }
    return null;
  };

  root.NMLookupCommon = C;
  if (typeof module !== 'undefined' && module.exports) module.exports = C;
})(typeof self !== 'undefined' ? self : globalThis);

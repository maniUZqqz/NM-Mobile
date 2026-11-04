/* Bale Web adapter (web.bale.ai; the OWNER is logged in). EXPERIMENTAL.
 *
 * Grounded in the client's own code (read from https://web.bale.ai bundles):
 *  - the router treats a path `/+<8-15 digits>` like a nickname link and resolves it through the
 *    client's own search (Users.SearchContacts) and then loads that user, exactly like opening
 *    a `ble.ir/+98...` link;
 *  - loaded users are cached by the client in IndexedDB object stores "users" and "full_users".
 * So: navigate the SPA to `/+<digits>`, wait for a NEW record in the "users" store (or a
 * record that carries the number), read name / nick / about from it.
 *
 * What is NOT grounded: the exact field names of those cached records (protobuf-derived) and
 * whether the search accepts a phone number for every account. The adapter therefore reads
 * several candidate field names and, if it finds a record but cannot recognise its shape,
 * answers {status:"error", error:"unknown_record_shape", extra:{keys:[...]}} so the shape can be
 * fixed from real data. No avatar is read in this phase.
 * Status: not verified against a real logged-in session (docs/lookup.md).
 */
(function (root) {
  'use strict';

  const C = root.NMLookupCommon || require('./common.js');

  function defaultNavigate(path) {
    root.history.pushState(null, '', path);
    root.dispatchEvent(new root.PopStateEvent('popstate'));
  }

  function envOf(env) {
    if (env) return env;
    return {
      localStorage: root.localStorage,
      navigate: defaultNavigate,
      idb: realIdb(root.indexedDB),
    };
  }

  function req(r) {
    return new Promise((resolve, reject) => {
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    });
  }

  /** {dbNames(): Promise<string[]>, read(db, store): Promise<{keys, values}|null>} on top of indexedDB. */
  function realIdb(indexedDB) {
    return {
      async dbNames() {
        if (!indexedDB || typeof indexedDB.databases !== 'function') return [];
        return ((await indexedDB.databases()) || []).map((d) => d.name).filter(Boolean);
      },
      async read(dbName, storeName) {
        const db = await req(indexedDB.open(dbName));
        try {
          if (!db.objectStoreNames.contains(storeName)) return null;
          const store = db.transaction(storeName, 'readonly').objectStore(storeName);
          const [keys, values] = await Promise.all([req(store.getAllKeys()), req(store.getAll())]);
          return { keys, values };
        } finally {
          db.close();
        }
      },
    };
  }

  function loggedIn(env) {
    try {
      const u = JSON.parse(env.localStorage.getItem('user') || '{}');
      return !!(u && u.id != null);
    } catch (e) {
      return false;
    }
  }

  function probe(env) {
    env = envOf(env);
    return loggedIn(env) ? { logged_in: true, stage: 'signed_in' } : { logged_in: false, stage: 'auth' };
  }

  /** The cached user records, as [{key, value}], from whichever database has a "users" store. */
  async function readUsers(env) {
    const names = await env.idb.dbNames();
    for (const n of names) {
      const r = await env.idb.read(n, 'users').catch(() => null);
      if (r) return { db: n, rows: r.keys.map((k, i) => ({ key: String(k), value: unwrap(r.values[i]) })) };
    }
    return null;
  }

  function unwrap(v) {
    if (v && typeof v === 'object' && 'value' in v && Object.keys(v).length <= 2) return v.value;
    return v;
  }

  async function readFull(env, db, key) {
    const r = await env.idb.read(db, 'full_users').catch(() => null);
    if (!r) return null;
    const i = r.keys.map(String).indexOf(String(key));
    return i >= 0 ? unwrap(r.values[i]) : null;
  }

  /** Does any (nested, shallow) value of the record equal / end with this phone number? */
  function carriesNumber(rec, digits, depth) {
    if (rec == null || (depth || 0) > 2) return false;
    const tail = digits.slice(-10);
    for (const k of Object.keys(rec)) {
      const v = rec[k];
      if (typeof v === 'string' || typeof v === 'number') {
        const d = C.digits(v);
        if (d.length >= 10 && d.endsWith(tail)) return true;
      } else if (v && typeof v === 'object' && carriesNumber(v, digits, (depth || 0) + 1)) {
        return true;
      }
    }
    return false;
  }

  function pickName(rec) {
    return C.firstText(rec.name, rec.title, rec.displayName, rec.fullName, rec.firstName);
  }

  async function run(args, env) {
    env = envOf(env);
    const digits = C.digits(args && args.digits);
    if (digits.length < 8 || digits.length > 15) return C.fail('bad_number');
    const timeout = (args && args.resolveTimeoutMs) || 15000;

    if (!loggedIn(env)) return C.result('login_required', { error: 'bale_not_logged_in' });

    const start = await C.poll(() => readUsers(env), { timeout: (args && args.readyTimeoutMs) || 12000, every: 400 });
    if (!start) return C.fail('no_users_store', 'IndexedDB "users" not found');
    const before = new Set(start.rows.map((r) => r.key));

    env.navigate('/+' + digits);

    const hit = await C.poll(
      async () => {
        const now = await readUsers(env);
        if (!now) return null;
        const fresh = now.rows.filter((r) => !before.has(r.key));
        if (fresh.length) return { row: fresh[fresh.length - 1], db: now.db, fresh: true };
        const known = now.rows.find((r) => r.value && typeof r.value === 'object' && carriesNumber(r.value, digits));
        return known ? { row: known, db: now.db, fresh: false } : null;
      },
      { timeout, every: 500 }
    );
    if (!hit) return C.fail('no_result_timeout', 'no new user record');

    const rec = hit.row.value || {};
    const name = pickName(rec);
    const nick = C.firstText(rec.nick, rec.nickname, rec.username);
    if (!name && !nick) {
      return C.result('error', { error: 'unknown_record_shape', extra: { keys: Object.keys(rec).slice(0, 30) } });
    }
    const full = await readFull(env, hit.db, hit.row.key);
    const bio = full && typeof full === 'object' ? C.firstText(full.about, full.bio, full.description) : null;

    const sources = {};
    const out = { on_platform: true, deep_link_id: hit.row.key, extra: { from_cache: !hit.fresh } };
    if (name) {
      out.display_name = name;
      sources.display_name = 'بله: نام پروفایل';
    }
    if (nick) {
      out.username = String(nick).replace(/^@/, '');
      sources.username = 'بله: نام کاربری (nick)';
    }
    if (bio) {
      out.bio = bio;
      sources.bio = 'بله: درباره';
    }
    const local = C.firstText(rec.localName);
    if (local && local !== name) out.extra.local_name = local;
    out.field_sources = sources;
    return C.result('found', out);
  }

  root.__NM_LOOKUP = run;
  root.__NM_PROBE = probe;
  if (typeof module !== 'undefined' && module.exports) module.exports = { run, probe, realIdb, carriesNumber };
})(typeof self !== 'undefined' ? self : globalThis);

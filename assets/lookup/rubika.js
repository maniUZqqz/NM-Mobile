/* Rubika Web adapter (web.rubika.ir): NOT AVAILABLE, on purpose.
 *
 * What was read (https://web.rubika.ir main bundle): the only phone-number -> user path in the web
 * client is `addAddressBook` (adds the number to the logged-in account's contacts) over its
 * encrypted internal RPC, plus `searchGlobalObjects` (text search, no documented phone support)
 * and `getObjectByUsername` (username only). The client is an Angular production build with no
 * published globals/modules to call, so a phone lookup would mean either re-implementing Rubika's
 * encrypted protocol (not acceptable) or driving the "add contact" UI, which writes to the owner's
 * address book and for which no stable, grounded selectors exist.
 * We do not fake it: this adapter reports `adapter_unavailable`, which the app shows to the user.
 * The one-tap "open in Rubika" deep link and "save as phone contact" remain available elsewhere.
 */
(function (root) {
  'use strict';

  const C = root.NMLookupCommon || require('./common.js');

  function probe(env) {
    const d = (env && env.document) || root.document;
    const body = d && d.body ? String(d.body.innerText || d.body.textContent || '') : '';
    // The login state of Rubika web is not probed reliably (no grounded selectors).
    return { logged_in: false, stage: body ? 'unknown' : 'loading', note: 'login_state_not_probed' };
  }

  async function run() {
    return C.result('error', {
      error: 'adapter_unavailable',
      extra: { reason: 'rubika_has_no_safe_phone_lookup' },
    });
  }

  root.__NM_LOOKUP = run;
  root.__NM_PROBE = probe;
  if (typeof module !== 'undefined' && module.exports) module.exports = { run, probe };
})(typeof self !== 'undefined' ? self : globalThis);

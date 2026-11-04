'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load, doc } = require('./helpers.js');

load('common.js');
const rubika = load('rubika.js');

test('Rubika is honestly unavailable: no lookup is attempted, no data is invented', async () => {
  const r = await rubika.run({ digits: '989120000005' });
  assert.equal(r.status, 'error');
  assert.equal(r.error, 'adapter_unavailable');
  assert.equal(r.extra.reason, 'rubika_has_no_safe_phone_lookup');
  assert.equal('display_name' in r, false);
  assert.equal('on_platform' in r, false);
});

test('Rubika probe never claims a login it cannot verify', () => {
  const p = rubika.probe({ document: doc({}, 'something') });
  assert.equal(p.logged_in, false);
});

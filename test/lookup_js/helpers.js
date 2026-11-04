'use strict';
// Tiny fakes shared by the adapter tests. No network, no real messenger, no real numbers
// (all numbers used in tests are made up: 98912000xxxx).

const path = require('node:path');

const ASSETS = path.join(__dirname, '..', '..', 'assets', 'lookup');

/** querySelector over a selector->element map; supports comma lists like the real thing. */
function pick(map, sel) {
  const parts = String(sel).split(',').map((x) => x.trim());
  for (const part of parts) {
    if (map[part]) return map[part];
  }
  return null;
}

/** A fake element. `props` can hold innerText, offsetParent, attrs, children (selector -> element). */
function el(props) {
  const p = props || {};
  const node = {
    innerText: p.innerText === undefined ? '' : p.innerText,
    textContent: p.innerText === undefined ? '' : p.innerText,
    offsetParent: p.hidden ? null : {},
    src: p.src,
    currentSrc: p.src,
    clicks: 0,
    _attrs: p.attrs || {},
    _children: p.children || {},
    getAttribute(k) {
      return Object.prototype.hasOwnProperty.call(this._attrs, k) ? this._attrs[k] : null;
    },
    querySelector(sel) {
      return pick(this._children, sel);
    },
    click() {
      this.clicks += 1;
      if (p.onClick) p.onClick(this);
    },
  };
  return node;
}

/** A fake document backed by a mutable selector -> element map. */
function doc(map, bodyText) {
  const d = {
    map: map || {},
    body: { innerText: bodyText || '', textContent: bodyText || '' },
    querySelector(sel) {
      return pick(this.map, sel);
    },
    createElement() {
      return {
        width: 0,
        height: 0,
        getContext: () => ({ drawImage() {} }),
        toDataURL: () => 'data:image/jpeg;base64,QUJD',
      };
    },
  };
  return d;
}

module.exports = { ASSETS, el, doc, load: (name) => require(path.join(ASSETS, name)) };

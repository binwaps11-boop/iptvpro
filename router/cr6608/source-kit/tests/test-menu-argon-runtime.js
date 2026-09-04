'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(
  path.join(root, 'files', 'www', 'luci-static', 'resources', 'menu-argon.js'),
  'utf8'
);

class MockClassList {
  constructor(value) {
    this.values = new Set(String(value || '').split(/\s+/).filter(Boolean));
  }

  add(name) { this.values.add(name); }
  remove(name) { this.values.delete(name); }
  contains(name) { return this.values.has(name); }
  toggle(name, force) {
    const enable = force === undefined ? !this.contains(name) : Boolean(force);
    if (enable) this.add(name);
    else this.remove(name);
    return enable;
  }
}

class MockNode {
  constructor(tagName, attrs, children) {
    this.tagName = tagName || '#fragment';
    this.attributes = Object.create(null);
    this.classList = new MockClassList();
    this.style = Object.create(null);
    this.children = [];
    this.listeners = Object.create(null);
    this.parentNode = null;
    this.previousElementSibling = null;
    this.nextElementSibling = null;
    this.clickHandler = null;
    this._innerHTML = '';

    Object.entries(attrs || {}).forEach(([name, value]) => {
      if (name === 'class') this.classList = new MockClassList(value);
      else if (name === 'click') this.clickHandler = value;
      else if (value != null) this.setAttribute(name, value);
    });
    const childList = children == null ? [] : (Array.isArray(children) ? children : [children]);
    childList.forEach((child) => this.appendChild(child));
  }

  appendChild(child) {
    if (child == null) return child;
    if (Array.isArray(child)) {
      child.forEach((item) => this.appendChild(item));
      return child;
    }
    if (typeof child === 'string') child = new MockNode('#text', { text: child }, []);
    const previous = this.children.length ? this.children[this.children.length - 1] : null;
    child.parentNode = this;
    child.previousElementSibling = previous;
    if (previous) previous.nextElementSibling = child;
    this.children.push(child);
    return child;
  }

  addEventListener(type, handler) {
    if (!this.listeners[type]) this.listeners[type] = [];
    this.listeners[type].push(handler);
  }

  listenerCount(type) { return (this.listeners[type] || []).length; }

  dispatch(type) {
    const event = {
      currentTarget: this,
      target: this,
      defaultPrevented: false,
      propagationStopped: false,
      preventDefault() { this.defaultPrevented = true; },
      stopPropagation() { this.propagationStopped = true; }
    };
    (this.listeners[type] || []).forEach((handler) => handler(event));
    return event;
  }

  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null; }
  hasAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name); }
  blur() {}

  set innerHTML(value) {
    this._innerHTML = String(value);
    this.children = [];
  }

  get innerHTML() { return this._innerHTML; }
}

function E(tagName, attrs, children) {
  if (Array.isArray(tagName)) return new MockNode('#fragment', {}, tagName);
  return new MockNode(tagName, attrs, children);
}

function findByAttribute(node, name, value, results) {
  results = results || [];
  if (node && node.getAttribute && node.getAttribute(name) === value) results.push(node);
  (node && node.children || []).forEach((child) => findByAttribute(child, name, value, results));
  return results;
}

const mainmenu = new MockNode('div', { id: 'mainmenu' }, []);
const tabmenu = new MockNode('div', { id: 'tabmenu' }, []);
const showSide = new MockNode('a', { class: 'showSide', href: '#mainmenu' }, []);
const darkMask = new MockNode('div', { class: 'darkMask' }, []);
const mainRight = new MockNode('div', { class: 'main-right' }, []);
const selectorMap = {
  '#mainmenu': mainmenu,
  '#tabmenu': tabmenu,
  'a.showSide': showSide,
  '.darkMask': darkMask,
  '.main-right': mainRight
};
const documentMock = {
  querySelector(selector) { return selectorMap[selector] || null; },
  querySelectorAll() { return []; }
};

let reloadCount = 0;
let nextTimerId = 1;
const scheduledTimers = [];
const windowMock = {
  location: { reload() { reloadCount++; } },
  setTimeout(handler, delay) {
    const timer = { id:nextTimerId++, handler, delay:Number(delay) || 0, active:true };
    scheduledTimers.push(timer);
    return timer.id;
  },
  clearTimeout(id) {
    const timer = scheduledTimers.find(entry => entry.id === id);
    if (timer) timer.active = false;
  }
};
function runScheduledTimer(delay) {
  const timer = scheduledTimers.find(entry => entry.active && entry.delay === delay);
  assert.ok(timer, `missing scheduled ${delay}ms timer`);
  timer.active = false;
  timer.handler();
}
async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}
const ui = {
  createHandlerFn(context, method) {
    return function handler(event) { return context[method](event); };
  },
  menu: {
    getChildren(tree) { return Object.values(tree && tree.children || {}); }
  }
};
const L = {
  env: { requestpath: ['admin'], dispatchpath: ['admin'] },
  url() { return '/' + Array.from(arguments).filter(Boolean).join('/'); }
};
const baseclass = { extend(definition) { return definition; } };
const translate = (text) => text;
const dollar = function() {
  throw new Error('jQuery animation must not be needed by these navigation contracts');
};

const createAdapter = new Function(
  'baseclass', 'ui', 'L', 'E', '_', '$', 'document', 'window',
  source
);
const adapter = createAdapter(baseclass, ui, L, E, translate, dollar, documentMock, windowMock);

const logout = { name: 'logout', title: 'Log out', children: {} };
const wireless = { name: 'wireless', title: 'Wireless', children: {} };
const network = { name: 'network', title: 'Network', children: { wireless } };
const admin = { name: 'admin', title: 'Admin', children: { network, logout } };

const renderedMenu = adapter.renderMainMenu(admin, 'admin');
const logoutLinks = findByAttribute(renderedMenu, 'data-title', 'Log_out');
const networkLinks = findByAttribute(renderedMenu, 'data-title', 'Network');
assert.strictEqual(logoutLinks.length, 1, 'logout leaf must render exactly one link');
assert.strictEqual(logoutLinks[0].getAttribute('href'), '/admin/logout');
assert.strictEqual(logoutLinks[0].clickHandler, null, 'leaf link must not receive the expand handler');
assert.strictEqual(networkLinks.length, 1, 'network parent must render exactly one link');
assert.strictEqual(typeof networkLinks[0].clickHandler, 'function', 'submenu parent must keep the expand handler');

adapter.renderLoadFailure();
assert.strictEqual(showSide.listenerCount('click'), 1, 'failure view must bind the mobile opener');
assert.strictEqual(darkMask.listenerCount('click'), 1, 'failure view must bind the mobile mask');
assert.strictEqual(showSide.getAttribute('data-cr6608-sidebar-bound'), '1');
assert.strictEqual(darkMask.getAttribute('data-cr6608-sidebar-bound'), '1');
assert.strictEqual(showSide.getAttribute('aria-controls'), 'mainmenu');
assert.strictEqual(showSide.getAttribute('aria-expanded'), 'false');
assert.strictEqual(mainmenu.style.display, '', 'failure menu must be visible');
assert.ok(mainmenu.children.length > 0, 'failure menu must contain recovery UI');

adapter.renderLoadFailure();
assert.strictEqual(showSide.listenerCount('click'), 1, 'failure rerender must not duplicate opener binding');
assert.strictEqual(darkMask.listenerCount('click'), 1, 'failure rerender must not duplicate mask binding');

const openEvent = showSide.dispatch('click');
assert.strictEqual(openEvent.defaultPrevented, true);
assert.strictEqual(openEvent.propagationStopped, true);
assert.strictEqual(showSide.classList.contains('active'), true);
assert.strictEqual(mainmenu.classList.contains('active'), true);
assert.strictEqual(mainRight.classList.contains('active'), true);
assert.strictEqual(darkMask.classList.contains('active'), true);
assert.strictEqual(showSide.getAttribute('aria-expanded'), 'true');

adapter.renderLoadFailure();
assert.strictEqual(showSide.getAttribute('aria-expanded'), 'true', 'failure rerender must preserve truthful ARIA state');
assert.strictEqual(showSide.listenerCount('click'), 1);
assert.strictEqual(darkMask.listenerCount('click'), 1);

const closeEvent = darkMask.dispatch('click');
assert.strictEqual(closeEvent.defaultPrevented, true);
assert.strictEqual(closeEvent.propagationStopped, true);
assert.strictEqual(showSide.classList.contains('active'), false);
assert.strictEqual(mainmenu.classList.contains('active'), false);
assert.strictEqual(mainRight.classList.contains('active'), false);
assert.strictEqual(darkMask.classList.contains('active'), false);
assert.strictEqual(showSide.getAttribute('aria-expanded'), 'false');

async function runTimeoutContracts() {
  mainmenu.innerHTML = '';
  adapter.render({ name: 'root', children: { admin } });
  assert.strictEqual(showSide.listenerCount('click'), 1, 'successful render after failure must reuse opener binding');
  assert.strictEqual(darkMask.listenerCount('click'), 1, 'successful render after failure must reuse mask binding');
  assert.strictEqual(reloadCount, 0, 'runtime contracts must not invoke reload');

  mainmenu.innerHTML = '';
  mainmenu.style.display = 'none';
  ui.menu.load = function() { return new Promise(function() {}); };
  adapter.loadMenu(0);
  runScheduledTimer(5000);
  await flushPromises();
  runScheduledTimer(500);
  await flushPromises();
  runScheduledTimer(5000);
  await flushPromises();
  assert.strictEqual(mainmenu.style.display, '', 'timed-out menu did not become visible');
  assert.ok(mainmenu.children.length > 0, 'timed-out menu did not show reload recovery UI');
}

runTimeoutContracts().then(function() {
  console.log('menu_argon_runtime=pass');
}).catch(function(error) {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});

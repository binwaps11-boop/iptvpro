#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.resolve(
  __dirname, '..', 'files', 'www', 'luci-static', 'resources', 'view', 'cr6608', 'quicksettings.js'
), 'utf8');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function element(tag, attrs, children) {
  const node = { tag, attrs: attrs || {}, children };
  Object.assign(node, attrs || {});
  node.setAttribute = function(name, value) { this.attrs[name] = value; };
  node.removeAttribute = function(name) { delete this.attrs[name]; };
  if (tag === 'strong') node.textContent = String(children == null ? '' : children);
  return node;
}

function testWindow(overrides) {
  return Object.assign({
    setTimeout: (fn, ms) => setTimeout(fn, Math.min(ms, 20)),
    clearTimeout,
    setInterval: () => 1,
    clearInterval: () => {},
    location: {
      href: '', hostname: '192.168.1.1', port: '', protocol: 'http:',
      pathname: '/cgi-bin/luci/admin/system/cr6608', search: '', hash: '',
      reload: () => {}
    }
  }, overrides || {});
}

function makeView(fetchImpl, Controller, win, uiOverrides) {
  const ui = Object.assign({
    addNotification: () => {}, showModal: () => {}, hideModal: () => {}
  }, uiOverrides || {});
  const rpc = {
    declare: () => function() { return Promise.resolve({}); },
    getSessionID: () => '0123456789abcdef0123456789abcdef'
  };
  const uci = {
    get: (pkg, section, key) => {
      if (key === 'channel24' || key === 'channel5') return '36';
      if (key === 'radio0_enabled' || key === 'radio1_enabled') return '1';
      return null;
    }
  };
  return new Function(
    'view', 'uci', 'form', 'fs', 'ui', 'rpc', 'fetch', 'AbortController', 'window', 'E', '_',
    source
  )(
    { extend: value => value }, uci, {}, {}, ui, rpc, fetchImpl, Controller,
    win || testWindow(), element, value => value
  );
}

async function testBodyTimeout() {
  let aborted = 0;
  class Controller {
    constructor() { this.signal = {}; }
    abort() { aborted += 1; }
  }
  const view = makeView(
    async () => ({ ok: true, status: 200, json: () => new Promise(() => {}) }),
    Controller
  );
  let error;
  try {
    await view.requestJson('/stalled-body', {}, 1000);
  } catch (caught) {
    error = caught;
  }
  assert(error && error.code === 'request_timeout', 'stalled JSON body was not bounded');
  assert(aborted === 1, 'timed-out request did not abort its fetch');
}

async function testCompletedRequestClearsTimeout() {
  let aborted = 0;
  class Controller {
    constructor() { this.signal = {}; }
    abort() { aborted += 1; }
  }
  const view = makeView(
    async () => ({ ok: true, status: 200, json: async () => ({ ok: true }) }),
    Controller
  );
  const result = await view.requestJson('/complete', {}, 1000);
  assert(result.data.ok === true, 'successful JSON response was changed');
  await new Promise(resolve => setTimeout(resolve, 30));
  assert(aborted === 0, 'successful request left its abort timer armed');
}

function testRadioTimeoutSelection() {
  const view = makeView(async () => { throw new Error('unused'); });
  assert(view.applyTimeoutMs({ channel24:'1', radio0_enabled:'1', channel5:'36', radio1_enabled:'1' }) === 90000,
    'fixed non-DFS radios should use the normal apply timeout');
  assert(view.applyTimeoutMs({ channel24:'auto', radio0_enabled:'1', channel5:'36', radio1_enabled:'1' }) === 90000,
    '2.4 GHz auto channel incorrectly selected a DFS-length timeout');
  assert(view.applyTimeoutMs({ channel24:'1', radio0_enabled:'1', channel5:'auto', radio1_enabled:'1' }) === 710000,
    'radio1 auto channel did not allow for ACS selecting a DFS channel');
  assert(view.applyTimeoutMs({ channel24:'1', radio0_enabled:'1', channel5:'100', radio1_enabled:'1' }) === 710000,
    'radio1 DFS channel did not select the long apply timeout');
  assert(view.applyTimeoutMs({ channel24:'auto', radio0_enabled:'0', channel5:'36', radio1_enabled:'1' }) === 90000,
    'disabled auto-channel radio incorrectly selected the long timeout');
}

async function testDuplicateApplySuppression() {
  let calls = 0, complete;
  const pending = new Promise(resolve => { complete = resolve; });
  const view = makeView(() => { calls += 1; return pending; });
  view.handleSave = () => Promise.resolve();
  const button = element('button', {}, 'apply');
  const event = { currentTarget: button };
  const first = view.handleSaveApply(event);
  const second = view.handleSaveApply(event);
  await Promise.resolve();
  await Promise.resolve();
  assert(calls === 1, 'a second click started a duplicate apply request');
  assert(button.disabled === true, 'apply button was not disabled while applying');
  complete({ ok:true, status:200, statusText:'OK', json:async () => ({ ok:false, code:'mock' }) });
  await Promise.all([first, second]);
  assert(button.disabled === false, 'apply button remained disabled after a known response');
}

async function testLostResponseRecoversAuthoritativeToken() {
  let calls = 0;
  const token = 'fedcba9876543210fedcba9876543210';
  const view = makeView(async url => {
    calls += 1;
    assert(url === '/cgi-bin/dashctl?section=apply_status', 'recovery queried the wrong endpoint');
    const body = calls === 1
      ? { ok:true, busy:true, pending:true, confirmation_ready:false }
      : { ok:true, busy:false, pending:true, confirmation_ready:true, rollback_token:token, remaining_s:77 };
    return { ok:true, status:200, json:async () => body };
  });
  const recovered = await view.recoverPendingApply({ lan_ipaddr:'10.77.0.1' });
  assert(calls === 2, 'recovery did not poll while the apply worker was busy');
  assert(recovered && recovered.pending_confirmation === true, 'pending Safe Apply was not recovered');
  assert(recovered.rollback_token === token, 'recovery exposed the wrong rollback token');
  assert(recovered.rollback_remaining_s === 77, 'recovery ignored server remaining time');
  assert(recovered.management_ip === '10.77.0.1', 'recovery lost the submitted management address');
}

async function testServerCountdownAndDuplicateConfirm() {
  let calls = 0, complete, modal;
  const pending = new Promise(resolve => { complete = resolve; });
  const win = testWindow();
  const view = makeView(
    () => { calls += 1; return pending; }, undefined, win,
    { showModal: (title, content) => { modal = content; } }
  );
  view.showReachabilityConfirmation({
    rollback_timeout_s: 30,
    rollback_remaining_s: 7,
    rollback_token: '0123456789abcdef0123456789abcdef',
    management_ip: '192.168.1.1'
  });
  const counter = modal[1].children[1];
  const buttons = modal[2].children;
  assert(counter.textContent === '7', 'countdown did not start from server remaining time');
  const first = buttons[1].click();
  const second = buttons[1].click();
  await Promise.resolve();
  assert(calls === 1, 'a second click started a duplicate confirmation request');
  assert(buttons[0].disabled && buttons[1].disabled, 'confirmation buttons were not locked in flight');
  complete({ ok:true, status:200, statusText:'OK', json:async () => ({ ok:true, confirmed:true }) });
  await Promise.all([first, second]);
}

(async () => {
  await testBodyTimeout();
  await testCompletedRequestClearsTimeout();
  testRadioTimeoutSelection();
  await testLostResponseRecoversAuthoritativeToken();
  await testDuplicateApplySuppression();
  await testServerCountdownAndDuplicateConfirm();
  console.log('quicksettings_safe_apply=pass');
})().catch(error => {
  console.error(error.stack || String(error));
  process.exit(1);
});

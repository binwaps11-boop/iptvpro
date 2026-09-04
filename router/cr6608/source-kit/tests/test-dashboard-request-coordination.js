#!/usr/bin/env node
'use strict';

const assert = require('assert').strict;
const fs = require('fs');
const path = require('path');

const kitDir = path.resolve(__dirname, '..');
const dashboardPath = process.env.DASHBOARD_JS || path.join(kitDir, 'files', 'www', 'dashboard.js');
const source = fs.readFileSync(dashboardPath, 'utf8');

// Ubuntu's pinned Node 12 predates the global AbortController. Keep the
// behavior test self-contained while exercising the same signal contract used
// by fetchWithTimeout in a browser.
class TestAbortSignal {
  constructor() {
    this.aborted = false;
    this.listeners = [];
  }
  addEventListener(type, listener, options) {
    if (type !== 'abort' || typeof listener !== 'function') return;
    this.listeners.push({ listener, once:!!(options && options.once) });
  }
  removeEventListener(type, listener) {
    if (type !== 'abort') return;
    this.listeners = this.listeners.filter(entry => entry.listener !== listener);
  }
  dispatchAbort() {
    if (this.aborted) return;
    this.aborted = true;
    const entries = this.listeners.slice();
    for (const entry of entries) {
      entry.listener({ type:'abort', target:this });
      if (entry.once) this.removeEventListener('abort', entry.listener);
    }
  }
}
class TestAbortController {
  constructor() { this.signal = new TestAbortSignal(); }
  abort() { this.signal.dispatchAbort(); }
}

// Compile without executing the browser IIFE. This is a syntax gate as well as
// a source contract, so a malformed dashboard can never reach an image build.
new Function(source);

function functionSource(name) {
  const asyncNeedle = `  async function ${name}(`;
  const plainNeedle = `  function ${name}(`;
  let start = source.indexOf(asyncNeedle);
  if (start < 0) start = source.indexOf(plainNeedle);
  assert.notEqual(start, -1, `missing function ${name}`);

  const open = source.indexOf('{', start);
  let depth = 0;
  let quote = '';
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let i = open; i < source.length; i++) {
    const ch = source[i];
    const next = source[i + 1];
    if (lineComment) {
      if (ch === '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (ch === '*' && next === '/') { blockComment = false; i++; }
      continue;
    }
    if (quote) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === quote) quote = '';
      continue;
    }
    if (ch === '/' && next === '/') { lineComment = true; i++; continue; }
    if (ch === '/' && next === '*') { blockComment = true; i++; continue; }
    if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
    if (ch === '{') depth++;
    if (ch === '}' && --depth === 0) return source.slice(start + 2, i + 1);
  }
  assert.fail(`unterminated function ${name}`);
}

function includesAll(body, needles, label) {
  for (const needle of needles) assert.ok(body.includes(needle), `${label} lacks ${needle}`);
}

const fetchBody = functionSource('fetchWithTimeout');
includesAll(fetchBody, [
  'var upstreamSignal = requestOptions.signal',
  'upstreamSignal.addEventListener("abort", upstreamAbort',
  'upstreamSignal.removeEventListener("abort", upstreamAbort)',
  'requestOptions.signal = controller.signal'
], 'fetchWithTimeout');

const loadDataBody = functionSource('loadData');
includesAll(loadDataBody, [
  'if (state._pollBusy)',
  'if (forceFull === true) state.fullRefreshRequested = true',
  'var generation = ++state.dataGeneration',
  'state.dataController = ctrl',
  'countDataRequest(1)',
  'countDataRequest(-1)',
  'isDataRequestCurrent(generation, sessionAtStart)',
  'var superseded = generation !== state.dataGeneration'
], 'loadData');
assert.ok(!loadDataBody.includes('cancelDataRead()'),
  'a forced refresh aborts the healthy in-flight dashboard read instead of coalescing');
assert.ok(!/\bfetch\s*\(/.test(loadDataBody), 'loadData bypasses the bounded request helper');
const logoutBody = functionSource('logout');
includesAll(logoutBody, [
  'state.navigationPending = true',
  'state.fullRefreshRequested = false',
  'cancelDataRead()',
  'state.navigationPending = false',
  'startPolling()'
], 'logout request quiesce');
assert.ok(logoutBody.indexOf('state.navigationPending = true') < logoutBody.indexOf('cancelDataRead()') &&
  logoutBody.indexOf('state.fullRefreshRequested = false') < logoutBody.indexOf('cancelDataRead()'),
  'logout can admit a trailing full refresh while revoking the session');
assert.ok(logoutBody.lastIndexOf('state.navigationPending = false') < logoutBody.lastIndexOf('startPolling()'),
  'logout transport recovery restarts polling while navigation remains blocked');
includesAll(functionSource('scheduleDataRefresh'), [
  'clearTimeout(state.dataRefreshTimer)', 'state.dataRefreshTimer = setTimeout',
  'loadData(forceFull === true, scheduledReason)'
], 'latest-wins data scheduler');
includesAll(functionSource('queueFullRefresh'), [
  'scheduleDataRefresh(delay, true, "full-refresh")'
], 'full refresh scheduler');
assert.ok(functionSource('showSection').includes('DATA_NAV_DEBOUNCE_MS'),
  'navigation data reads bypass the debounced coordinator');
assert.ok(functionSource('render').indexOf('markLiveSnapshotUnavailable()') < functionSource('render').indexOf('state.latest = data'),
  'stale data can be committed before fail-closed invalidation');

const loadControlBody = functionSource('loadControl');
includesAll(loadControlBody, [
  'cancelControlRead()',
  'var generation = state.controlGeneration',
  'state.controlReadGeneration = generation',
  'state.controlReadController = readController',
  'isControlRequestCurrent(generation, section, box)',
  'state.controlReadGeneration === generation',
  'res.ok !== true',
  'data.ok !== true',
  'scheduleControlReadRetry(section)',
  'resetControlReadRetry(section)',
  'postJsonLocked(url, fetchOptions, controlActionTimeoutMs(section, actionName), button)',
  'controlPostNeedsRecovery(e)',
  'recoverControlAction(section, actionName, box, recoveryContext)'
], 'loadControl');
const showSectionBody = functionSource('showSection');
includesAll(showSectionBody, ['cancelControlRead()', 'bindDynamic($(id))', 'scheduleActiveControlLoad()'], 'showSection');
assert.ok(!/\bloadControl\s*\(\s*["'](?:wizard|isolation)["']/.test(showSectionBody),
  'showSection starts heavyweight control CGI before the navigation debounce');
includesAll(functionSource('cancelControlRead'), [
  'clearTimeout(state.controlLoadTimer)', 'state.controlLoadTimer = 0'
], 'cancelControlRead');
includesAll(functionSource('scheduleActiveControlLoad'), [
  'CONTROL_NAV_DEBOUNCE_MS', 'if (state.controlLoadTimer) return', 'box.dataset.loaded',
  'state.controlLoadTimer = setTimeout', 'loadActiveControl()'
], 'scheduleActiveControlLoad');
includesAll(functionSource('nextControlReadRetryDelay'), [
  'CONTROL_READ_MAX_RETRIES', 'return null', 'Math.pow(2, state.controlReadFailureCount - 1)'
], 'nextControlReadRetryDelay');
includesAll(functionSource('scheduleControlReadRetry'), [
  'nextControlReadRetryDelay(section)', 'if (delay === null) return false',
  'scheduleActiveControlLoad(delay, true)'
], 'scheduleControlReadRetry');
assert.ok(functionSource('render').includes('scheduleActiveControlLoad()'),
  'telemetry render bypasses the single control-load scheduler');
assert.ok(!/setTimeout\s*\(\s*function\s*\(\)\s*\{\s*if\s*\(!state\.postLock/.test(loadControlBody),
  'postLock retry bypasses the single control-load scheduler');
assert.ok(!loadControlBody.includes('return loadControl(section)'),
  'an action completion can still start an off-screen passive control read');
assert.ok((loadControlBody.match(/queueControlReloadIfActive\(section, box,/g) || []).length >= 3,
  'action completion paths do not use the active-section reload gate');
includesAll(functionSource('queueControlReloadIfActive'), [
  'delete box.dataset.loaded', 'activeControlSection() !== section',
  'scheduleActiveControlLoad(delayMs)'
], 'queueControlReloadIfActive');
includesAll(functionSource('recoverControlAction'), [
  'queueControlReloadIfActive(section, box, 0)',
  'delete box.dataset.loaded',
  'var status = await readApplyStatus();',
  'if (releaseIfInactive()) return true;'
], 'recoverControlAction settled refresh');
const bindControlIndex = loadControlBody.lastIndexOf('bindDynamic(box)');
assert.ok(bindControlIndex >= 0 && loadControlBody.indexOf('state.controlCache[section] = data', bindControlIndex) > bindControlIndex,
  'control payload is cached before render/binding succeeds');
assert.ok(bindControlIndex >= 0 && loadControlBody.indexOf('resetControlReadRetry(section)', bindControlIndex) > bindControlIndex,
  'control retry state is reset before render/binding succeeds');
includesAll(functionSource('retranslateControlSection'), [
  'patchHtml(container', 'state.controlCache[section]',
  'patchHtml(box, renderControlData(section, cached), { preserveTabs:true })', 'bindDynamic(box)',
  'if (keep || rollback)'
], 'retranslateControlSection');
assert.ok(!functionSource('retranslateControlSection').includes('loadControl('),
  'language switch starts a control GET');
assert.ok(!functionSource('retranslateControlSection').includes('cancelControlRead()'),
  'language switch aborts an authoritative control read');
assert.ok(!functionSource('retranslateControlSection').includes('readApplyStatus('),
  'language switch probes Safe Apply state');
includesAll(functionSource('action'), [
  'dashboardActionMayReconnect(name) && controlPostNeedsRecovery(e)',
  'waitForRouterReachable(name, button)'
], 'action');
includesAll(functionSource('runDeviceAccessAction'), [
  'presentPendingApply("wizard", pendingBox, data)',
  'controlPostNeedsRecovery(e)',
  'recoverControlAction("wizard", act, recoveryBox)'
], 'runDeviceAccessAction');
includesAll(functionSource('applyBestChannels'), [
  'j.ok !== true', 'j.confirmation_ready === true',
  'presentPendingApply("wizard", quickBox, j)', 'event("Best channel applied:'
], 'applyBestChannels');
includesAll(functionSource('recoverSessionSafeApply'), [
  'readApplyStatus()', 'quickSafeApplyBox()', 'presentPendingApply("wizard", pendingBox, status)',
  'recoverControlAction("wizard", "resume_pending_apply", recoveryBox)'
], 'recoverSessionSafeApply');
includesAll(functionSource('paintControlRecovery'), [
  'link.target = "_blank"', 'link.rel = "noopener noreferrer"'
], 'paintControlRecovery');
assert.ok(functionSource('bindDynamic').includes('await runDeviceAccessAction(mac, act, b)'),
  'device block/unblock bypasses the Safe Apply handler');
assert.ok(!source.includes('probeSafeApplyAfterControlRebuild'),
  'theme/language still depend on destructive Safe Apply rebuild recovery');
assert.ok(!functionSource('init').includes('showSection(act)'),
  'theme switch remounts the active section');

for (const name of ['syncBrowserTime', 'scanLan', 'scanWifi', 'applyBestChannels', 'action', 'loadControl', 'bindDynamic']) {
  assert.ok(functionSource(name).includes('postJsonLocked('), `${name} bypasses the global mutation lock`);
}

includesAll(functionSource('readApplyStatus'), [
  'section=apply_status',
  'RECOVERY_PROBE_TIMEOUT_MS'
], 'readApplyStatus');
includesAll(functionSource('presentPendingApply'), [
  'state.controlTokens[section] = token',
  'data-ctl-action="keep_changes"',
  'data-ctl-action="rollback_last"'
], 'presentPendingApply');
includesAll(functionSource('recoverControlAction'), [
  'readApplyStatus()',
  'applyStatusHasPendingConfirmation(status)',
  'applyStatusIsSettled(status)',
  'presentPendingApply(section, box, status)',
  'paintControlRecovery(box, safetyMessage, recoveryContext, true)',
  'controlRecoveryWindowMs(section, actionName)'
], 'recoverControlAction');
assert.ok(!source.includes('controlActionMayReconnect'), 'POST recovery still depends on an incomplete action allowlist');
includesAll(functionSource('postJsonLocked'), ['error.smartapPostFailure = true'], 'postJsonLocked');
includesAll(functionSource('controlRecoveryContext'), [
  'http_port', 'lan_ipaddr', 'device_ip', 'target.search = ""'
], 'controlRecoveryContext');
includesAll(functionSource('applyStatusIsSettled'), [
  'status.busy === false', 'status.safe_state === "clean"', 'status.pending === false'
], 'applyStatusIsSettled');

const usageBody = functionSource('dataUsage');
assert.ok(!usageBody.includes('localStorage'), 'router usage still depends on browser-local baselines');
assert.ok(!usageBody.includes('toISOString'), 'router usage still uses UTC browser boundaries');
assert.ok(!/dayBase|monthBase|yearBase/.test(source), 'legacy calendar baselines remain');
const clientLimitMatch = source.match(/var MAX_PAGE_CLIENT_MACS = (\d+);/);
assert.ok(clientLimitMatch, 'page client-memory limit is missing');
const maxPageClientMacs = Number(clientLimitMatch[1]);
assert.equal(maxPageClientMacs, 128, 'page client-memory limit changed without review');
function clientMac(index) {
  const hex = index.toString(16).padStart(10, '0');
  return `02:${hex.slice(0, 2)}:${hex.slice(2, 4)}:${hex.slice(4, 6)}:${hex.slice(6, 8)}:${hex.slice(8, 10)}`;
}
function makeClientTouch(memoryState) {
  return new Function('state', 'MAX_PAGE_CLIENT_MACS',
    `${functionSource('touchPageClient')}\nreturn touchPageClient;`
  )(memoryState, maxPageClientMacs);
}
const clientMemory = { histories:{}, knownMacs:{}, deviceNames:{}, clientMacLru:[] };
const touchClient = makeClientTouch(clientMemory);
for (let i = 0; i <= maxPageClientMacs; i++) {
  const mac = touchClient(clientMac(i).toUpperCase());
  clientMemory.knownMacs[mac] = 1;
  clientMemory.deviceNames[mac] = `client-${i}`;
  clientMemory.histories[`sig_${mac}`] = [i];
  clientMemory.histories[`rate_${mac}`] = [i];
}
const firstClient = clientMac(0);
assert.equal(clientMemory.clientMacLru.length, maxPageClientMacs, 'client LRU exceeded its fixed cap');
assert.equal(clientMemory.knownMacs[firstClient], undefined, 'oldest known MAC was not evicted');
assert.equal(clientMemory.deviceNames[firstClient], undefined, 'oldest client name was not evicted');
assert.equal(clientMemory.histories[`sig_${firstClient}`], undefined, 'oldest signal history was not evicted');
assert.equal(clientMemory.histories[`rate_${firstClient}`], undefined, 'oldest rate history was not evicted');
const retainedClient = clientMac(1);
touchClient(retainedClient);
const addedClient = touchClient(clientMac(maxPageClientMacs + 1));
clientMemory.knownMacs[addedClient] = 1;
assert.equal(clientMemory.clientMacLru[clientMemory.clientMacLru.length - 1], addedClient,
  'new client was not normalized and placed at the LRU tail');
assert.ok(clientMemory.knownMacs[retainedClient], 'recently touched client was evicted instead of the LRU client');
assert.equal(clientMemory.knownMacs[clientMac(2)], undefined,
  'LRU eviction did not remove the oldest untouched client');
const existingClient = clientMac(50);
const newClient = clientMac(maxPageClientMacs + 2);
const detectionState = {
  histories:{}, knownMacs:{ [existingClient]:1 }, deviceNames:{}, clientMacLru:[existingClient]
};
const detectionAlerts = [];
const detectionEvents = [];
const detectNewDevices = new Function(
  'state', 'mergeDevices', 'toast', 'tr', 'event', 'touchPageClient', 'MAX_PAGE_CLIENT_MACS',
  `${functionSource('detectNewDevices')}\nreturn detectNewDevices;`
)(detectionState, () => [
  { mac:existingClient.toUpperCase(), vendor:'existing' },
  { mac:newClient.toUpperCase(), vendor:'new' }
], value => detectionAlerts.push(value), value => value,
value => detectionEvents.push(value), makeClientTouch(detectionState), maxPageClientMacs);
detectNewDevices({});
detectNewDevices({});
assert.equal(detectionAlerts.length, 1,
  'an existing client was re-announced or a new client was announced twice');
assert.equal(detectionEvents.length, 1, 'new-device event deduplication does not match the alert');
assert.ok(detectionAlerts[0].includes(newClient.toUpperCase()) &&
  !detectionAlerts[0].includes(existingClient.toUpperCase()),
  'the existing client, rather than only the new client, triggered the alert');
assert.ok(detectionState.knownMacs[existingClient] && detectionState.knownMacs[newClient],
  'normalized known clients were not retained');
const normalizationState = { histories:{}, knownMacs:{}, deviceNames:{}, clientMacLru:[] };
const normalizeClient = makeClientTouch(normalizationState);
assert.equal(normalizeClient(`  ${existingClient.toUpperCase()}  `), existingClient,
  'client-memory key did not trim and normalize a valid MAC');
assert.equal(normalizeClient('not-a-mac'), '', 'invalid MAC entered client memory');
const overflowState = {
  histories:{}, knownMacs:{}, deviceNames:{}, clientMacLru:[], clientInventoryOverflow:false
};
const overflowAlerts = [];
const overflowEvents = [];
let overflowSnapshot = Array.from({ length:maxPageClientMacs + 1 }, (_, index) => ({
  mac:clientMac(1000 + index), vendor:'overflow'
}));
const detectOverflowDevices = new Function(
  'state', 'mergeDevices', 'toast', 'tr', 'event', 'touchPageClient', 'MAX_PAGE_CLIENT_MACS',
  `${functionSource('detectNewDevices')}\nreturn detectNewDevices;`
)(overflowState, () => overflowSnapshot,
value => overflowAlerts.push(value), value => value,
value => overflowEvents.push(value), makeClientTouch(overflowState), maxPageClientMacs);
detectOverflowDevices({});
detectOverflowDevices({});
detectOverflowDevices({});
assert.equal(overflowAlerts.length, 0,
  'overflowing stable client inventory generated repeated new-device alerts');
assert.equal(overflowEvents.length, 0,
  'overflowing stable client inventory generated repeated new-device events');
assert.equal(overflowState.clientMacLru.length, maxPageClientMacs,
  'overflow detection exceeded the client-memory cap');
assert.equal(Object.keys(overflowState.knownMacs).length, maxPageClientMacs,
  'overflow detection exceeded the known-client cap');
assert.equal(overflowState.clientInventoryOverflow, true,
  'overflow state was not retained across live snapshots');
overflowSnapshot = overflowSnapshot.slice(0, maxPageClientMacs);
detectOverflowDevices({});
assert.equal(overflowState.clientInventoryOverflow, false,
  'first bounded snapshot did not clear overflow state');
assert.equal(overflowAlerts.length, 0,
  'first bounded snapshot after overflow generated a false new-device alert');
detectOverflowDevices({});
assert.equal(overflowAlerts.length, 0,
  'stable bounded snapshot after overflow generated a false new-device alert');
overflowSnapshot = overflowSnapshot.slice(0, -1).concat({
  mac:clientMac(5000), vendor:'genuine-new'
});
detectOverflowDevices({});
assert.equal(overflowAlerts.length, 1,
  'genuine new client was not announced after overflow recovery');
assert.equal(overflowEvents.length, 1,
  'genuine new-client event was not recorded after overflow recovery');
assert.ok(functionSource('resetLiveSessionState').includes('state.clientMacLru = [];'),
  'authentication-boundary reset does not clear the client LRU');
assert.ok(functionSource('resetLiveSessionState').includes('state.clientInventoryOverflow = false;'),
  'authentication-boundary reset does not clear client-overflow suppression');
includesAll(functionSource('renderData'), ['counterWindow', 'routerCounter', 'topologyPartial'], 'renderData');
includesAll(functionSource('renderOverviewLite'), [
  'data.traffic.topology_complete === true', 'trafficCoverageNote(data)', 'Wi-Fi edges only'
], 'renderOverviewLite');
assert.ok(functionSource('renderPortThroughput').includes('throughputRow(i.name, num(i.tx_bps), num(i.rx_bps)'),
  'DSA client direction is not TX=download/RX=upload');
assert.ok(!functionSource('renderNetwork').includes('i.name === "br-lan" ? rates.'),
  'raw interface RX/TX still falls back to client-edge traffic');
assert.ok(!functionSource('trafficRates').includes('data.interfaces'),
  'client-edge traffic rate still sums layered interfaces');
assert.ok(!functionSource('totalTraffic').includes('data.interfaces'),
  'client-edge total still sums layered interfaces');
includesAll(functionSource('verifiedUplinkCapacity'), [
  'traffic.topology_complete !== true', 'traffic.uplink_device', 'row.connected === true',
  'row.speed_mbps', 'speed * 1000000 / 8'
], 'verifiedUplinkCapacity');

const chartScheduleBody = functionSource('scheduleChartDraw');
includesAll(chartScheduleBody, [
  'chartDrawJobs[canvasId] !== job', 'canvas !== job.node', 'canvas === $(canvasId)',
  'job.stable >= 2', 'canvas.dataset.chartStable = "1"', 'job.queued',
  'job.paint = paint'
], 'scheduleChartDraw');
const chartFlushBody = functionSource('flushScheduledCharts');
includesAll(chartFlushBody, [
  'root.querySelectorAll("canvas[id]")', 'chartDrawJobs[canvas.id]', 'job.paint()'
], 'flushScheduledCharts');
const liveSectionBody = functionSource('renderLiveSection');
includesAll(liveSectionBody, ['patchHtml($(', 'flushScheduledCharts(root)', 'bindDynamic(root)'], 'renderLiveSection');
for (const name of ['patchHtml', 'renderKpis', 'renderLiveSection', 'retranslateControlSection', 'showSection']) {
  assert.ok(!/\.innerHTML\s*=|\.outerHTML\s*=|replaceChildren\s*\(/.test(functionSource(name)),
    `${name} can replace mounted DOM`);
}
assert.ok(!/\.innerHTML\s*=|\.outerHTML\s*=|replaceChildren\s*\(/.test(source),
  'dashboard contains a forbidden structural HTML assignment');
includesAll(functionSource('patchHtml'), ['patchDomChildren(root, desired)', 'capturePatchContinuity(root, options)', 'restorePatchContinuity(root, continuity)'], 'patchHtml');
includesAll(functionSource('patchDomChildren'), ['patchNodeKey(desired)', 'insertBefore(live', 'removeChild(node)'], 'keyed reconciler');
includesAll(functionSource('patchNodeKey'), ['data-ui-key', 'data-ctl-field', 'data-insight-category'], 'stable key lookup');
assert.ok(source.includes('stable_dom:"pass"'), 'stable DOM diagnostic marker is missing');
assert.ok(source.includes('data-ui-key="kpi:') && source.includes('data-ui-key="device:') &&
  source.includes('data-ui-key="station:') && source.includes('data-ui-key="interface:') &&
  source.includes('data-ui-key="insight:'), 'keyed live collections are incomplete');
assert.ok(!/setTimeout\(function \(\) \{ draw(?:Channels|Constellation)/.test(source),
  'raw Wi-Fi canvas timers can paint a replaced node');

for (const staleText of [
  'CAP=1000000000', 'Weekly Digest', 'Network Score', 'ALL GOOD', 'ALL OK',
  'No tips — all tuned', 'Never drop weak', 'never dropped', 'protected — never dropped',
  'Co-Channel Pressure', 'Management Exposure', 'Rogue Neighbor Watch',
  'WPA / PMF Posture', 'Gateway RTT Grade', 'Jitter Estimate'
]) {
  assert.ok(!source.includes(staleText), `misleading UI claim remains: ${staleText}`);
}
assert.ok(!/grand\s*\+=/.test(source), 'layered interface counters still produce a grand total');
assert.ok(!/\/8\/AVG/.test(source), 'byte-rate PPS estimate still divides by 8');
includesAll(functionSource('card'), ['esc(title)', 'esc(chip)'], 'card metadata escaping');
includesAll(functionSource('sectionHead'), ['esc(title)', 'esc(desc)', 'esc(chip)'], 'sectionHead metadata escaping');

let mutationRemainder = source;
for (const name of ['postJsonLocked', 'revokeServerSessions', 'ensureLuciSession', 'login']) {
  mutationRemainder = mutationRemainder.replace(functionSource(name), '');
}
assert.ok(!/method\s*:\s*["']POST["']/.test(mutationRemainder), 'an uncoordinated dashboard POST remains');

const bindBody = functionSource('bindDynamic');
includesAll(bindBody, ['function bindDynamic(rootNode)', 'root.querySelectorAll(', 'dynamicId(root,'], 'bindDynamic');
includesAll(bindBody, ['resetControlReadRetry(b.dataset.ctlRefresh)', 'loadControl(b.dataset.ctlRefresh)'],
  'manual control refresh');
assert.ok(!bindBody.includes('document.querySelectorAll'), 'bindDynamic still scans the whole document');
assert.ok(!bindBody.includes('addEventListener('), 'repeated dynamic binding can stack event listeners');
assert.ok(!/\bbindDynamic\(\s*\);/.test(source), 'a full-document bindDynamic call remains');

const stationTrafficRowsBody = functionSource('stationTrafficRows');
includesAll(stationTrafficRowsBody, ['stationTraffic(s)', 'if (!t.hasRate) return', 'rateSource: t.rateSource'], 'stationTrafficRows');
assert.ok(!/\b(?:tx|rx)_rate\b|expected_mbps/.test(stationTrafficRowsBody),
  'per-client traffic rows still use PHY/estimate telemetry as consumption');
includesAll(functionSource('parseStationRateDetail'), [
  'HE|VHT', 'nssSource = "reported"', 'nssSource = "ht-mcs"', 'shortGi', 'width: width'
], 'parseStationRateDetail');
includesAll(functionSource('configuredPhyCeiling2x2'), ['20:286.8', '40:573.5', '80:1201.0'], 'configuredPhyCeiling2x2');
for (const stalePattern of [
  /var MAX=1201/,
  /Math\.round\(rate\/b\)/,
  /if\(r>=700\)two\+\+/,
  /H\.clamp\(tx\/ex\*100/,
  /inferred from radio htmode/,
  /Closest to Ceiling/,
  /Per-Client PHY Efficiency/,
  /Spectral Efficiency/,
  /Airtime Efficiency/
]) {
  assert.ok(!stalePattern.test(source), `misleading PHY/throughput heuristic remains: ${stalePattern}`);
}
assert.ok(source.includes('Byte-counter deltas only; last PHY snapshots and expected_mbps are never used as traffic.'),
  'traffic UI no longer states its measured-counter source');
assert.ok(source.includes('Last PHY snapshot') && source.includes('not throughput'),
  'PHY snapshot UI lost its explicit non-throughput semantics');

async function behaviorTests() {
  const timerJobs = new Map();
  let nextTimerId = 1;
  const scheduledLoads = [];
  const schedulerState = { session:'cookie', dataRefreshTimer:0, dataRefreshReason:'' };
  const scheduleRefresh = new Function(
    'state', 'setTimeout', 'clearTimeout', 'publishDataRequestDebug', 'loadData',
    `${functionSource('scheduleDataRefresh')}\nreturn scheduleDataRefresh;`
  )(
    schedulerState,
    (callback, delay) => { const id = nextTimerId++; timerJobs.set(id, { callback, delay, cleared:false }); return id; },
    id => { if (timerJobs.has(id)) timerJobs.get(id).cleared = true; },
    () => {}, (full, reason) => scheduledLoads.push({ full, reason })
  );
  for (let index = 0; index < 8; index++) scheduleRefresh(180, true, `nav-${index}`);
  const liveTimerJobs = [...timerJobs.values()].filter(job => !job.cleared);
  assert.equal(liveTimerJobs.length, 1, 'navigation burst left multiple live data timers');
  liveTimerJobs[0].callback();
  assert.deepEqual(scheduledLoads, [{ full:true, reason:'nav-7' }],
    'latest-wins scheduler did not execute exactly the latest intent');
  assert.equal(schedulerState.dataRefreshTimer, 0, 'settled data timer retained ownership');

  const requestCountState = { activeDataRequests:0, maxActiveDataRequests:0 };
  const countRequest = new Function(
    'state', 'publishDataRequestDebug',
    `${functionSource('countDataRequest')}\nreturn countDataRequest;`
  )(requestCountState, () => {});
  countRequest(1); countRequest(-1); countRequest(1); countRequest(-1);
  assert.deepEqual(requestCountState, { activeDataRequests:0, maxActiveDataRequests:1 },
    'sequential GET instrumentation did not retain maxActive=1');

  const abandonedRecoveryBox = { dataset:{ loaded:'1' }, isConnected:true };
  const recoverControl = new Function(
    'state', 'controlRecoveryWindowMs', 'activeControlSection',
    `${functionSource('recoverControlAction')}\nreturn recoverControlAction;`
  )({ lang:'en' }, () => 1000, () => 'isolation');
  assert.equal(await recoverControl('wizard', 'resume_pending_apply', abandonedRecoveryBox), true,
    'off-screen Safe Apply recovery did not terminate');
  assert.equal(abandonedRecoveryBox.dataset.loaded, undefined,
    'off-screen Safe Apply recovery left the wizard permanently loaded');

  let deferredRecoveryActive = 'wizard', resolveRecoveryProbe, pendingPaints = 0;
  const deferredRecoveryProbe = new Promise(resolve => { resolveRecoveryProbe = resolve; });
  const recoverDeferredControl = new Function(
    'state', 'controlRecoveryWindowMs', 'activeControlSection', 'readApplyStatus',
    'applyStatusHasPendingConfirmation', 'presentPendingApply', 'paintControlRecovery',
    `${functionSource('recoverControlAction')}\nreturn recoverControlAction;`
  )(
    { lang:'en' }, () => 1000, () => deferredRecoveryActive,
    () => deferredRecoveryProbe, () => true, () => { pendingPaints++; return true; }, () => {}
  );
  const deferredRecoveryBox = { dataset:{}, isConnected:true };
  const deferredRecoveryResult = recoverDeferredControl(
    'wizard', 'resume_pending_apply', deferredRecoveryBox, { targetUrl:'' }
  );
  await Promise.resolve();
  deferredRecoveryActive = 'isolation';
  resolveRecoveryProbe({ ok:true, pending:true });
  assert.equal(await deferredRecoveryResult, true,
    'navigation during an in-flight Safe Apply probe did not terminate recovery');
  assert.equal(deferredRecoveryBox.dataset.loaded, undefined,
    'navigation during an in-flight Safe Apply probe left the old panel loaded');
  assert.equal(pendingPaints, 0,
    'an in-flight Safe Apply response painted into an off-screen panel');

  let activeControl = 'isolation';
  const queuedReloads = [];
  const resetReloads = [];
  const queueReload = new Function(
    'activeControlSection', 'scheduleActiveControlLoad', 'resetControlReadRetry',
    `${functionSource('queueControlReloadIfActive')}\nreturn queueControlReloadIfActive;`
  )(() => activeControl, delay => queuedReloads.push(delay), section => resetReloads.push(section));
  const offscreenWizard = { dataset:{ loaded:'1' }, isConnected:true };
  assert.equal(queueReload('wizard', offscreenWizard, 0), false,
    'off-screen action completion claimed it queued a wizard reload');
  assert.equal(offscreenWizard.dataset.loaded, undefined,
    'off-screen action completion left the old wizard permanently loaded');
  assert.equal(queuedReloads.length, 0,
    'off-screen action completion cancelled or replaced the active panel timer');
  assert.equal(resetReloads.length, 0, 'off-screen action completion reset another panel retry state');
  activeControl = 'wizard';
  assert.equal(queueReload('wizard', offscreenWizard, 750), true,
    'active wizard reload was not queued');
  assert.deepEqual(queuedReloads, [750], 'active wizard reload changed its requested delay');
  assert.deepEqual(resetReloads, ['wizard'], 'active action reload did not reopen exhausted reads');

  const scheduledState = { controlLoadTimer:0 };
  const scheduledBox = { dataset:{} };
  const scheduledDelays = [];
  const scheduleControl = new Function(
    'state', 'activeControlSection', '$', 'sid', 'isFinite', 'setTimeout',
    'CONTROL_NAV_DEBOUNCE_MS', 'loadActiveControl',
    `${functionSource('scheduleActiveControlLoad')}\nreturn scheduleActiveControlLoad;`
  )(
    scheduledState, () => 'wizard', id => id === 'ctl_wizard' ? scheduledBox : null,
    value => value, Number.isFinite,
    (_callback, delay) => { scheduledDelays.push(delay); return 41; }, 500, () => {}
  );
  scheduleControl(750);
  scheduleControl();
  assert.deepEqual(scheduledDelays, [750],
    'background render shortened or duplicated an existing control retry');
  scheduledState.controlLoadTimer = 0;
  scheduledBox.dataset.loaded = '1';
  scheduleControl(500);
  assert.deepEqual(scheduledDelays, [750], 'a loaded panel scheduled a redundant control GET');

  const retryState = { controlReadFailureSection:'', controlReadFailureCount:0 };
  const nextRetry = new Function(
    'state', 'CONTROL_READ_MAX_RETRIES', 'CONTROL_READ_RETRY_MS',
    `${functionSource('nextControlReadRetryDelay')}\nreturn nextControlReadRetryDelay;`
  )(retryState, 3, 750);
  assert.deepEqual(
    [nextRetry('wizard'), nextRetry('wizard'), nextRetry('wizard'), nextRetry('wizard')],
    [750, 1500, 3000, null],
    'persistent passive control failure does not stop after three retries'
  );

  const renderRetryState = {
    postLock:false, controlGeneration:7, controlReadController:null,
    controlReadBox:null, controlReadGeneration:0, lang:'en',
    controlCache:{ wizard:{ ok:true, marker:'last-known-good' } }
  };
  const renderRetryBox = { dataset:{}, isConnected:true, className:'', textContent:'', innerHTML:'' };
  const renderRetryDelays = [];
  let renderShouldFail = true, renderResetCount = 0;
  function scheduleRenderRetry(section) {
    const delay = nextRenderRetry(section);
    renderRetryDelays.push(delay);
    return delay !== null;
  }
  function resetRenderRetry(section) {
    renderResetCount++;
    if (renderRetryState.controlReadFailureSection !== section) return;
    renderRetryState.controlReadFailureSection = '';
    renderRetryState.controlReadFailureCount = 0;
  }
  const nextRenderRetry = new Function(
    'state', 'CONTROL_READ_MAX_RETRIES', 'CONTROL_READ_RETRY_MS',
    `${functionSource('nextControlReadRetryDelay')}\nreturn nextControlReadRetryDelay;`
  )(renderRetryState, 3, 750);
  const makeLoadControl = new Function('deps', `
    var state = deps.state, $ = deps.$, sid = deps.sid;
    var cancelControlRead = deps.cancelControlRead, authUrl = deps.authUrl, CTL = deps.CTL;
    var authHeaders = deps.authHeaders, fetchWithTimeout = deps.fetchWithTimeout;
    var API_TIMEOUT_MS = deps.API_TIMEOUT_MS, isControlRequestCurrent = deps.isControlRequestCurrent;
    var controlActionAffectsSnapshot = deps.controlActionAffectsSnapshot;
    var renderControlData = deps.renderControlData, syncWizardMode = deps.syncWizardMode;
    var bindDynamic = deps.bindDynamic, isAbortError = deps.isAbortError;
    var activeControlSection = deps.activeControlSection;
    var scheduleControlReadRetry = deps.scheduleControlReadRetry;
    var resetControlReadRetry = deps.resetControlReadRetry;
    var patchHtml = deps.patchHtml;
    ${functionSource('loadControl')}
    return loadControl;
  `);
  const loadControlForRenderRetry = makeLoadControl({
    state:renderRetryState,
    $:id => id === 'ctl_wizard' ? renderRetryBox : null,
    sid:value => value,
    cancelControlRead:() => {}, authUrl:value => value, CTL:'/dashctl',
    authHeaders:() => ({}), API_TIMEOUT_MS:1000,
    fetchWithTimeout:async () => ({ status:200, ok:true, json:async () => ({ ok:true, marker:'new-payload' }) }),
    isControlRequestCurrent:() => true,
    controlActionAffectsSnapshot:() => false,
    renderControlData:() => { if (renderShouldFail) throw new Error('malformed-control-payload'); return '<div>ok</div>'; },
    syncWizardMode:() => {}, bindDynamic:() => {}, isAbortError:() => false,
    activeControlSection:() => 'wizard', scheduleControlReadRetry:scheduleRenderRetry,
    resetControlReadRetry:resetRenderRetry,
    patchHtml:(box, html) => { box.renderedHtml = html; }
  });
  for (let attempt = 0; attempt < 4; attempt++) await loadControlForRenderRetry('wizard');
  assert.deepEqual(renderRetryDelays, [750, 1500, 3000, null],
    'render failures reset backoff or bypass the three-retry terminal gate');
  assert.equal(renderResetCount, 0, 'a failed render reset passive-read backoff');
  assert.equal(renderRetryState.controlCache.wizard.marker, 'last-known-good',
    'a malformed control payload replaced the last known-good cache entry');
  renderShouldFail = false;
  await loadControlForRenderRetry('wizard');
  assert.equal(renderResetCount, 1, 'a fully rendered control response did not reset backoff');
  assert.equal(renderRetryState.controlCache.wizard.marker, 'new-payload',
    'a fully rendered control response was not cached');

  const htmlEscape = value => String(value == null ? '' : value)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  const renderCard = new Function('icon', 'esc', `${functionSource('card')}\nreturn card;`)(() => '', htmlEscape);
  const renderSectionHead = new Function('esc', `${functionSource('sectionHead')}\nreturn sectionHead;`)(htmlEscape);
  const xssPayload = '<img src=x onerror="globalThis.pwned=1" data-xss>';
  const escapedMetadata = renderCard(xssPayload, '<b>trusted body</b>', xssPayload, 'shield') +
    renderSectionHead(xssPayload, xssPayload, xssPayload);
  assert.ok(!escapedMetadata.includes('<img'), 'card/section metadata allows an injected element');
  assert.ok(escapedMetadata.includes('&lt;img'), 'card/section metadata payload was not rendered as text');

  const uplinkCapacity = new Function(
    `${functionSource('num')}\n${functionSource('finite')}\n${functionSource('verifiedUplinkCapacity')}\nreturn verifiedUplinkCapacity;`
  )();
  const verified = uplinkCapacity({
    traffic:{ topology_complete:true, uplink_device:'lan3' },
    interfaces:[
      { name:'lan1', connected:true, speed_mbps:2500 },
      { name:'lan3', connected:true, speed_mbps:1000 }
    ]
  });
  assert.deepEqual(verified, { device:'lan3', speedMbps:1000, bytesPerSecond:125000000 },
    'verified utilization did not use the matching uplink speed');
  assert.equal(uplinkCapacity({ traffic:{ topology_complete:false, uplink_device:'lan3' }, interfaces:[{ name:'lan3', connected:true, speed_mbps:1000 }] }), null,
    'partial topology produced a utilization capacity');
  assert.equal(uplinkCapacity({ traffic:{ topology_complete:true, uplink_device:'lan3' }, interfaces:[{ name:'lan3', connected:true }] }), null,
    'missing documented link speed produced a utilization capacity');
  assert.equal(uplinkCapacity({ traffic:{ topology_complete:true, uplink_device:'lan3' }, interfaces:[{ name:'lan3', connected:false, speed_mbps:1000 }] }), null,
    'disconnected uplink produced a utilization capacity');

  const parseRate = new Function(
    `${functionSource('num')}\n${functionSource('finite')}\n${functionSource('parseStationRateDetail')}\nreturn parseStationRateDetail;`
  )();
  const idleHe1 = parseRate({
    tx_rate:24.3,
    tx_rate_detail:'24.3 MBit/s 20MHz HE-MCS 2 HE-NSS 1 HE-GI 1'
  }, 'tx');
  assert.deepEqual(
    { rate:idleHe1.rate, width:idleHe1.width, family:idleHe1.family, mcs:idleHe1.mcs, nss:idleHe1.nss, source:idleHe1.nssSource, gi:idleHe1.gi },
    { rate:24.3, width:20, family:'HE', mcs:2, nss:1, source:'reported', gi:1 },
    '24.3 Mbps idle HE fixture was not parsed as the reported 1SS/MCS2 snapshot'
  );
  const activeHe2 = parseRate({
    tx_rate:270.8,
    tx_rate_detail:'270.8 MBit/s 20MHz HE-MCS 11 HE-NSS 2 HE-GI 1'
  }, 'tx');
  assert.equal(activeHe2.nss, 2, '270.8 Mbps HE fixture lost its reported 2SS value');
  assert.equal(activeHe2.mcs, 11, '270.8 Mbps HE fixture lost MCS11');
  const vht2 = parseRate({ tx_rate_detail:'866.7 MBit/s 80MHz short GI VHT-MCS 9 VHT-NSS 2' }, 'tx');
  assert.deepEqual({ family:vht2.family, width:vht2.width, mcs:vht2.mcs, nss:vht2.nss, gi:vht2.gi },
    { family:'VHT', width:80, mcs:9, nss:2, gi:'short' }, 'VHT rate details are not parsed correctly');
  const ht2 = parseRate({ tx_rate_detail:'300.0 MBit/s 40MHz short GI MCS 15' }, 'tx');
  assert.deepEqual({ family:ht2.family, width:ht2.width, mcs:ht2.mcs, nss:ht2.nss, source:ht2.nssSource },
    { family:'HT', width:40, mcs:15, nss:2, source:'ht-mcs' }, 'HT MCS did not produce its exact NSS');
  const unknownNss = parseRate({ tx_rate:1201, tx_rate_detail:'1201.0 MBit/s 80MHz HE-MCS 11 HE-GI 1' }, 'tx');
  assert.equal(unknownNss.nss, null, 'NSS was guessed from Mbps when the driver did not report it');

  const configuredCapacity = new Function(
    `${functionSource('num')}\n${functionSource('finite')}\n${functionSource('radioWidthMHz')}\n${functionSource('configuredPhyCeiling2x2')}\nreturn configuredPhyCeiling2x2;`
  )();
  assert.equal(configuredCapacity({ htmode:'HE20' }).mbps, 286.8, 'HE20 2x2 capability changed');
  assert.equal(configuredCapacity({ htmode:'HE80' }).mbps, 1201, 'HE80 2x2 capability changed');
  assert.equal(configuredCapacity({ htmode:'VHT80' }).mbps, 866.7, 'VHT80 2x2 capability changed');
  assert.equal(configuredCapacity({ htmode:'HT40' }).mbps, 300, 'HT40 2x2 capability changed');

  const trafficRows = new Function(
    `${functionSource('num')}\n${functionSource('finite')}\n${functionSource('stationTraffic')}\n${functionSource('stationTrafficRows')}\nreturn stationTrafficRows;`
  )();
  const measuredRows = trafficRows({ wifi:[{ band:'2.4G', stations:[
    { mac:'idle-phy', tx_rate:1201, rx_rate:1201, expected_mbps:999, upload_bytes:900000, download_bytes:800000 },
    { mac:'measured', tx_rate:24.3, expected_mbps:1, upload_bps:3200, download_bps:22000 }
  ] }] });
  assert.deepEqual(measuredRows.map(row => row.mac), ['measured'],
    'PHY/expected telemetry leaked into measured per-client traffic rows');
  assert.equal(measuredRows[0].totalRate, 25200, 'measured byte-rate deltas were not preserved');
  assert.equal(measuredRows[0].rateSource, 'byte-counter-delta', 'traffic rate source is not explicit');

  const makeControlTimeout = new Function(
    'CONTROL_TIMEOUT_MS', 'NETWORK_CONTROL_TIMEOUT_MS', 'WIFI_CONTROL_TIMEOUT_MS',
    `${functionSource('controlActionTimeoutMs')}\nreturn controlActionTimeoutMs;`
  );
  const controlTimeout = makeControlTimeout(130000, 190000, 740000);
  assert.equal(controlTimeout('wizard', 'apply_royal'), 740000, 'guarded Wi-Fi apply keeps the full server window');
  assert.equal(controlTimeout('rawuci', 'raw_uci_commit_reload'), 740000, 'raw UCI can reload Wi-Fi but still has a short timeout');
  assert.equal(controlTimeout('wizard', 'resume_pending_apply'), 740000, 'resumed Safe Apply recovery has a short timeout');
  assert.equal(controlTimeout('interfaces', 'save_interface'), 190000, 'network reload timeout is too short');
  assert.equal(controlTimeout('system', 'save_system'), 130000, 'ordinary control timeout changed unexpectedly');

  const makeControlRecoveryWindow = new Function(
    'RECOVERY_WINDOW_MS', 'RECOVERY_GRACE_MS', 'WIFI_CONTROL_TIMEOUT_MS', 'WIFI_RECOVERY_WINDOW_MS', 'controlActionTimeoutMs',
    `${functionSource('controlRecoveryWindowMs')}\nreturn controlRecoveryWindowMs;`
  );
  const controlRecoveryWindow = makeControlRecoveryWindow(180000, 20000, 740000, 1740000, controlTimeout);
  assert.equal(controlRecoveryWindow('wizard', 'apply_royal'), 1740000, 'DFS recovery does not outlive the 1700s worker guard');
  assert.equal(controlRecoveryWindow('rawuci', 'raw_uci_commit_reload'), 1740000, 'raw UCI recovery can stop before its Wi-Fi worker guard');
  assert.equal(controlRecoveryWindow('interfaces', 'save_interface'), 210000, 'network recovery lacks its action-aware grace');
  assert.equal(controlRecoveryWindow('system', 'save_system'), 180000, 'ordinary recovery should retain the minimum window');

  const makeActionTimeout = new Function(
    'WIFI_CONTROL_TIMEOUT_MS',
    `${functionSource('dashboardActionTimeoutMs')}\nreturn dashboardActionTimeoutMs;`
  );
  const actionTimeout = makeActionTimeout(740000);
  assert.equal(actionTimeout('wifi_radio0'), 740000, 'radio toggle still has a false short timeout');
  assert.equal(actionTimeout('reconnect'), 45000, 'WAN reconnect timeout no longer covers its bounded wait');

  const makeDashboardRecoveryWindow = new Function(
    'RECOVERY_WINDOW_MS', 'RECOVERY_GRACE_MS', 'WIFI_CONTROL_TIMEOUT_MS', 'WIFI_RECOVERY_WINDOW_MS', 'dashboardActionTimeoutMs',
    `${functionSource('dashboardRecoveryWindowMs')}\nreturn dashboardRecoveryWindowMs;`
  );
  const dashboardRecoveryWindow = makeDashboardRecoveryWindow(180000, 20000, 740000, 1740000, actionTimeout);
  assert.equal(dashboardRecoveryWindow('wifi_radio0'), 1740000, 'radio reconnect recovery is shorter than the worker guard');
  assert.equal(dashboardRecoveryWindow('reconnect'), 180000, 'ordinary WAN reconnect lost the minimum recovery window');

  const recoveryBackoff = new Function(`${functionSource('recoveryPollDelayMs')}\nreturn recoveryPollDelayMs;`)();
  assert.deepEqual([0, 4, 5, 14, 15, 100].map(recoveryBackoff), [2000, 2000, 5000, 5000, 10000, 10000],
    'recovery polling backoff is not bounded/staged');

  const validRecoveryIp = new Function(`${functionSource('validRecoveryIpv4')}\nreturn validRecoveryIpv4;`)();
  const makeRecoveryContext = new Function(
    'window', 'validRecoveryIpv4',
    `${functionSource('controlRecoveryContext')}\nreturn controlRecoveryContext;`
  );
  const recoveryContext = makeRecoveryContext(
    { location:{ href:'http://192.168.1.1/', origin:'http://192.168.1.1' } }, validRecoveryIp
  );
  assert.equal(
    recoveryContext('administration', 'save_admin_access', '&http_port=8080').targetUrl,
    'http://192.168.1.1:8080/',
    'HTTP-port changes do not expose the possible new management origin'
  );
  assert.equal(
    recoveryContext('dhcp', 'save_dhcp', '&lan_ipaddr=192.168.8.1').targetUrl,
    'http://192.168.8.1/',
    'LAN-address changes do not expose the possible new management origin'
  );
  assert.equal(recoveryContext('administration', 'save_admin_access', '&http_port=70000').targetUrl, '',
    'invalid recovery port was accepted');

  const postNeedsRecovery = new Function(`${functionSource('controlPostNeedsRecovery')}\nreturn controlPostNeedsRecovery;`)();
  assert.equal(postNeedsRecovery({ smartapPostFailure:true, code:'SMARTAP_TIMEOUT' }), true,
    'tagged POST timeout does not enter authoritative recovery');
  assert.equal(postNeedsRecovery({ code:'SMARTAP_POST_BUSY' }), false,
    'a mutation rejected before sending incorrectly enters recovery');
  const pendingApply = new Function(`${functionSource('applyStatusHasPendingConfirmation')}\nreturn applyStatusHasPendingConfirmation;`)();
  const settledApply = new Function(`${functionSource('applyStatusIsSettled')}\nreturn applyStatusIsSettled;`)();
  assert.equal(pendingApply({ busy:false, safe_state:'armed', pending:true, confirmation_ready:true, remaining_s:119, rollback_token:'a'.repeat(32) }), true,
    'valid armed Safe Apply state is not confirmable');
  assert.equal(pendingApply({ busy:false, safe_state:'armed', pending:true, confirmation_ready:true, remaining_s:119, rollback_token:'' }), false,
    'armed Safe Apply without a token was accepted');
  assert.equal(pendingApply({ busy:false, safe_state:'armed', pending:true, confirmation_ready:false, remaining_s:119, rollback_token:'a'.repeat(32) }), false,
    'armed transaction without a completed-success marker was accepted');
  assert.equal(pendingApply({ busy:false, safe_state:'armed', pending:true, confirmation_ready:true, remaining_s:0, rollback_token:'a'.repeat(32) }), false,
    'expired transaction was offered for confirmation');
  assert.equal(settledApply({ busy:false, safe_state:'clean', pending:false }), true,
    'exact clean Safe Apply state was not accepted');
  assert.equal(settledApply({ busy:false, safe_state:'invalid', pending:false }), false,
    'invalid Safe Apply state was treated as settled');

  let resumedStatus = {
    ok:true, busy:false, safe_state:'armed', pending:true, confirmation_ready:true,
    remaining_s:119, rollback_token:'d'.repeat(32)
  };
  let resumedQuickOpens = 0, resumedPendingRenders = 0, resumedRecoveryCalls = 0;
  const recoverSession = new Function(
    'readApplyStatus', 'applyStatusHasPendingConfirmation', 'quickSafeApplyBox',
    'presentPendingApply', 'toast', 'state', 'paintControlRecovery', 'recoverControlAction',
    `${functionSource('recoverSessionSafeApply')}\nreturn recoverSessionSafeApply;`
  )(
    async () => resumedStatus, pendingApply, () => { resumedQuickOpens++; return { dataset:{}, isConnected:true }; },
    () => { resumedPendingRenders++; return true; }, () => {}, { lang:'en' }, () => {},
    async () => { resumedRecoveryCalls++; return true; }
  );
  assert.equal(await recoverSession(), true, 'session resume ignored a ready Safe Apply transaction');
  assert.equal(resumedQuickOpens, 1, 'session resume did not open Quick for pending confirmation');
  assert.equal(resumedPendingRenders, 1, 'session resume did not restore Keep/Rollback');
  resumedStatus = { ok:true, busy:false, safe_state:'clean', pending:false, confirmation_ready:false };
  assert.equal(await recoverSession(), false, 'clean session resume suppressed normal startup work');
  resumedStatus = { ok:true, busy:false, safe_state:'armed', pending:true, confirmation_ready:false, remaining_s:80, text:'waiting' };
  assert.equal(await recoverSession(), true, 'unready armed transaction was treated as clean');
  assert.equal(resumedRecoveryCalls, 1, 'unready armed transaction did not start fail-closed recovery');

  let recoveryNow = 0, recoveryProbes = 0, recoveryReloads = 0;
  const recoverAction = new Function(
    'state', 'Date', 'controlRecoveryWindowMs', 'activeControlSection', 'readApplyStatus',
    'applyStatusHasPendingConfirmation', 'presentPendingApply', 'applyStatusIsSettled',
    'toast', 'queueControlReloadIfActive', 'sleepMs', 'recoveryPollDelayMs', 'paintControlRecovery',
    `${functionSource('recoverControlAction')}\nreturn recoverControlAction;`
  )(
    { lang:'en', controlRecoveryTargets:{} }, { now:() => recoveryNow }, controlRecoveryWindow,
    () => 'wizard', async () => {
      recoveryProbes++;
      return recoveryNow < 300000
        ? { busy:true, safe_state:'armed', pending:true, rollback_token:'a'.repeat(32) }
        : { busy:false, safe_state:'clean', pending:false };
    },
    pendingApply, () => false, settledApply, () => {}, () => { recoveryReloads++; return true; },
    async () => { recoveryNow += 100000; }, recoveryBackoff,
    (box, message) => { box.textContent = message; }
  );
  const recoveryBox = { dataset:{}, className:'', textContent:'', isConnected:true };
  assert.equal(await recoverAction('wizard', 'apply_royal', recoveryBox), true, 'action recovery did not complete');
  assert.ok(recoveryNow > 180000, 'DFS recovery stopped at the old fixed three-minute window');
  assert.equal(recoveryProbes, 4, 'mocked DFS recovery did not poll through the busy interval');
  assert.equal(recoveryReloads, 1, 'mocked DFS recovery did not refresh after the apply lock cleared');
  for (const actionName of ['save_bridge_options', 'set_port_state', 'save_admin_access', 'raw_uci_commit_reload']) {
    assert.equal(await recoverAction('wizard', actionName, { dataset:{}, isConnected:true }), true,
      `${actionName} is still excluded from POST recovery`);
  }

  let safetyNow = 0, safetyProbe = 0, safetyReloads = 0;
  const safetyWarnings = [];
  const recoverUnsafeState = new Function(
    'state', 'Date', 'controlRecoveryWindowMs', 'activeControlSection', 'readApplyStatus',
    'applyStatusHasPendingConfirmation', 'presentPendingApply', 'applyStatusIsSettled',
    'toast', 'queueControlReloadIfActive', 'sleepMs', 'recoveryPollDelayMs', 'paintControlRecovery',
    `${functionSource('recoverControlAction')}\nreturn recoverControlAction;`
  )(
    { lang:'en', controlRecoveryTargets:{} }, { now:() => safetyNow }, controlRecoveryWindow,
    () => 'wizard', async () => {
      safetyProbe++;
      if (safetyProbe === 1) return { busy:false, safe_state:'invalid', pending:false };
      if (safetyProbe === 2) return { busy:false, safe_state:'armed', pending:true, rollback_token:'' };
      return { busy:false, safe_state:'clean', pending:false };
    },
    pendingApply, () => false, settledApply, () => {}, () => { safetyReloads++; return true; },
    async () => { safetyNow += 1000; }, recoveryBackoff,
    (box, message, _context, warning) => { box.textContent = message; if (warning) safetyWarnings.push(message); }
  );
  assert.equal(await recoverUnsafeState('wizard', 'save_bridge_options', { dataset:{}, isConnected:true }), true,
    'fail-closed recovery did not eventually settle');
  assert.equal(safetyProbe, 3, 'invalid/armed-without-token state did not continue bounded polling');
  assert.equal(safetyReloads, 1, 'recovery refreshed before exact clean+pending=false');
  assert.ok(safetyWarnings.some(message => message.includes('invalid')) && safetyWarnings.some(message => message.includes('armed')),
    'unresolved Safe Apply states were not surfaced as warnings');

  let trafficNow = 1000;
  const trafficState = { previousTraffic:null, previousAt:0 };
  const trafficRate = new Function(
    'state', 'Date',
    `${functionSource('trafficRates')}\nreturn trafficRates;`
  )(trafficState, { now:() => trafficNow });
  trafficRate({ traffic:{ rx_bytes:1000, tx_bytes:2000, counter_signature:'true:lan1:lan2' } }, true);
  trafficNow = 2000;
  let browserRate = trafficRate({ traffic:{ rx_bytes:1100, tx_bytes:2200, counter_signature:'true:lan1:lan2' } }, true);
  assert.equal(browserRate.rx, 100, 'stable traffic signature did not produce a browser delta');
  assert.equal(browserRate.tx, 200, 'stable traffic signature produced the wrong upload delta');
  trafficNow = 3000;
  browserRate = trafficRate({ traffic:{ rx_bytes:50000, tx_bytes:60000, counter_signature:'false:none:lan1,lan2' } }, true);
  assert.equal(browserRate.rx, 0, 'topology signature transition produced a download spike');
  assert.equal(browserRate.tx, 0, 'topology signature transition produced an upload spike');
  trafficNow = 4000;
  browserRate = trafficRate({ traffic:{ rx_bytes:50100, tx_bytes:60200, counter_signature:'false:none:lan1,lan2' } }, true);
  assert.equal(browserRate.rx, 100, 'new traffic signature did not establish a fresh baseline');
  assert.equal(browserRate.tx, 200, 'new traffic signature baseline has the wrong rate');

  const makeFetchWithTimeout = new Function(
    'fetch', 'AbortController', 'AUTH_TIMEOUT_MS',
    `${fetchBody}\nreturn fetchWithTimeout;`
  );
  let requestSignal;
  const abortingFetch = (_url, options) => new Promise((_resolve, reject) => {
    requestSignal = options.signal;
    requestSignal.addEventListener('abort', () => {
      const error = new Error('aborted');
      error.name = 'AbortError';
      reject(error);
    }, { once:true });
  });
  const boundedFetch = makeFetchWithTimeout(abortingFetch, TestAbortController, 1000);
  const upstream = new TestAbortController();
  const pending = boundedFetch('/probe', { signal:upstream.signal }, 1000);
  await Promise.resolve();
  assert.ok(requestSignal && !requestSignal.aborted, 'request did not receive a live composed signal');
  upstream.abort();
  await assert.rejects(pending, error => error && error.name === 'AbortError');
  assert.equal(requestSignal.aborted, true, 'upstream abort did not reach the request');

  const state = { lang:'en', postLock:null };
  let finishBody;
  const response = {
    status:200,
    json:() => new Promise(resolve => { finishBody = resolve; })
  };
  const makeLockedPost = new Function(
    'state', 'fetchWithTimeout',
    `${functionSource('postBusyError')}\n${functionSource('postJsonLocked')}\nreturn postJsonLocked;`
  );
  const lockedPost = makeLockedPost(state, async () => response);
  const button = { disabled:false, isConnected:true };
  const first = lockedPost('/mutate', { body:'x=1' }, 1000, button);
  await Promise.resolve();
  await Promise.resolve();
  assert.ok(state.postLock, 'POST lock released before response body completion');
  assert.equal(button.disabled, true, 'POST owner button was not disabled');
  await assert.rejects(
    lockedPost('/mutate', { body:'x=2' }, 1000),
    error => error && error.code === 'SMARTAP_POST_BUSY'
  );
  finishBody({ ok:true });
  const completed = await first;
  assert.deepEqual(completed.data, { ok:true });
  assert.equal(state.postLock, null, 'POST lock was not released');
  assert.equal(button.disabled, false, 'POST owner button was not restored');

  const failedButton = { disabled:false, isConnected:true };
  const failedPost = makeLockedPost(state, async () => { throw new Error('link-lost'); });
  let failedPostError;
  await assert.rejects(failedPost('/mutate', { body:'x=3' }, 1000, failedButton), error => {
    failedPostError = error;
    return /link-lost/.test(error && error.message);
  });
  assert.equal(failedPostError.smartapPostFailure, true, 'lost POST result was not tagged for recovery');
  assert.equal(postNeedsRecovery(failedPostError), true, 'tagged connection failure did not enter recovery');
  assert.equal(state.postLock, null, 'POST lock leaked after a connection failure');
  assert.equal(failedButton.disabled, false, 'POST owner button stayed disabled after a connection failure');

  const actionToasts = [];
  let actionRecoveryCalls = 0;
  const makeAction = new Function(
    'state', 'loadData', 'speedTest', 'toast', 'tr', 'postJsonLocked', 'ACTION',
    'authHeaders', 'sidQuery', 'dashboardActionTimeoutMs', 'requireLogin', 'event',
    'queueFullRefresh', 'dashboardActionMayReconnect', 'controlPostNeedsRecovery',
    'waitForRouterReachable',
    `${functionSource('action')}\nreturn action;`
  );
  const actionState = { pendingAction:{ name:'reconnect', until:Date.now() + 6000 } };
  let actionPostError = Object.assign(new Error('another change is still running'), { code:'SMARTAP_POST_BUSY' });
  const runAction = makeAction(
    actionState, async () => {}, async () => {}, value => actionToasts.push(value), value => value,
    async () => { throw actionPostError; }, '/cgi-bin/dashaction', () => ({}), () => 'sid=test',
    () => 45000, () => {}, () => {}, () => {},
    name => name === 'reconnect' || /^wifi_radio[01]$/.test(name || ''), postNeedsRecovery,
    async () => { actionRecoveryCalls++; }
  );
  await runAction('reconnect', { disabled:false, isConnected:true });
  assert.equal(actionRecoveryCalls, 0, 'a locally rejected busy action falsely entered reconnect recovery');
  assert.deepEqual(actionToasts, ['another change is still running'], 'busy action did not report its real error');

  actionState.pendingAction = { name:'reconnect', until:Date.now() + 6000 };
  actionPostError = Object.assign(new Error('response lost'), {
    code:'SMARTAP_TIMEOUT', smartapPostFailure:true
  });
  await runAction('reconnect', { disabled:false, isConnected:true });
  assert.equal(actionRecoveryCalls, 1, 'a sent reconnect with a lost response did not enter recovery');

  const deviceToasts = [], deviceEvents = [];
  let deviceQuickOpens = 0, devicePendingRenders = 0, deviceRecoveryCalls = 0;
  let devicePostResult = {
    response:{ status:200 },
    data:{ ok:true, summary:'MAC blocked', rollback_token:'b'.repeat(32), confirmation_ready:true, actions:[] }
  };
  const pendingBox = { dataset:{}, isConnected:true };
  const runDeviceAccess = new Function(
    'CTL', 'postJsonLocked', 'authHeaders', 'sidQuery', 'requireLogin', 'tr',
    'quickSafeApplyBox', 'presentPendingApply', 'toast', 'event', 'queueFullRefresh',
    'controlPostNeedsRecovery', 'recoverControlAction',
    `${functionSource('runDeviceAccessAction')}\nreturn runDeviceAccessAction;`
  )(
    '/cgi-bin/dashctl', async () => {
      if (devicePostResult instanceof Error) throw devicePostResult;
      return devicePostResult;
    }, () => ({}), () => 'sid=test', () => {}, value => value,
    () => { deviceQuickOpens++; return pendingBox; },
    (section, box, data) => {
      devicePendingRenders++;
      return section === 'wizard' && box === pendingBox && /^[0-9a-f]{32}$/.test(data.rollback_token);
    }, value => deviceToasts.push(value), value => deviceEvents.push(value), () => {},
    postNeedsRecovery, async () => { deviceRecoveryCalls++; return true; }
  );
  await runDeviceAccess('aa:bb:cc:dd:ee:ff', 'block_mac', { disabled:false, isConnected:true });
  assert.equal(deviceQuickOpens, 1, 'successful device block did not open Safe Apply');
  assert.equal(devicePendingRenders, 1, 'successful device block did not render Keep/Rollback');
  assert.deepEqual(deviceEvents, ['Block aa:bb:cc:dd:ee:ff'], 'successful block event was not recorded');

  devicePostResult = {
    response:{ status:200 },
    data:{ ok:false, summary:'reload failed', rollback_token:'c'.repeat(32), confirmation_ready:false, actions:[] }
  };
  await runDeviceAccess('aa:bb:cc:dd:ee:ff', 'block_mac', { disabled:false, isConnected:true });
  assert.equal(deviceQuickOpens, 1, 'failed device block exposed an unready rollback token');
  assert.equal(devicePendingRenders, 1, 'failed device block rendered Keep/Rollback');

  devicePostResult = Object.assign(new Error('block response lost'), {
    code:'SMARTAP_TIMEOUT', smartapPostFailure:true
  });
  await runDeviceAccess('aa:bb:cc:dd:ee:ff', 'unblock_mac', { disabled:false, isConnected:true });
  assert.equal(deviceRecoveryCalls, 1, 'lost block/unblock POST did not recover Safe Apply status');

  const bestToasts = [], bestEvents = [];
  let bestShowCalls = 0, bestPendingRenders = 0, bestRefreshes = 0;
  let bestResult = { response:{ status:200 }, data:{ ok:false, summary:'channel reload failed' } };
  const bestBox = { dataset:{}, isConnected:true };
  const runBestChannels = new Function(
    '$', 'startControlProgress', 'postJsonLocked', 'CTL', 'sidQuery', 'controlActionTimeoutMs',
    'requireLogin', 'tr', 'state', 'showSection', 'quickSafeApplyBox', 'presentPendingApply', 'toast', 'event',
    'queueFullRefresh', 'controlPostNeedsRecovery', 'recoverControlAction',
    `${functionSource('applyBestChannels')}\nreturn applyBestChannels;`
  )(
    id => id === 'ctl_wizard' ? bestBox : null, () => () => {}, async () => bestResult,
    '/cgi-bin/dashctl', () => 'sid=test', () => 740000, () => {}, value => value,
    { lang:'en' }, () => { bestShowCalls++; }, () => { bestShowCalls++; return bestBox; }, () => { bestPendingRenders++; return true; },
    value => bestToasts.push(value), value => bestEvents.push(value), () => { bestRefreshes++; },
    postNeedsRecovery, async () => true
  );
  await runBestChannels('11', '36', { disabled:false, isConnected:true });
  assert.equal(bestShowCalls, 0, 'failed best-channel apply opened a success confirmation');
  assert.equal(bestPendingRenders, 0, 'failed best-channel apply rendered Keep/Rollback');
  assert.equal(bestEvents.length, 0, 'failed best-channel apply recorded a success event');
  assert.deepEqual(bestToasts, ['channel reload failed'], 'failed best-channel apply hid its backend result');

  bestResult = {
    response:{ status:200 },
    data:{ ok:true, summary:'channels ready', confirmation_ready:true, rollback_token:'e'.repeat(32) }
  };
  await runBestChannels('11', '36', { disabled:false, isConnected:true });
  assert.equal(bestShowCalls, 1, 'successful best-channel apply did not open Safe Apply');
  assert.equal(bestPendingRenders, 1, 'successful best-channel apply did not render Keep/Rollback');
  assert.deepEqual(bestEvents, ['Best channel applied: 2.4G=11 5G=36'], 'successful best-channel event is missing');
  assert.equal(bestRefreshes, 1, 'successful best-channel apply did not refresh telemetry');

  const reconnectToasts = [];
  const makeReachabilityWait = new Function(
    'state', 'dashboardRecoveryWindowMs', 'RECOVERY_PROBE_TIMEOUT_MS', 'API',
    'fetchWithTimeout', 'authUrl', 'authHeaders', 'requireLogin', 'tr', 'toast', 'queueFullRefresh', 'recoveryPollDelayMs',
    'patchHtml',
    `${functionSource('sleepMs')}\n${functionSource('waitForRouterReachable')}\nreturn waitForRouterReachable;`
  );
  const waitForReachability = makeReachabilityWait(
    { lang:'en' }, () => 100, 50, '/cgi-bin/dashapi2',
    async () => ({ status:200, ok:true, text:async () => '{}' }),
    value => value, () => ({}), () => {}, value => value,
    value => reconnectToasts.push(value), () => {}, recoveryBackoff,
    (button, html) => { button.innerHTML = html; }
  );
  const attrs = new Set();
  const reconnectButton = {
    disabled:false, innerHTML:'<strong>Wi-Fi</strong>', textContent:'Wi-Fi',
    setAttribute:name => attrs.add(name), removeAttribute:name => attrs.delete(name)
  };
  await waitForReachability('wifi_radio0', reconnectButton);
  assert.equal(reconnectButton.disabled, false, 'reconnect flow left the action button disabled');
  assert.equal(reconnectButton.innerHTML, '<strong>Wi-Fi</strong>', 'reconnect flow did not restore button content');
  assert.equal(attrs.has('aria-busy'), false, 'reconnect flow left aria-busy set');
  assert.ok(reconnectToasts.length > 0, 'reconnect flow did not report recovery');

  const navigationState = {
    navigationPending:false, timer:17, dataRefreshTimer:23,
    dataRefreshReason:'manual', activeDataRequests:1, _pollBusy:true
  };
  let navigationCancelCalls = 0;
  const runNavigationQuiesce = new Function(
    'state', 'clearTimeout', 'clearStaleRetry', 'cancelDataRead', 'Date', 'setTimeout',
    `${functionSource('quiesceDataReadsForNavigation')}\nreturn quiesceDataReadsForNavigation;`
  )(
    navigationState, () => {}, () => {}, () => {
      navigationCancelCalls++;
      navigationState.dataRefreshTimer = 0;
      navigationState.dataRefreshReason = '';
      navigationState.activeDataRequests = 0;
      navigationState._pollBusy = false;
    }, Date, setTimeout
  );
  await runNavigationQuiesce();
  assert.equal(navigationCancelCalls, 1, 'LuCI navigation did not abort the replaceable live GET');
  assert.equal(navigationState.navigationPending, true, 'navigation gate reopened before leaving Smart AP');
  assert.equal(navigationState.timer, 0, 'poll timer survived LuCI navigation quiesce');

  let boundedNow = 0;
  const stuckNavigationState = {
    navigationPending:false, timer:1, dataRefreshTimer:1,
    dataRefreshReason:'stuck', activeDataRequests:1, _pollBusy:true
  };
  const boundedNavigationQuiesce = new Function(
    'state', 'clearTimeout', 'clearStaleRetry', 'cancelDataRead', 'Date', 'setTimeout',
    `${functionSource('quiesceDataReadsForNavigation')}\nreturn quiesceDataReadsForNavigation;`
  )(
    stuckNavigationState, () => {}, () => {}, () => {},
    { now:() => boundedNow }, (handler, delay) => { boundedNow += delay; handler(); }
  );
  await boundedNavigationQuiesce();
  assert.equal(boundedNow, 1500, 'navigation drain is not bounded to the short 1.5s deadline');
  assert.equal(stuckNavigationState.navigationPending, true, 'bounded drain timeout incorrectly restarted polling');

  const speedState = { lang:'en', speedTestBusy:false };
  let finishMeasurement;
  let measurementCalls = 0;
  const speedMessages = [];
  const runSpeedTest = new Function(
    'state', 'measureLocalSpeed', 'toast', 'tr', 'fmt', 'bps',
    `${functionSource('beginSpeedTest')}\n${functionSource('finishSpeedTest')}\n${functionSource('speedTest')}\nreturn speedTest;`
  )(
    speedState,
    () => { measurementCalls++; return new Promise((_resolve, reject) => { finishMeasurement = reject; }); },
    message => speedMessages.push(message), value => value,
    value => String(value), value => String(value)
  );
  const speedAttrs = new Set();
  const speedButton = {
    disabled:false, isConnected:true,
    setAttribute:name => speedAttrs.add(name), removeAttribute:name => speedAttrs.delete(name)
  };
  const firstSpeed = runSpeedTest(speedButton);
  await runSpeedTest(speedButton);
  assert.equal(measurementCalls, 1, 'repeated speed-test click started a concurrent measurement');
  assert.equal(speedButton.disabled, true, 'speed-test button was not disabled while measurement was active');
  assert.equal(speedAttrs.has('aria-busy'), true, 'speed-test button did not expose its busy state');
  finishMeasurement(new Error('probe-failed'));
  await firstSpeed;
  assert.equal(speedButton.disabled, false, 'failed speed-test did not restore its button');
  assert.equal(speedAttrs.has('aria-busy'), false, 'failed speed-test leaked aria-busy');
  assert.equal(speedState.speedTestBusy, false, 'failed speed-test leaked its concurrency guard');
  assert.ok(speedMessages.some(message => /probe-failed/.test(message)), 'speed-test rejection was not reported');
}

behaviorTests().then(() => {
  process.stdout.write('stable_dom=pass\n');
  process.stdout.write('dashboard_request_coordination=pass\n');
}).catch(error => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});

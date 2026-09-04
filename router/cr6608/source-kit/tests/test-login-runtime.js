#!/usr/bin/env node

const fs = require("fs");
const http = require("http");
const path = require("path");

const playwrightCandidates = [
  path.resolve(__dirname, "..", "test-tools", "playwright", "node_modules", "playwright-core"),
  path.resolve(__dirname, "..", "..", "tools", "playwright", "node_modules", "playwright-core"),
  path.resolve(__dirname, "..", "..", "..", "tools", "playwright", "node_modules", "playwright-core")
];
if (process.env.HOME)
  playwrightCandidates.push(path.resolve(process.env.HOME, "tools", "playwright", "node_modules", "playwright-core"));
const playwrightCore = playwrightCandidates.find(candidate => fs.existsSync(path.join(candidate, "package.json")));

if (!playwrightCore)
  throw new Error("playwright-core is missing from the CR6608 test tools directory");

const { chromium } = require(playwrightCore);
const webRoot = path.resolve(__dirname, "..", "files", "www");
const legacyLocalStorageKeys = [
  "smartap.availability", "smartap.cardOrder", "smartap.dailyBudgetGb", "smartap.dayBaseRx",
  "smartap.dayBaseTx", "smartap.devNames", "smartap.events", "smartap.histories",
  "smartap.insightCategory", "smartap.interval", "smartap.knownMacs", "smartap.lang",
  "smartap.latHist", "smartap.monthBaseRx", "smartap.monthBaseTx", "smartap.monthBudgetGb",
  "smartap.outageLog", "smartap.theme", "smartap.themePref", "smartap.uiVersion",
  "smartap.weeklyLog", "smartap.yearBaseRx", "smartap.yearBaseTx"
];

let scenario = "success";
const requests = {
  login: 0, loginBodies: [], api: 0, apiModes: [], apiProbes: [], full: 0, slowFull: 0,
  delayedData: 0, dashluci: 0, luciRoute: 0, logout: 0, action: 0, ctl: 0,
  queuedCtl: 0, retryCtl: 0, exhaustedCtl: 0
};
let validationGate = false;
let fullValidationAttempts = 0;
let staleFullResponsesRemaining = 0;
let invalidatedFullResponsesRemaining = 0;
let busyFullResponsesRemaining = 0;
let unavailableFullResponsesRemaining = 0;
let transientProbeResponsesRemaining = 0;
let slowFullResponsesRemaining = 0;
let delayedDataResponsesRemaining = 0;
let queuedControlReadyAt = 0;
let failedControlReadsRemaining = 0;
// Chromium startup/render time varies on the maintained VM. Keep a strict
// six-second cold-page SLA, but give Playwright one additional second to wake
// its polling task so scheduler jitter is not mistaken for an application
// regression. Manual refresh retains its separate four-second limit.
const FIRST_DATA_SLA_MS = 6000;
const FIRST_DATA_WAIT_MS = 7000;
const UI_STATE_WAIT_MS = 8000;

function send(response, status, type, body, extraHeaders) {
  const data = Buffer.from(body);
  response.writeHead(status, Object.assign({
    "Content-Type": type,
    "Content-Length": data.length,
    "Cache-Control": "no-store"
  }, extraHeaders || {}));
  response.end(data);
}

const liteSnapshot = JSON.stringify({
  ok: true,
  lite: true,
  uptime: 120,
  load: [0.01, 0.02, 0.03],
  cpu: { cores: 4, percent: 2 },
  mem: { total: 256000000, free: 128000000, available: 192000000 },
  storage: { total: 100000000, used: 2000000, available: 98000000 },
  traffic: { rx_bytes: 1000, tx_bytes: 500 },
  wifi: [],
  devices: [],
  events: []
});
const fullSnapshot = {
  ok: true,
  snapshot_live: true,
  snapshot_stale: false,
  snapshot_invalidated: false,
  snapshot_age_s: 0,
  collector_degraded: false,
  hostname: "CR6608-TEST",
  model: "Fresh Router Model",
  os: "OpenWrt test",
  uptime: 120,
  load: [0.01, 0.02, 0.03],
  cpu: { cores: 4, percent: 2 },
  mem: { total: 256000000, free: 128000000, available: 192000000 },
  storage: { total: 100000000, used: 2000000, available: 98000000 },
  traffic: { rx_bytes: 1000, tx_bytes: 500 },
  backhaul: { online: false },
  health: { score: 100, reasons: [] },
  services: { uhttpd: true, rpcd: true, netifd: true, dnsmasq: true, odhcpd: true, prplMesh: true },
  interfaces: [],
  wifi: [
    { radio: "radio0", iface: "phy0-ap0", ssid: "Smart ap 2.4G", band: "2.4G", channel: "11", htmode: "HE20", clients: 0, up: true, requested_dbm: 38, driver_accepted_dbm: 38 },
    { radio: "radio1", iface: "phy1-ap0", ssid: "Smart ap 5G", band: "5G", channel: "36", htmode: "HE80", clients: 0, up: true, requested_dbm: 38, driver_accepted_dbm: 38 }
  ],
  devices: []
};

const server = http.createServer((request, response) => {
  const url = new URL(request.url, "http://127.0.0.1");

  if (url.pathname === "/cgi-bin/dashlogin") {
    requests.login++;
    const chunks = [];
    request.on("data", chunk => chunks.push(chunk));
    request.on("end", () => {
      const rawBody = Buffer.concat(chunks).toString("utf8");
      requests.loginBodies.push(rawBody);
      if (scenario === "login_401")
        return send(response, 401, "application/json", '{"ok":false,"message":"invalid username or password"}');
      if (scenario === "login_429")
        return send(response, 429, "application/json", '{"ok":false,"message":"too many attempts"}');
      if (scenario === "login_503")
        return send(response, 503, "application/json", '{"ok":false,"message":"authentication service unavailable"}');
      return send(response, 200, "application/json", '{"ok":true}', {
        "Set-Cookie": "cr6608_sid_http=0123456789abcdef0123456789abcdef; Path=/; HttpOnly; SameSite=Strict"
      });
    });
    return;
  }

  if (url.pathname === "/cgi-bin/dashapi2") {
    requests.api++;
    const apiMode = url.searchParams.get("lite") === "1" ? "lite" : "full";
    const apiProbe = url.searchParams.get("probe") === "1";
    requests.apiModes.push(apiMode);
    requests.apiProbes.push(apiProbe);
    if (scenario === "probe_transient" && apiMode === "lite" && apiProbe && transientProbeResponsesRemaining-- > 0)
      return send(response, 503, "application/json", '{"ok":false,"error":"temporary"}');
    if (validationGate) {
      if (apiMode !== "lite") {
        fullValidationAttempts++;
        return send(response, 503, "application/json", '{"ok":false,"error":"full_validation_forbidden"}');
      }
      validationGate = false;
    }
    if (scenario === "semantic_invalid_session")
      return send(response, 200, "application/json", '{"ok":false,"error":"forbidden"}');
    if (!String(request.headers.cookie || "").includes("cr6608_sid_http=")) {
      if (apiMode === "lite" && apiProbe)
        return send(response, 200, "application/json", '{"ok":false,"authenticated":false,"error":"forbidden"}');
      return send(response, 403, "application/json", '{"ok":false,"error":"forbidden"}');
    }
    if (scenario === "privacy_relogin_delay" && apiMode === "lite" && !apiProbe &&
        delayedDataResponsesRemaining-- > 0) {
      requests.delayedData++;
      setTimeout(() => send(response, 200, "application/json", liteSnapshot), 1500);
      return;
    }
    if (apiMode === "full") {
      requests.full++;
      if (scenario === "unavailable_after_fresh" && unavailableFullResponsesRemaining-- > 0)
        return send(response, 503, "application/json", '{"ok":false,"error":"temporary_unavailable"}');
      if (scenario === "slow_full_force" && slowFullResponsesRemaining-- > 0) {
        requests.slowFull++;
        setTimeout(() => send(response, 200, "application/json", JSON.stringify(fullSnapshot)), 1200);
        return;
      }
      if (scenario === "busy_snapshot" && busyFullResponsesRemaining-- > 0)
        return send(response, 200, "application/json", '{"ok":false,"error":"busy"}');
      if ((scenario === "stale_refresh" || scenario === "stale_auto_recovery") && staleFullResponsesRemaining-- > 0)
        return send(response, 200, "application/json", JSON.stringify(Object.assign({}, fullSnapshot, {
          model: "Stale Router Model", snapshot_live: false, snapshot_stale: true, snapshot_age_s: 3600
        })));
      if (scenario === "invalidated_refresh" && invalidatedFullResponsesRemaining-- > 0)
        return send(response, 200, "application/json", JSON.stringify(Object.assign({}, fullSnapshot, {
          model: "Invalidated Router Model", snapshot_stale: false,
          snapshot_live: false, snapshot_invalidated: true, snapshot_age_s: 0
        })));
      if (scenario === "privacy_seed")
        return send(response, 200, "application/json", JSON.stringify(Object.assign({}, fullSnapshot, {
          hostname: "PRIVATE-PREVIOUS-SESSION",
          model: "Private Previous Session Model",
          events: ["PRIVATE_PREVIOUS_SESSION_API_EVENT"]
        })));
      return send(response, 200, "application/json", JSON.stringify(fullSnapshot));
    }
    return send(response, 200, "application/json", liteSnapshot);
  }

  if (url.pathname === "/cgi-bin/dashluci") {
    requests.dashluci++;
    if (request.method !== "POST")
      return send(response, 405, "application/json", '{"ok":false,"error":"method"}');
    if (!String(request.headers.cookie || "").includes("cr6608_sid_http="))
      return send(response, 403, "application/json", '{"ok":false,"error":"session_missing"}');
    return send(response, 200, "application/json",
      '{"ok":true,"target":"/cgi-bin/luci/admin/network/wireless"}', {
        "Set-Cookie": "sysauth_http=abcdef0123456789abcdef0123456789; Path=/cgi-bin/luci; HttpOnly; SameSite=Strict"
      });
  }

  if (url.pathname === "/cgi-bin/luci" || url.pathname.startsWith("/cgi-bin/luci/")) {
    requests.luciRoute++;
    if (!String(request.headers.cookie || "").includes("sysauth_http="))
      return send(response, 302, "text/plain", "", { Location: "/" });
    return send(response, 200, "text/html; charset=utf-8",
      '<!doctype html><title>OpenWrt Wireless</title><link rel="icon" href="/luci-static/argon/favicon.ico"><main id="luci-wireless-settings">Wireless settings</main>');
  }

  if (url.pathname === "/cgi-bin/dashlogout") {
    requests.logout++;
    if (scenario === "logout_503")
      return send(response, 503, "application/json", '{"ok":false,"error":"revocation_failed"}', {
        "Retry-After": "1",
        "Set-Cookie": [
          "cr6608_sid_http=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict",
          "sysauth_http=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict"
        ]
      });
    return send(response, 200, "application/json", '{"ok":true}');
  }

  if (url.pathname === "/cgi-bin/dashctl") {
    requests.ctl++;
    const controlSection = url.searchParams.get("section");
    if (scenario === "control_read_retry_exhausted" && request.method === "GET" && controlSection === "wizard") {
      requests.exhaustedCtl++;
      return send(response, 200, "application/json", '{"ok":false,"error":"busy"}');
    }
    if (scenario === "control_read_retry" && request.method === "GET" && controlSection === "wizard") {
      requests.retryCtl++;
      if (failedControlReadsRemaining-- > 0)
        return send(response, 200, "application/json", '{"ok":false,"error":"busy"}');
    }
    if (scenario === "queued_control_navigation" && request.method === "GET" &&
        (controlSection === "wizard" || controlSection === "isolation")) {
      requests.queuedCtl++;
      // Model a single-core router where aborting the browser request does not
      // stop its already-running CGI. Each extra navigation GET joins the same
      // backend work queue and delays the final panel users actually want.
      const now = Date.now();
      queuedControlReadyAt = Math.max(now, queuedControlReadyAt) + 450;
      const delay = Math.max(0, queuedControlReadyAt - now);
      return setTimeout(() => send(response, 200, "application/json",
        '{"ok":true,"cards":[],"form":[],"actions":[]}'), delay);
    }
    if (request.method === "GET" && url.searchParams.get("section") === "wizard") {
      return send(response, 200, "application/json", JSON.stringify({
        ok: true,
        cards: [],
        form: [
          { name: "ssid", type: "text", value: "Original SSID", label: "SSID", group: "device" },
          { name: "security", type: "select", value: "open", options: "open:Open,wpa2:WPA2", label: "Security", group: "security" },
          { name: "txpower_radio0", type: "number", value: "38", options: "1:38:1", label: "TX power", group: "advanced" }
        ],
        actions: []
      }));
    }
    if (request.method === "GET" && url.searchParams.get("section") === "isolation") {
      return send(response, 200, "application/json", JSON.stringify({
        ok: true,
        cards: [],
        form: [
          { name: "guard_enabled", type: "select", value: "1", options: "0:Off,1:On", label: "Protection", group: "guard" },
          { name: "wifi_isolate", type: "select", value: "0", options: "0:Off,1:On", label: "Wi-Fi isolation", group: "wifi" }
        ],
        actions: []
      }));
    }
    return send(response, 200, "application/json", '{"ok":true,"cards":[],"form":[],"actions":[]}');
  }

  if (url.pathname === "/cgi-bin/dashaction") {
    requests.action++;
    return send(response, 200, "application/json", '{"ok":true,"message":"applied"}');
  }

  const relative = url.pathname === "/" ? "index.html" : url.pathname.replace(/^\/+/, "");
  const file = path.resolve(webRoot, relative);
  if (!file.startsWith(webRoot + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile())
    return send(response, 404, "text/plain", "not found");

  const extension = path.extname(file);
  const type = extension === ".html" ? "text/html; charset=utf-8"
    : extension === ".js" ? "application/javascript; charset=utf-8"
      : extension === ".css" ? "text/css; charset=utf-8"
        : "application/octet-stream";
  send(response, 200, type, fs.readFileSync(file));
});

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function requestStatus(pathname) {
  return new Promise((resolve, reject) => {
    const request = http.get({ host: "127.0.0.1", port: server.address().port, path: pathname }, response => {
      response.resume();
      response.on("end", () => resolve(response.statusCode));
    });
    request.on("error", reject);
  });
}

async function waitForCondition(predicate, timeoutMs, message) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert(predicate(), message);
}

async function waitForFullRequestsToSettle(idleMs = 400, timeoutMs = 3500) {
  const deadline = Date.now() + timeoutMs;
  let lastCount = requests.full;
  let idleSince = Date.now();
  while (Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 25));
    if (requests.full !== lastCount) {
      lastCount = requests.full;
      idleSince = Date.now();
    } else if (Date.now() - idleSince >= idleMs) {
      return;
    }
  }
  assert(false, `full API requests did not settle before the next isolated scenario (count=${requests.full})`);
}

async function newPage(browser, staleSession, validCookie, storageSeed, sessionSeed) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const runtimeErrors = [];
  const resourceErrors = [];
  page.on("pageerror", error => runtimeErrors.push(String(error)));
  page.on("console", message => {
    if (message.type() !== "error") return;
    if (/^Failed to load resource:/.test(message.text()))
      resourceErrors.push({ text: message.text(), url: message.location().url || "" });
    else
      runtimeErrors.push(message.text());
  });
  await page.addInitScript(options => {
    localStorage.clear();
    sessionStorage.clear();
    Object.keys(options.storageSeed || {}).forEach(key => {
      const value = options.storageSeed[key];
      if (value === null) localStorage.removeItem(key);
      else localStorage.setItem(key, String(value));
    });
    Object.keys(options.sessionSeed || {}).forEach(key => {
      const value = options.sessionSeed[key];
      if (value === null) sessionStorage.removeItem(key);
      else sessionStorage.setItem(key, String(value));
    });
    if (options.staleSession) sessionStorage.setItem("smartap.session", "cookie");
  }, { staleSession: !!staleSession, storageSeed: storageSeed || {}, sessionSeed: sessionSeed || {} });
  if (validCookie) {
    await page.context().addCookies([{
      name: "cr6608_sid_http",
      value: "0123456789abcdef0123456789abcdef",
      url: `http://127.0.0.1:${server.address().port}/`,
      httpOnly: true,
      sameSite: "Strict"
    }]);
  }
  const navigationStarted = Date.now();
  await page.goto(`http://127.0.0.1:${server.address().port}/`, { waitUntil: "domcontentloaded" });
  await page.evaluate(() => document.querySelector("#loginLangEn").click());
  return { page, runtimeErrors, resourceErrors, navigationStarted };
}

async function submitLogin(page, injectedUsername = "root", injectedPassword = "admin") {
  // The visible field must accept both supported names.  The CGI maps admin to
  // the one real root account and remains the authoritative allowlist.
  await page.fill("#loginUser", injectedUsername);
  await page.fill("#loginPass", injectedPassword);
  await page.click("#loginBtn");
}

(async () => {
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const launchOptions = { headless: true };
  if (process.env.CR6608_BROWSER_PATH)
    launchOptions.executablePath = process.env.CR6608_BROWSER_PATH;
  else if (process.platform === "win32")
    launchOptions.executablePath = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";

  const browser = await chromium.launch(launchOptions);
  try {
    scenario = "success";
    assert(await requestStatus("/cgi-bin/dashapi2?lite=1") === 403,
      "ordinary unauthenticated API request did not remain forbidden");
    assert(await requestStatus("/cgi-bin/dashapi2?lite=1&probe=1") === 200,
      "unauthenticated session probe did not use a non-error response");
    assert(await requestStatus("/cgi-bin/luci/admin/network/wireless") === 302,
      "unauthenticated LuCI request did not return to Smart AP");
    {
      const localSeed = legacyLocalStorageKeys.reduce((seed, key) => {
        seed[key] = "legacy";
        return seed;
      }, {
        "unrelated.app": "keep-local",
        "smartap.notOwnedByLegacyUI": "keep-namespaced",
        "smartap.session": "keep-wrong-store"
      });
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, false, localSeed, {
        "smartap.session": "legacy-session",
        "unrelated.session": "keep-session",
        "smartap.theme": "keep-wrong-store"
      });
      const migrationState = await page.evaluate(keys => ({
        retiredLocal: keys.map(key => localStorage.getItem(key)),
        retiredSession: sessionStorage.getItem("smartap.session"),
        unrelatedLocal: localStorage.getItem("unrelated.app"),
        unrelatedNamespaced: localStorage.getItem("smartap.notOwnedByLegacyUI"),
        wrongStoreLocal: localStorage.getItem("smartap.session"),
        unrelatedSession: sessionStorage.getItem("unrelated.session"),
        wrongStoreSession: sessionStorage.getItem("smartap.theme"),
        localLength: localStorage.length,
        sessionLength: sessionStorage.length
      }), legacyLocalStorageKeys);
      assert(migrationState.retiredLocal.every(value => value === null),
        `zero-retention migration left legacy local keys: ${JSON.stringify(migrationState)}`);
      assert(migrationState.retiredSession === null,
        "zero-retention migration left the legacy Smart AP session key");
      assert(migrationState.unrelatedLocal === "keep-local" &&
        migrationState.unrelatedNamespaced === "keep-namespaced" &&
        migrationState.wrongStoreLocal === "keep-wrong-store" &&
        migrationState.unrelatedSession === "keep-session" &&
        migrationState.wrongStoreSession === "keep-wrong-store" &&
        migrationState.localLength === 3 && migrationState.sessionLength === 2,
        `zero-retention migration removed a non-owned key: ${JSON.stringify(migrationState)}`);
      assert(runtimeErrors.length === 0,
        `zero-retention migration raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `zero-retention migration raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }
    {
      const apiBefore = requests.apiModes.length;
      const fullValidationBefore = fullValidationAttempts;
      validationGate = true;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, false);
      await page.waitForTimeout(500);
      assert(await page.locator("#loginScreen").isVisible(), "fresh browser did not remain on login");
      assert(requests.apiModes[apiBefore] === "lite", "fresh browser session probe was not lite");
      assert(requests.apiProbes[apiBefore] === true, "fresh browser did not use the non-error session probe");
      assert(validationGate === false, "fresh browser did not complete the validation gate");
      assert(fullValidationAttempts === fullValidationBefore,
        "fresh browser attempted the full collector during validation");
      assert(runtimeErrors.length === 0, `fresh browser raised runtime errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `fresh browser raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    {
      const loginBefore = requests.login;
      const apiBefore = requests.apiModes.length;
      const fullValidationBefore = fullValidationAttempts;
      validationGate = true;
      const { page, runtimeErrors } = await newPage(browser, false, true);
      await page.waitForSelector("#appShell:not([hidden])");
      assert(requests.login === loginBefore, "valid HttpOnly cookie forced a new password login");
      assert(requests.apiModes[apiBefore] === "lite",
        `cookie bootstrap used ${requests.apiModes[apiBefore] || "no"} API collector for session validation`);
      assert(requests.apiProbes[apiBefore] === true, "cookie bootstrap did not use the session probe");
      assert(validationGate === false, "cookie bootstrap did not complete the lite validation gate");
      assert(fullValidationAttempts === fullValidationBefore,
        "cookie bootstrap attempted the full hardware collector during session validation");
      assert((await page.evaluate(() => sessionStorage.length)) === 0,
        "valid cookie bootstrap wrote browser session storage");
      assert(runtimeErrors.length === 0, `cookie bootstrap raised browser errors: ${runtimeErrors.join("; ")}`);
      await page.close();
    }

    scenario = "probe_transient";
    {
      transientProbeResponsesRemaining = 1;
      const loginBefore = requests.login;
      const probeBefore = requests.apiProbes.filter(Boolean).length;
      const fullValidationBefore = fullValidationAttempts;
      validationGate = true;
      const { page, runtimeErrors } = await newPage(browser, true, true);
      await page.waitForSelector("#appShell:not([hidden])", { timeout: UI_STATE_WAIT_MS });
      assert(requests.login === loginBefore, "transient session-probe failure requested the password again");
      assert(requests.apiProbes.filter(Boolean).length - probeBefore >= 2,
        "transient session-probe failure was not retried");
      assert(fullValidationAttempts === fullValidationBefore,
        "transient session validation started the full collector before authentication succeeded");
      assert((await page.evaluate(() => sessionStorage.getItem("smartap.session"))) === null,
        "zero-retention migration did not purge the retired session key");
      assert(runtimeErrors.length === 0, `transient probe retry raised browser errors: ${runtimeErrors.join("; ")}`);
      await page.close();
    }

    scenario = "probe_transient";
    {
      transientProbeResponsesRemaining = 10;
      const fullValidationBefore = fullValidationAttempts;
      validationGate = true;
      const { page, runtimeErrors } = await newPage(browser, true, true);
      await page.waitForFunction(() => {
        const button = document.querySelector("#loginBtn");
        const screen = document.querySelector("#loginScreen");
        return button && !button.disabled && screen && !screen.hidden;
      }, null, { timeout: UI_STATE_WAIT_MS });
      assert((await page.evaluate(() => sessionStorage.getItem("smartap.session"))) === null,
        "persistent probe flow retained the retired session key");
      assert(fullValidationAttempts === fullValidationBefore,
        "persistent session-probe failure invoked the full hardware collector");
      await submitLogin(page);
      await page.waitForSelector("#appShell:not([hidden])");
      assert(runtimeErrors.length === 0,
        `persistent probe recovery raised browser errors: ${runtimeErrors.join("; ")}`);
      await page.close();
    }

    scenario = "semantic_invalid_session";
    {
      const apiBefore = requests.apiModes.length;
      const fullValidationBefore = fullValidationAttempts;
      validationGate = true;
      const { page, runtimeErrors } = await newPage(browser, true);
      await page.waitForTimeout(500);
      assert(requests.api > 0, "stale session was not validated through dashapi2");
      assert(requests.apiModes[apiBefore] === "lite",
        `stale-session validation used ${requests.apiModes[apiBefore] || "no"} API collector`);
      assert(validationGate === false, "stale session did not complete the lite validation gate");
      assert(fullValidationAttempts === fullValidationBefore,
        "stale session attempted the full hardware collector during validation");
      assert(await page.locator("#loginScreen").isVisible(), "{ok:false} session response opened the dashboard");
      assert(!(await page.locator("#appShell").isVisible()), "invalid semantic session left the app shell visible");
      assert((await page.evaluate(() => sessionStorage.getItem("smartap.session"))) === null,
        "invalid semantic session flow retained the retired session key");
      const staleMessage = await page.locator("#loginMsg").innerText();
      assert(!staleMessage.includes("Incorrect password"),
        `stale session falsely blamed the password: ${staleMessage}`);
      assert(runtimeErrors.length === 0, `stale-session flow raised browser errors: ${runtimeErrors.join("; ")}`);
      await page.close();
    }

    for (const item of [
      ["login_401", "use root or admin", "service did not respond"],
      ["login_429", "Too many attempts", "service did not respond"],
      ["login_503", "sign-in service did not respond", "Login failed"]
    ]) {
      scenario = item[0];
      const { page, runtimeErrors } = await newPage(browser, false);
      await submitLogin(page);
      await page.waitForFunction(() => !document.querySelector("#loginBtn").disabled);
      const message = await page.locator("#loginMsg").innerText();
      assert(message.includes(item[1]), `${item[0]} displayed the wrong login message: ${message}`);
      assert(!message.includes(item[2]), `${item[0]} displayed a misleading login message: ${message}`);
      assert(await page.locator("#loginScreen").isVisible(), `${item[0]} hid the login screen`);
      if (item[0] === "login_401")
        assert((await page.locator("#loginPass").inputValue()) === "", "rejected autofill password was not cleared");
      assert(runtimeErrors.length === 0, `${item[0]} raised browser errors: ${runtimeErrors.join("; ")}`);
      await page.close();
    }

    scenario = "success";
    {
      const logoutBefore = requests.logout;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForSelector("#appShell:not([hidden])", { timeout: UI_STATE_WAIT_MS });
      scenario = "logout_503";
      await page.locator("#logoutBtn").click();
      await page.waitForFunction(() => {
        const login = document.querySelector("#loginScreen");
        return login && !login.hidden;
      }, null, { timeout: 3000 });
      await page.waitForTimeout(1500);
      assert(requests.logout === logoutBefore + 1,
        "503 logout retried without the cleared HttpOnly SID and accepted a cookie-less response");
      const remainingCookies = await page.context().cookies();
      assert(!remainingCookies.some(cookie => cookie.name === "cr6608_sid_http" || cookie.name === "sysauth_http"),
        `503 logout did not clear browser auth cookies: ${JSON.stringify(remainingCookies)}`);
      assert(await page.locator("#loginScreen").isVisible(),
        "503 logout did not converge to the local signed-out screen");
      assert(runtimeErrors.length === 0, `503 logout raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length <= 1 && resourceErrors.every(error => /dashlogout/.test(error.url)),
        `503 logout raised unrelated HTTP errors: ${JSON.stringify(resourceErrors)}`);
      scenario = "success";
      await page.close();
    }

    scenario = "success";
    {
      const dashluciBefore = requests.dashluci;
      const luciRouteBefore = requests.luciRoute;
      const loginBodyBefore = requests.loginBodies.length;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false);
      assert(await page.locator("#loginUser").getAttribute("readonly") === null,
        "username field is unexpectedly readonly");
      assert((await page.locator("#loginPassToggle").count()) === 0,
        "removed password visibility control is still rendered");
      assert((await page.locator("#loginPass").getAttribute("type")) === "password",
        "password field is not permanently masked");
      assert((await page.locator("#loginForm").getAttribute("autocomplete")) === "off",
        "login form still permits browser credential retention");
      assert((await page.locator("#loginUser").getAttribute("autocomplete")) === "off",
        "username field still permits stale autofill");
      assert((await page.locator("#loginPass").getAttribute("autocomplete")) === "new-password",
        "password field still requests a saved current password");
      await submitLogin(page, "admin", "admin\r\n\u200f");
      await page.waitForSelector("#appShell:not([hidden])");
      await page.waitForTimeout(500);
      assert(requests.dashluci === dashluciBefore,
        "ordinary Smart AP login must not wait for the optional LuCI bridge");
      assert((await page.locator("#openWrtBtn").count()) === 1,
        "Smart AP does not render the OpenWrt settings button");
      assert((await page.locator('a[href^="/cgi-bin/luci"], form[action^="/cgi-bin/luci"]').count()) === 0,
        "Smart AP exposes an unauthenticated static LuCI link");
      assert(await page.locator("#appShell").isVisible(), "successful login did not open Smart AP");
      assert(!(await page.locator("#loginScreen").isVisible()), "successful login returned to the login screen");
      assert((await page.locator("#loginPass").inputValue()) === "",
        "successful login retained the one-use credential in the document");
      assert((await page.evaluate(() => sessionStorage.length)) === 0,
        "successful Smart AP login wrote browser session storage");
      const submittedLogin = JSON.parse(requests.loginBodies[loginBodyBefore]);
      assert(submittedLogin.username === "admin",
        `visible admin alias was not submitted: ${submittedLogin.username}`);
      assert(submittedLogin.password === "admin",
        `mobile newline/bidi controls were not removed from the submitted password: ${JSON.stringify(submittedLogin.password)}`);

      await page.click("#openWrtBtn");
      await page.waitForSelector("#luci-wireless-settings");
      assert(new URL(page.url()).pathname === "/cgi-bin/luci/admin/network/wireless",
        `secure OpenWrt handoff reached the wrong path: ${page.url()}`);
      assert(requests.dashluci === dashluciBefore + 1,
        "OpenWrt button did not create its LuCI session through dashluci");
      assert(requests.luciRoute === luciRouteBefore + 1,
        "OpenWrt button did not reach the LuCI wireless route");
      assert(runtimeErrors.length === 0, `Smart AP -> LuCI flow raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `Smart AP -> LuCI flow raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "privacy_seed";
    {
      const logoutBefore = requests.logout;
      const actionBefore = requests.action;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Private Previous Session Model"), null,
        { timeout: UI_STATE_WAIT_MS });
      await page.locator('[data-section="actions"]').click();
      await page.locator('[data-action="wifi_radio0"]').click();
      await page.locator('[data-action="wifi_radio0"]').click();
      await waitForCondition(() => requests.action > actionBefore, 3000,
        "privacy-boundary setup action did not reach dashaction");
      await page.waitForFunction(() => document.body.innerText.includes("wifi_radio0: applied"), null,
        { timeout: UI_STATE_WAIT_MS });
      assert((await page.locator("#actions").textContent()).includes("PRIVATE_PREVIOUS_SESSION_API_EVENT"),
        "privacy-boundary setup did not render prior-session API telemetry");

      const searchBoundarySetup = await page.evaluate(() => {
        const search = document.querySelector("#navSearch");
        const original = search;
        const english = { label:search.getAttribute("aria-label"), placeholder:search.placeholder };
        document.querySelector("#langAr").click();
        const arabic = { label:search.getAttribute("aria-label"), placeholder:search.placeholder };
        document.querySelector("#langEn").click();
        const restored = { label:search.getAttribute("aria-label"), placeholder:search.placeholder };
        search.value = "__no_matching_section__";
        search.dispatchEvent(new Event("input", { bubbles:true }));
        return {
          sameNode:original === document.querySelector("#navSearch"), english, arabic, restored,
          hiddenButtons:Array.from(document.querySelectorAll(".nav button[data-section]"))
            .filter(button => button.style.display === "none").length
        };
      });
      assert(searchBoundarySetup.sameNode &&
        searchBoundarySetup.english.label === "Quick search in dashboard sections" &&
        searchBoundarySetup.english.placeholder === "Quick search…" &&
        searchBoundarySetup.arabic.label === "بحث سريع في أقسام اللوحة" &&
        searchBoundarySetup.arabic.placeholder === "بحث سريع…" &&
        searchBoundarySetup.restored.label === searchBoundarySetup.english.label &&
        searchBoundarySetup.restored.placeholder === searchBoundarySetup.english.placeholder,
      `navigation search did not remain language-aware on the same node: ${JSON.stringify(searchBoundarySetup)}`);
      assert(searchBoundarySetup.hiddenButtons === 9,
        `navigation filter setup did not hide all nine destinations: ${JSON.stringify(searchBoundarySetup)}`);

      await page.locator("#logoutBtn").click();
      await page.waitForFunction(() => {
        const login = document.querySelector("#loginScreen");
        return login && !login.hidden;
      }, null, { timeout: 3000 });
      assert(requests.logout === logoutBefore + 1, "privacy-boundary logout did not reach dashlogout");

      scenario = "privacy_relogin_delay";
      delayedDataResponsesRemaining = 1;
      const delayedBefore = requests.delayedData;
      await submitLogin(page, "admin");
      await waitForCondition(() => requests.delayedData > delayedBefore, 3000,
        "re-login did not enter the delayed first-snapshot window");
      await page.waitForFunction(() => {
        const app = document.querySelector("#appShell");
        return app && !app.hidden;
      }, null, { timeout: 3000 });
      const privacyBoundary = await page.evaluate(() => {
        const sectionIds = ["overview", "network", "devices", "wifi", "insights", "system", "quick", "isolation", "actions"];
        return {
          lastApi: window.__lastApi,
          appText: (document.querySelector("#appShell") || {}).textContent || "",
          kpiHtml: (document.querySelector("#kpiBar") || {}).innerHTML || "",
          sectionHtml: sectionIds.map(id => (document.getElementById(id) || {}).innerHTML || ""),
          warning: (document.querySelector("#snapshotWarning") || {}).textContent || "",
          search: (document.querySelector("#navSearch") || {}).value || "",
          hiddenNavButtons:Array.from(document.querySelectorAll(".nav button[data-section]"))
            .filter(button => button.style.display === "none").length
        };
      });
      assert(privacyBoundary.lastApi === null,
        `prior state.latest remained exposed before the new snapshot: ${JSON.stringify(privacyBoundary.lastApi)}`);
      assert(!/Private Previous Session Model|PRIVATE_PREVIOUS_SESSION|wifi_radio0: applied/.test(privacyBoundary.appText),
        "prior-session snapshot or event remained in the dashboard DOM during re-login");
      assert(privacyBoundary.kpiHtml === "" && privacyBoundary.sectionHtml.every(html => html === "") && privacyBoundary.warning === "",
        `prior-session live DOM was not cleared: ${JSON.stringify(privacyBoundary)}`);
      assert(privacyBoundary.search === "" && privacyBoundary.hiddenNavButtons === 0,
        `logout/re-login retained the navigation query or hidden destinations: ${JSON.stringify(privacyBoundary)}`);

      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null,
        { timeout: UI_STATE_WAIT_MS });
      await page.locator('[data-section="actions"]').click();
      const newSessionActions = await page.locator("#actions").textContent();
      assert(!/PRIVATE_PREVIOUS_SESSION_API_EVENT|wifi_radio0: applied/.test(newSessionActions),
        "prior-session telemetry reappeared after the new session received fresh data");
      assert(runtimeErrors.length === 0, `logout/re-login privacy test raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `logout/re-login privacy test raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      scenario = "success";
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "success";
    {
      const { page, runtimeErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null,
        { timeout: UI_STATE_WAIT_MS });
      await page.locator('[data-section="actions"]').click();
      await page.waitForSelector('#actions [data-action="refresh"]');
      scenario = "unavailable_after_fresh";
      unavailableFullResponsesRemaining = 1;
      await page.locator("#refreshBtn").click();
      await page.waitForFunction(() => window.__lastApi === null &&
        document.querySelector("#snapshotWarning") && !document.querySelector("#snapshotWarning").hidden,
        null, { timeout: 4000 });
      const unavailable = await page.evaluate(() => ({
        lastApi: window.__lastApi,
        status: (document.querySelector("#connectionState") || {}).textContent || "",
        warningVisible: !!document.querySelector("#snapshotWarning") && !document.querySelector("#snapshotWarning").hidden,
        warning: (document.querySelector("#snapshotWarning") || {}).textContent || "",
        actionText: (document.querySelector("#actions") || {}).textContent || "",
        actionButtons: document.querySelectorAll("#actions [data-action]").length,
        body: document.body.innerText
      }));
      assert(unavailable.lastApi === null && !unavailable.body.includes("Fresh Router Model"),
        `failed live read left the previous snapshot visible: ${JSON.stringify(unavailable)}`);
      assert(unavailable.status === "Live data unavailable",
        `failed live read remained presented as current/online: ${JSON.stringify(unavailable)}`);
      assert(unavailable.warningVisible && /Previous values were removed/.test(unavailable.warning),
        `failed live read did not expose a persistent warning: ${JSON.stringify(unavailable)}`);
      assert(unavailable.actionButtons === 0 && /no previous snapshot is displayed/i.test(unavailable.actionText),
        `failed live read left stale actions available: ${JSON.stringify(unavailable)}`);
      assert(runtimeErrors.length === 0,
        `unavailable-after-fresh test raised runtime errors: ${runtimeErrors.join("; ")}`);
      scenario = "success";
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "stale_refresh";
    {
      staleFullResponsesRemaining = 1;
      const { page, runtimeErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => window.__lastApi &&
        window.__lastApi.model === "Fresh Router Model" &&
        window.__lastApi._liveLite === false,
        null, { timeout: UI_STATE_WAIT_MS });
      assert(!(await page.locator("body").innerText()).includes("Stale Router Model"),
        "stale full response was rendered before recovery");
      scenario = "unavailable_after_fresh";
      // Hold the transport-unavailable state across the first automatic retry.
      // Otherwise a healthy retry can legitimately render a new Fresh snapshot
      // between two separate Playwright reads and look like retained old data.
      unavailableFullResponsesRemaining = 2;
      await page.locator("#refreshBtn").click();
      const unavailableHandle = await page.waitForFunction(() => {
        const body = document.body.innerText;
        const status = (document.querySelector("#connectionState") || {}).textContent || "";
        const warning = document.querySelector("#snapshotWarning");
        if (window.__lastApi !== null ||
            document.body.dataset.liveState !== "unavailable" ||
            status !== "Live data unavailable" ||
            !warning || warning.hidden ||
            /Stale Router Model|Fresh Router Model/.test(body)) return false;
        return { body, status, warning: warning.textContent || "" };
      }, null, { timeout: 4000 });
      const unavailableState = await unavailableHandle.jsonValue();
      await unavailableHandle.dispose();
      assert(!/Stale Router Model|Fresh Router Model/.test(unavailableState.body),
        `transport failure preserved an earlier full snapshot in the interface: ${JSON.stringify(unavailableState)}`);
      scenario = "success";
      unavailableFullResponsesRemaining = 0;
      await page.waitForFunction(() => window.__lastApi &&
        window.__lastApi.model === "Fresh Router Model" &&
        window.__lastApi._liveLite === false,
        null, { timeout: UI_STATE_WAIT_MS });
      assert(runtimeErrors.length === 0,
        `stale-to-unavailable test raised runtime errors: ${runtimeErrors.join("; ")}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "stale_refresh";
    {
      staleFullResponsesRemaining = 7;
      const fullBefore = requests.full;
      const { page, runtimeErrors, resourceErrors, navigationStarted } = await newPage(browser, false, true);
      await page.waitForFunction(() => window.__lastApi === null &&
        document.body.innerText.includes("no previous snapshot is displayed"), null, { timeout: FIRST_DATA_WAIT_MS });
      const unavailableVisibleMs = Date.now() - navigationStarted;
      // Force six more full reads so regression coverage crosses the old fifth
      // response bug without making the suite sleep through production backoff.
      // A manual refresh disables its own button until the request settles.
      // Wait for that legitimate state transition rather than racing a one
      // second locator deadline on a busy CI/Ubuntu host. These rapid stress
      // clicks bypass Playwright's animation-stability heuristic only; the
      // ordinary unforced refresh below remains the user-actionability gate.
      const staleLoopDeadline = Date.now() + 12000;
      while (requests.full - fullBefore < 7) {
        assert(Date.now() < staleLoopDeadline,
          `stale refresh loop timed out after ${requests.full - fullBefore} full responses`);
        await page.locator("#refreshBtn:not([disabled])").click({ timeout: 3000, force: true });
        await page.waitForTimeout(180);
      }
      const staleState = await page.evaluate(() => ({
        lastApi: window.__lastApi,
        status: (document.querySelector("#connectionState") && document.querySelector("#connectionState").textContent) || "",
        warningVisible: !!document.querySelector("#snapshotWarning") && !document.querySelector("#snapshotWarning").hidden,
        body: document.body.innerText
      }));
      assert(staleState.lastApi === null && !staleState.body.includes("Stale Router Model"),
        "seventh stale response was retained or rendered");
      assert(staleState.status === "Live data unavailable",
        `stale status was not failed closed: ${JSON.stringify(staleState)}`);
      assert(staleState.warningVisible, "live-only unavailable warning was hidden");
      const manualRefreshStarted = Date.now();
      await page.locator("#refreshBtn").click();
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: 4000 });
      const manualRefreshMs = Date.now() - manualRefreshStarted;
      assert(unavailableVisibleMs < FIRST_DATA_SLA_MS, `live-only failure state missed first-data SLA: ${unavailableVisibleMs}ms`);
      assert(manualRefreshMs < 4000, `manual stale refresh was not prompt: ${manualRefreshMs}ms`);
      assert(requests.full - fullBefore >= 8, "live-only path did not remain retryable after seven rejected snapshots");
      assert(runtimeErrors.length === 0, `stale refresh raised runtime errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0, `stale refresh raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "queued_control_navigation";
    queuedControlReadyAt = 0;
    {
      const queuedBefore = requests.queuedCtl;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null,
        { timeout: UI_STATE_WAIT_MS });
      for (let pass = 0; pass < 3; pass++) {
        // Force only removes Playwright's host-scheduler/actionability delay;
        // the explicit 45-ms dwell remains the production navigation stress.
        await page.locator('[data-section="quick"]').click({ force:true });
        await page.waitForTimeout(45);
        await page.locator('[data-section="isolation"]').click({ force:true });
        await page.waitForTimeout(45);
        await page.locator('[data-section="overview"]').click({ force:true });
        await page.waitForTimeout(45);
      }
      await page.locator('[data-section="quick"]').click({ force:true });
      await page.waitForSelector('#ctl_wizard .wizard-tabs', { timeout: 2500 });
      await page.waitForTimeout(1250);
      assert(requests.queuedCtl - queuedBefore === 1,
        `rapid navigation amplified control CGI reads: ${requests.queuedCtl - queuedBefore}`);
      assert(runtimeErrors.length === 0,
        `queued control navigation raised runtime errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `queued control navigation raised HTTP errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "control_read_retry";
    failedControlReadsRemaining = 1;
    {
      const retryBefore = requests.retryCtl;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null,
        { timeout: UI_STATE_WAIT_MS });
      await page.locator('[data-section="quick"]').click();
      await page.waitForSelector('#ctl_wizard .wizard-tabs', { timeout: 3500 });
      await page.waitForTimeout(1250);
      assert(requests.retryCtl - retryBefore === 2,
        `passive control retry was missing or unbounded: ${requests.retryCtl - retryBefore}`);
      assert(runtimeErrors.length === 0,
        `passive control retry raised runtime errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `passive control retry raised HTTP errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "control_read_retry_exhausted";
    {
      const exhaustedBefore = requests.exhaustedCtl;
      const { page, runtimeErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null,
        { timeout: UI_STATE_WAIT_MS });
      await page.locator('[data-section="quick"]').click();
      await waitForCondition(() => requests.exhaustedCtl - exhaustedBefore >= 4, 8000,
        "passive control retry did not reach its explicit terminal attempt");
      await page.waitForTimeout(3500);
      assert(requests.exhaustedCtl - exhaustedBefore === 4,
        `persistent control failure did not stop after three retries: ${requests.exhaustedCtl - exhaustedBefore}`);
      assert((await page.locator('#ctl_wizard').innerText()).includes('busy'),
        'terminal passive control error was not left visible with the manual refresh control');
      assert(runtimeErrors.length === 0,
        `exhausted passive control retry raised runtime errors: ${runtimeErrors.join("; ")}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    {
      const apiBefore = requests.api;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true, {
        "smartap.uiVersion": "cr6608-smartap-v86-live-design-27.0.0",
        "smartap.interval": "garbage"
      });
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      assert(await page.locator("#intervalSelect").inputValue() === "5",
        "a corrupt current-version polling interval was not normalized to 5 seconds");
      assert(await page.evaluate(() => localStorage.getItem("smartap.interval")) === null,
        "zero-retention migration retained the retired polling interval");
      await page.waitForTimeout(1200);
      assert(requests.api - apiBefore <= 5,
        `a corrupt polling interval caused an API request flood: ${requests.api - apiBefore} requests`);

      const fullBeforePoll = requests.full;
      const modesBeforePoll = requests.apiModes.length;
      // The production live-only default is 30 seconds. Allow the full period
      // plus browser/host scheduling margin before declaring the poll missing.
      await waitForCondition(() => requests.full > fullBeforePoll, 40000,
        "regular polling did not request a fresh full snapshot");
      const periodicModes = requests.apiModes.slice(modesBeforePoll).filter((_, index) =>
        requests.apiProbes[modesBeforePoll + index] !== true);
      assert(periodicModes.length > 0 && periodicModes.every(mode => mode === "full"),
        `regular polling reused a lite snapshot after bootstrap: ${JSON.stringify(periodicModes)}`);
      assert(await page.evaluate(() => window.__lastApi && window.__lastApi._liveLite === false),
        "regular full polling left the dashboard classified as lite data");
      await page.locator('[data-section="wifi"]').click();
      await page.waitForSelector('#wifi .section-head');
      await page.locator('#langAr').click();
      await page.waitForFunction(() => {
        const description = document.querySelector('#wifi .section-head p');
        return /TX Power منفصل/.test((description && description.textContent) || "");
      });
      await page.locator('[data-section="devices"]').click();
      await page.waitForSelector('#devices #lanScanBtn');
      await page.locator('#langEn').click();
      await page.waitForFunction(() => {
        const scanButton = document.querySelector('#lanScanBtn');
        return /Discover devices on the network/.test((scanButton && scanButton.textContent) || "");
      });

      await page.locator('[data-section="quick"]').click();
      await page.waitForSelector('#ctl_wizard .wizard-tabs', { timeout: 3000 });
      await page.locator('[data-ctl-field="ssid"]').fill('Unsaved Draft SSID');
      await page.locator('[data-wizard-tab="security"]').click();
      await page.locator('#langAr').click();
      await page.waitForFunction(() => {
        const active = document.querySelector('[data-section="quick"]');
        const tab = document.querySelector('[data-wizard-tab="security"]');
        const draft = document.querySelector('[data-control-section="wizard"] [data-ctl-field="ssid"]');
        return active && active.classList.contains('active') && active.getAttribute('aria-current') === 'page' &&
          tab && tab.getAttribute('aria-selected') === 'true' && /إعدادات الحماية/.test(tab.textContent) &&
          draft && draft.value === 'Unsaved Draft SSID';
      }, null, { timeout: 3000 });
      await page.locator('#langEn').click();
      await page.waitForFunction(() => {
        const active = document.querySelector('[data-section="quick"]');
        const tab = document.querySelector('[data-wizard-tab="security"]');
        const draft = document.querySelector('[data-control-section="wizard"] [data-ctl-field="ssid"]');
        return active && active.classList.contains('active') && active.getAttribute('aria-current') === 'page' &&
          tab && tab.getAttribute('aria-selected') === 'true' && /Security settings/.test(tab.textContent) &&
          draft && draft.value === 'Unsaved Draft SSID';
      }, null, { timeout: 3000 });

      await page.locator('[data-section="isolation"]').click();
      await page.waitForSelector('#ctl_isolation [data-isolation-tab="wifi"]', { timeout: 3000 });
      await page.locator('[data-isolation-tab="wifi"]').click();
      await page.locator('[data-control-section="isolation"] [data-ctl-field="wifi_isolate"]').selectOption('1');
      await page.locator('#langAr').click();
      await page.waitForFunction(() => {
        const tab = document.querySelector('[data-isolation-tab="wifi"]');
        const draft = document.querySelector('[data-control-section="isolation"] [data-ctl-field="wifi_isolate"]');
        return tab && tab.getAttribute('aria-selected') === 'true' && /عزل Wi-Fi/.test(tab.textContent) &&
          draft && draft.value === '1';
      }, null, { timeout: 3000 });
      await page.locator('#langEn').click();
      await page.waitForFunction(() => {
        const tab = document.querySelector('[data-isolation-tab="wifi"]');
        const draft = document.querySelector('[data-control-section="isolation"] [data-ctl-field="wifi_isolate"]');
        return tab && tab.getAttribute('aria-selected') === 'true' && /Wi-Fi isolation/.test(tab.textContent) &&
          draft && draft.value === '1';
      }, null, { timeout: 3000 });
      assert(runtimeErrors.length === 0, `interval/language recovery raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `interval/language recovery raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "stale_auto_recovery";
    {
      staleFullResponsesRemaining = 1;
      const fullBefore = requests.full;
      const { page, runtimeErrors, resourceErrors, navigationStarted } = await newPage(browser, false, true, {
        "smartap.interval": "120"
      });
      assert(await page.locator("#intervalSelect").inputValue() === "5",
        "browser storage changed the live-only default polling interval");
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: FIRST_DATA_WAIT_MS });
      const automaticRecoveryMs = Date.now() - navigationStarted;
      assert(requests.full - fullBefore >= 2,
        "automatic stale recovery did not perform both stale and fresh full reads");
      assert(!(await page.locator("body").innerText()).includes("Stale Router Model"),
        "automatic recovery rendered the rejected stale snapshot");
      assert(automaticRecoveryMs < FIRST_DATA_SLA_MS,
        `automatic stale recovery missed the fresh-data SLA: ${automaticRecoveryMs}ms`);
      assert(runtimeErrors.length === 0, `automatic stale recovery raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `automatic stale recovery raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "invalidated_refresh";
    {
      invalidatedFullResponsesRemaining = 1;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      const invalidatedState = await page.evaluate(() => ({
        lastApi: window.__lastApi,
        body: document.body.innerText
      }));
      assert(invalidatedState.lastApi && invalidatedState.lastApi.snapshot_live === true,
        "invalidated response did not recover to a live sample");
      assert(!invalidatedState.body.includes("Invalidated Router Model"),
        "invalidated snapshot was rendered before recovery");
      assert(runtimeErrors.length === 0, `invalidated refresh raised runtime errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0, `invalidated refresh raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    await waitForFullRequestsToSettle();

    scenario = "busy_snapshot";
    {
      busyFullResponsesRemaining = 1;
      const fullBefore = requests.full;
      const { page, runtimeErrors, resourceErrors, navigationStarted } = await newPage(browser, false, true);
      await page.waitForTimeout(1200);
      const interim = await page.evaluate(() => window.__lastApi || {});
      assert(interim.error !== "busy", "semantic busy response was rendered as dashboard data");
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      const freshVisibleMs = Date.now() - navigationStarted;
      assert(freshVisibleMs < 5500, `busy response suppressed the next full retry: ${freshVisibleMs}ms`);
      assert(requests.full - fullBefore >= 2, "busy response did not trigger a full retry");
      assert(runtimeErrors.length === 0, `busy retry raised runtime errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0, `busy retry raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    {
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true, {
        "smartap.uiVersion": "cr6608-smartap-v86-live-design-27.0.0",
        "smartap.histories": "{broken-json",
        "smartap.availability": "{}",
        "smartap.events": "{}",
        "smartap.knownMacs": "{}",
        "smartap.weeklyLog": "[]",
        "smartap.outageLog": "{}",
        "smartap.latHist": "[]"
      });
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      await page.locator('[data-section="actions"]').click();
      await page.waitForFunction(() => {
        const section = document.querySelector("#actions");
        return section && !section.hidden && section.innerText.includes("Events / Alerts");
      }, null, { timeout: 2500 });
      const telemetryStorage = await page.evaluate(() =>
        ["histories", "availability", "events", "knownMacs", "weeklyLog", "outageLog", "latHist"]
          .reduce((values, key) => {
            values[key] = localStorage.getItem("smartap." + key);
            return values;
          }, {}));
      assert(Object.values(telemetryStorage).every(value => value === null),
        `zero-retention migration retained legacy telemetry storage: ${JSON.stringify(telemetryStorage)}`);
      assert(await page.locator("#appShell").isVisible(), "pre-existing browser storage prevented dashboard startup");
      assert(runtimeErrors.length === 0, `pre-existing browser storage raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `pre-existing browser storage raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    {
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      const fullBefore = requests.full;
      const slowFullBefore = requests.slowFull;
      slowFullResponsesRemaining = 1;
      scenario = "slow_full_force";
      await waitForCondition(() => requests.slowFull > slowFullBefore, 40000,
        "regular polling did not start the delayed full request");
      const fullAfterSlowStarted = requests.full;
      await page.locator("#refreshBtn").click();
      await waitForCondition(() => requests.full > fullAfterSlowStarted, 5000,
        "forceFull requested during a delayed full poll was dropped");
      assert(requests.full - fullBefore >= 2,
        "queued forceFull scenario did not issue a replacement full request");
      assert(requests.slowFull === slowFullBefore + 1,
        "queued forceFull scenario did not exercise exactly one delayed full response");
      assert(runtimeErrors.length === 0, `queued forceFull raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `queued forceFull raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      scenario = "success";
      await page.close();
    }

    scenario = "success";
    {
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      await page.locator('[data-section="actions"]').click();
      const fullBefore = requests.full;
      const actionBefore = requests.action;
      await page.locator('[data-action="wifi_radio0"]').click();
      await page.locator('[data-action="wifi_radio0"]').click();
      await new Promise(resolve => {
        const deadline = Date.now() + 3000;
        const poll = () => requests.full > fullBefore ? resolve() : (Date.now() > deadline ? resolve() : setTimeout(poll, 50));
        poll();
      });
      assert(requests.action === actionBefore + 1, "confirmed dashboard action did not reach dashaction");
      assert(requests.full > fullBefore, "successful dashboard action waited for the 60-second full refresh interval");
      assert(runtimeErrors.length === 0, `action refresh raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0, `action refresh raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    scenario = "success";
    {
      const probeBefore = requests.apiProbes.filter(Boolean).length;
      const { page, runtimeErrors, resourceErrors } = await newPage(browser, false, true);
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      await page.evaluate(() => {
        document.querySelector("#loginPass").value = "must-not-survive-pagehide";
        const search = document.querySelector("#navSearch");
        if (search) search.value = "must-not-survive-pagehide";
        const event = new Event("pagehide");
        Object.defineProperty(event, "persisted", { value: true });
        window.dispatchEvent(event);
      });
      const scrubbed = await page.evaluate(() => ({
        lastApi: window.__lastApi,
        password: document.querySelector("#loginPass").value,
        search: (document.querySelector("#navSearch") || {}).value || "",
        appHidden: document.querySelector("#appShell").hidden,
        sectionBytes: Array.from(document.querySelectorAll("main > section"))
          .reduce((total, section) => total + section.innerHTML.length, 0)
      }));
      assert(scrubbed.lastApi === null, "pagehide retained the last API snapshot");
      assert(scrubbed.password === "", "pagehide retained the password field");
      assert(scrubbed.search === "", "pagehide retained the navigation draft");
      assert(scrubbed.appHidden === true, "pagehide left the old dashboard visible");
      assert(scrubbed.sectionBytes === 0, "pagehide retained rendered telemetry sections");

      const navigation = page.waitForNavigation({ waitUntil: "domcontentloaded", timeout: UI_STATE_WAIT_MS });
      await page.evaluate(() => {
        const event = new Event("pageshow");
        Object.defineProperty(event, "persisted", { value: true });
        window.dispatchEvent(event);
      });
      await navigation;
      await page.waitForFunction(() => document.body.innerText.includes("Fresh Router Model"), null, { timeout: UI_STATE_WAIT_MS });
      assert(requests.apiProbes.filter(Boolean).length > probeBefore,
        "bfcache restoration did not revalidate the HttpOnly cookie");
      assert(runtimeErrors.length === 0, `page-memory scrub raised browser errors: ${runtimeErrors.join("; ")}`);
      assert(resourceErrors.length === 0,
        `page-memory scrub raised HTTP console errors: ${JSON.stringify(resourceErrors)}`);
      await page.close();
    }

    console.log("login_runtime_tests=pass");
    console.log(`login_requests=${requests.login}`);
    console.log(`session_validation_requests=${requests.api}`);
    console.log(`full_data_requests=${requests.full}`);
    assert(requests.dashluci === 1, `dashboard issued ${requests.dashluci} dashluci bridge requests`);
    console.log(`dashluci_bridge_requests=${requests.dashluci}`);
    console.log(`luci_redirect_requests=${requests.luciRoute}`);
  } finally {
    await browser.close();
    server.close();
  }
})().catch(error => {
  console.error(error.stack || String(error));
  server.close();
  process.exit(1);
});

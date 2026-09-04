#!/usr/bin/env node

const http = require("http");
const fs = require("fs");
const path = require("path");
const playwrightCandidates = [
  path.resolve(__dirname, "..", "test-tools", "playwright", "node_modules", "playwright-core"),
  path.resolve(__dirname, "..", "..", "tools", "playwright", "node_modules", "playwright-core"),
  path.resolve(__dirname, "..", "..", "..", "tools", "playwright", "node_modules", "playwright-core")
];
if (process.env.HOME)
  playwrightCandidates.push(path.resolve(process.env.HOME, "tools", "playwright", "node_modules", "playwright-core"));
const playwrightCore = playwrightCandidates.find((candidate) => fs.existsSync(path.join(candidate, "package.json")));
if (!playwrightCore) {
  throw new Error("playwright-core is missing from the CR6608 test tools directory");
}
const { chromium } = require(playwrightCore);

const root = path.resolve(__dirname, "..", "files", "www");
const outDir = process.env.CR6608_UI_SCREENSHOT_DIR
  ? path.resolve(process.env.CR6608_UI_SCREENSHOT_DIR)
  : path.resolve(__dirname, "..", ".mobile-layout");
if (path.basename(outDir) !== ".mobile-layout") {
  throw new Error("CR6608_UI_SCREENSHOT_DIR must end with .mobile-layout");
}
const argonCascadePath = path.join(root, "luci-static", "argon", "css", "cascade.css");
const argonMobilePath = path.join(root, "luci-static", "argon", "css", "cr6608-mobile.css");
const argonLocalTimePath = path.join(root, "luci-static", "argon", "js", "cr6608-localtime.js");
const argonHeaderPath = path.resolve(
  __dirname, "..", "files", "usr", "share", "ucode", "luci", "template", "themes", "argon", "header.ut"
);
const argonCss = [
  fs.readFileSync(argonCascadePath, "utf8"),
  fs.existsSync(argonMobilePath) ? fs.readFileSync(argonMobilePath, "utf8") : ""
].join("\n");
const argonLocalTimeJs = fs.existsSync(argonLocalTimePath)
  ? fs.readFileSync(argonLocalTimePath, "utf8")
  : "";
fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });
let dashluciRequests = 0;
let luciRouteRequests = 0;
let applyStatusControl = null;
let dashApiSeen = 0;
let dashApiActive = 0;
let dashApiMaxActive = 0;
let dashApiGate = null;
let dashCtlGetRequests = 0;

const mock = {
  ok: true,
  snapshot_live: true,
  snapshot_stale: false,
  snapshot_invalidated: false,
  snapshot_age_s: 0,
  hostname: "CR6608-D4F3C8",
  uptime: 900,
  load: [0.16, 0.11, 0.07],
  cpu: { cores: 4, percent: 7 },
  mem: { total: 254156800, available: 172000000 },
  storage: { total: 102285312, used: 57344, available: 97275904 },
  health: { score: 94, grade: "Excellent", busy_pct: 8 },
  clients: 2,
  temperature_c: 48,
  latency_ms: 1,
  backhaul: { online: true, gateway: "192.168.1.254", device: "lan1" },
  traffic: {
    rx_bytes: 1200000, tx_bytes: 430000, rx_bps: 120000, tx_bps: 42000,
    topology_complete: true, uplink_device: "lan1", counter_window: "since-interface-reset"
  },
  interfaces: [
    { name: "br-lan", connected: true, speed_mbps: 1000, rx_bps: 120000, tx_bps: 42000,
      rx_errors: 80, tx_errors: 20, rx_dropped: 40, tx_dropped: 10 },
    { name: "lan1", connected: true, speed_mbps: 1000, rx_bps: 90000, tx_bps: 31000,
      rx_errors: 0, tx_errors: 0, rx_dropped: 19, tx_dropped: 0 },
    { name: "lan2", connected: false, speed_mbps: 0, rx_bps: 0, tx_bps: 0 },
    { name: "lan3", connected: false, speed_mbps: 0, rx_bps: 0, tx_bps: 0 },
    { name: "phy0-ap0", connected: true, speed_mbps: 0, rx_bps: 30000, tx_bps: 11000,
      rx_errors: 70, tx_errors: 30, rx_dropped: 5, tx_dropped: 5 }
  ],
  wifi: [
    {
      iface: "phy0-ap0", ssid: "Smart ap 2.4G", mode: "ap", band: "2.4G",
      channel: 11, htmode: "HE20", signal_dbm: -34, noise_dbm: -95, clients: 2,
      radio: "radio0", up: true, disabled: false, state: "up", reason: "",
      requested_dbm: 38, applied_dbm: 30, max_dbm: 30,
      txpower: { requested_dbm: 38, applied_dbm: 30, max_dbm: 30, status: "limited", reason: "regulatory-or-driver-limit" },
      survey: { busy_pct: 7 }, stations: [{
        mac: "1C:9F:4E:56:E0:98", ip: "192.168.1.101", signal_dbm: -17, noise_dbm: -91, snr: 74,
        tx_rate: 24.3, rx_rate: 1,
        tx_rate_detail: "24.3 MBit/s 20MHz HE-MCS 2 HE-NSS 1 HE-GI 1",
        rx_rate_detail: "1.0 MBit/s 20MHz HE-MCS 0 HE-NSS 1 HE-GI 2",
        inactive_ms: 1234, conn_s: 600, tx_packets: 100, tx_retries: 4, tx_failed: 0,
        upload_bytes: 250000, download_bytes: 900000, upload_bps: 3200, download_bps: 22000
      }, {
        mac: "02:11:22:33:44:55", ip: "192.168.1.102", signal_dbm: -41, noise_dbm: -91, snr: 50,
        tx_rate: 270.8, rx_rate: 6,
        tx_rate_detail: "270.8 MBit/s 20MHz HE-MCS 11 HE-NSS 2 HE-GI 1",
        rx_rate_detail: "6.0 MBit/s 20MHz HE-MCS 0 HE-NSS 1 HE-GI 2",
        inactive_ms: 6320, conn_s: 240, tx_packets: 20, tx_retries: 1, tx_failed: 0,
        expected_mbps: 999
      }]
    },
    {
      iface: "phy1-ap0", ssid: "Smart ap 5G", mode: "ap", band: "5G",
      channel: 149, htmode: "HE80", signal_dbm: -31, noise_dbm: -95, clients: 1,
      radio: "radio1", up: true, disabled: false, state: "up", reason: "",
      requested_dbm: 38, applied_dbm: 23, max_dbm: 23,
      txpower: { requested_dbm: 38, applied_dbm: 23, max_dbm: 23, status: "limited", reason: "regulatory-or-driver-limit" },
      survey: { busy_pct: 9 }, stations: []
    }
  ],
  devices: []
};

const wizardControl = {
  ok: true,
  cards: [
    { label: "Mode", value: "Access Point" },
    { label: "TX Power", value: "38 requested / accepted varies" }
  ],
  form: [
    { name: "program_mode", label: "وضع البرمجة", value: "ap", type: "select", options: "ap:نقطة وصول,ap_vlan:نقطة وصول + VLAN", group: "device" },
    { name: "device_ip", label: "Management address", value: "192.168.1.1", type: "text", group: "device" },
    { name: "ssid", label: "Wi-Fi name", value: "Smart AP", type: "text", group: "device" },
    { name: "security", label: "Security", value: "open", type: "select", options: "open:Open,wpa2:WPA2", group: "security" },
    { name: "txpower_radio0", label: "2.4 GHz TX power", value: "38", type: "number", options: "1:38:1", group: "advanced" },
    { name: "txpower_radio1", label: "5 GHz TX power", value: "38", type: "number", options: "1:38:1", group: "advanced" }
  ],
  actions: [{ id: "apply_royal", label: "Save & Apply" }]
};

const isolationControl = {
  ok: true,
  summary: "Optional protections and VLAN controls loaded",
  cards: [
    { label: "LAN1", value: "Enabled", hint: "Plain switch", level: "ok" },
    { label: "LAN2", value: "Enabled", hint: "Plain switch", level: "ok" },
    { label: "LAN3", value: "Enabled", hint: "Plain switch", level: "ok" },
    { label: "Wi-Fi 2.4G", value: "Not isolated" },
    { label: "Protection", value: "Enabled" }
  ],
  form: [
    { name: "security_enabled", label: "Protection", value: "1", type: "select", options: "1:On,0:Off", group: "guard" },
    { name: "wifi_isolate24", label: "2.4G client isolation", value: "0", type: "select", options: "0:Off,1:On", group: "wifi" },
    { name: "lan1_enabled", label: "LAN1", value: "1", type: "select", options: "1:On,0:Off", group: "ports" },
    { name: "lan1_vlan_mode", label: "LAN1 mode", value: "plain", type: "select", options: "plain:Plain,access:Access,trunk:Trunk", group: "ports" },
    { name: "lan1_vlan", label: "LAN1 VLAN", value: "1", type: "number", options: "1:4094:1", group: "ports" },
    { name: "lan1_isolate", label: "LAN1 isolation", value: "0", type: "select", options: "0:Off,1:On", group: "ports" },
    { name: "lan2_enabled", label: "LAN2", value: "1", type: "select", options: "1:On,0:Off", group: "ports" },
    { name: "lan2_vlan_mode", label: "LAN2 mode", value: "plain", type: "select", options: "plain:Plain,access:Access,trunk:Trunk", group: "ports" },
    { name: "lan2_vlan", label: "LAN2 VLAN", value: "1", type: "number", options: "1:4094:1", group: "ports" },
    { name: "lan2_isolate", label: "LAN2 isolation", value: "0", type: "select", options: "0:Off,1:On", group: "ports" },
    { name: "lan3_enabled", label: "LAN3", value: "1", type: "select", options: "1:On,0:Off", group: "ports" },
    { name: "lan3_vlan_mode", label: "LAN3 mode", value: "plain", type: "select", options: "plain:Plain,access:Access,trunk:Trunk", group: "ports" },
    { name: "lan3_vlan", label: "LAN3 VLAN", value: "1", type: "number", options: "1:4094:1", group: "ports" },
    { name: "lan3_isolate", label: "LAN3 isolation", value: "0", type: "select", options: "0:Off,1:On", group: "ports" }
  ],
  actions: [{ id: "apply_isolation", label: "Apply settings" }]
};

function send(res, code, type, body) {
  const data = Buffer.from(body);
  res.writeHead(code, {
    "Content-Type": type,
    "Content-Length": data.length,
    "Cache-Control": "no-store"
  });
  res.end(data);
}

async function waitForCondition(predicate, label, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  throw new Error(`timed out waiting for ${label}`);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  if (url.pathname === "/cgi-bin/dashlogin") {
    res.setHeader("Set-Cookie", "cr6608_mock_session=valid; Path=/; HttpOnly; SameSite=Strict");
    send(res, 200, "application/json", '{"ok":true}');
    return;
  }
  if (url.pathname === "/cgi-bin/dashapi2") {
    if (!/(?:^|;\s*)cr6608_mock_session=valid(?:;|$)/.test(req.headers.cookie || "")) {
      send(res, 403, "application/json", '{"ok":false,"error":"auth"}');
      return;
    }
    dashApiSeen++;
    dashApiActive++;
    dashApiMaxActive = Math.max(dashApiMaxActive, dashApiActive);
    const payloadAtArrival = JSON.stringify(mock);
    let finished = false;
    function finish() {
      if (finished) return;
      finished = true;
      dashApiActive = Math.max(0, dashApiActive - 1);
      if (!res.destroyed && !res.writableEnded)
        send(res, 200, "application/json", payloadAtArrival);
    }
    res.once("close", () => {
      if (finished) return;
      finished = true;
      dashApiActive = Math.max(0, dashApiActive - 1);
    });
    if (dashApiGate) dashApiGate.push(finish); else finish();
    return;
  }
  if (url.pathname === "/cgi-bin/dashlogout") {
    res.setHeader("Set-Cookie", "cr6608_mock_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict");
    send(res, 200, "application/json", '{"ok":true}');
    return;
  }
  if (url.pathname === "/cgi-bin/dashluci") {
    dashluciRequests++;
    send(res, 410, "application/json", '{"ok":false,"error":"smartap_only"}');
    return;
  }
  if (url.pathname === "/cgi-bin/luci" || url.pathname.startsWith("/cgi-bin/luci/")) {
    luciRouteRequests++;
    res.writeHead(302, {
      Location: "/",
      "Content-Length": "0",
      "Cache-Control": "no-store"
    });
    res.end();
    return;
  }
  if (url.pathname === "/cgi-bin/dashctl") {
    if (req.method === "GET") dashCtlGetRequests++;
    const querySection = url.searchParams.get("section");
    let body = "";
    req.on("data", chunk => { body += chunk; });
    req.on("end", () => {
      const section = new URLSearchParams(body).get("section") || querySection;
      const control = section === "apply_status"
        ? (applyStatusControl || { ok:true, busy:false, pending:false, safe_state:"clean", confirmation_ready:false, actions:[], rollback_token:"" })
        : section === "isolation" ? isolationControl : wizardControl;
      send(res, 200, "application/json", JSON.stringify(control));
    });
    return;
  }

  const rel = url.pathname === "/" ? "index.html" : url.pathname.replace(/^\/+/, "");
  const file = path.resolve(root, rel);
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    send(res, 404, "text/plain", "not found");
    return;
  }
  const ext = path.extname(file);
  const type = ext === ".html" ? "text/html; charset=utf-8"
    : ext === ".js" ? "application/javascript; charset=utf-8"
      : ext === ".css" ? "text/css; charset=utf-8"
        : ext === ".svg" ? "image/svg+xml"
          : "application/octet-stream";
  send(res, 200, type, fs.readFileSync(file));
});

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function argonFixture(dataPage, body, direction = "ltr") {
  const safeCss = argonCss.replace(/<\/style/gi, "<\\/style");
  const safeLocalTimeJs = argonLocalTimeJs.replace(/<\/script/gi, "<\\/script");
  return `<!doctype html>
<html lang="${direction === "rtl" ? "ar" : "en"}" dir="${direction}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>${safeCss}</style>
</head>
<body class="lang_${direction === "rtl" ? "ar" : "en"} logged-in" data-page="${dataPage}">
  <div class="main">
    <div class="main-left" id="mainmenu" style="display:none"></div>
    <div class="main-right">
      <header class="bg-primary"><div class="fill"><div class="container">
        <div class="flex1"><a class="showSide" href="#mainmenu" role="button" aria-label="Toggle navigation menu" aria-controls="mainmenu" aria-expanded="false"><span class="cr6608-menu-lines" aria-hidden="true"><i></i><i></i><i></i></span></a><a class="brand">Smart AP</a></div>
      </div></div></header>
      <div id="maincontent"><div class="container">${body}</div></div>
    </div>
  </div>
  <script>${safeLocalTimeJs}</script>
</body>
</html>`;
}

async function measureBidiOrder(page, selector, valueProperty, expected, tokens) {
  return page.evaluate(({ selector, valueProperty, expected, tokens }) => {
    const element = document.querySelector(selector);
    const marked = valueProperty ? element.value : element.textContent;
    const marks = /[\u2066-\u2069]/g;
    const plain = marked.replace(marks, "");
    const style = getComputedStyle(element);
    const mirror = document.createElement("span");
    mirror.style.cssText = "position:fixed;left:0;top:0;opacity:0;pointer-events:none;white-space:nowrap";
    mirror.style.font = style.font;
    mirror.style.direction = style.direction;
    mirror.style.unicodeBidi = style.unicodeBidi;
    mirror.textContent = marked;
    document.body.appendChild(mirror);
    const node = mirror.firstChild;

    function markedOffset(plainOffset) {
      let seen = 0;
      for (let index = 0; index < marked.length; index++) {
        if (/[\u2066-\u2069]/.test(marked[index])) continue;
        if (seen === plainOffset) return index;
        seen++;
      }
      return marked.length;
    }

    let cursor = 0;
    const positions = tokens.map(token => {
      const plainStart = plain.indexOf(token, cursor);
      if (plainStart < 0) return { token, found:false };
      cursor = plainStart + token.length;
      const range = document.createRange();
      range.setStart(node, markedOffset(plainStart));
      range.setEnd(node, markedOffset(cursor));
      const rect = range.getBoundingClientRect();
      return { token, found:true, left:rect.left, right:rect.right, width:rect.width };
    });
    mirror.remove();

    const lri = (marked.match(/\u2066/g) || []).length;
    const rli = (marked.match(/\u2067/g) || []).length;
    const pdi = (marked.match(/\u2069/g) || []).length;
    const visuallyOrdered = positions.every((position, index) =>
      position.found && position.width > 0 &&
      (index === 0 || position.left >= positions[index - 1].right - 1));
    return {
      expected,
      plain,
      marked,
      ariaLabel:element.getAttribute("aria-label"),
      direction:style.direction,
      unicodeBidi:style.unicodeBidi,
      lri,
      rli,
      pdi,
      visuallyOrdered,
      positions
    };
  }, { selector, valueProperty, expected, tokens });
}

async function verifyBidiRefreshRepair(page, selector, valueProperty, expected) {
  await page.evaluate(({ selector, valueProperty, expected }) => {
    const element = document.querySelector(selector);
    if (valueProperty) element.value = expected;
    else element.textContent = expected;
  }, { selector, valueProperty, expected });
  await page.waitForFunction(({ selector, valueProperty, expected }) => {
    const element = document.querySelector(selector);
    const marked = valueProperty ? element.value : element.textContent;
    return marked !== expected && marked.replace(/[\u2066-\u2069]/g, "") === expected &&
      /[\u2066\u2067]/.test(marked);
  }, { selector, valueProperty, expected });
}

async function verifyOverviewNavigationClearance(page, width) {
  await page.waitForSelector("#overview > .section-head > .chip");
  const metrics = await page.evaluate(() => {
    const rect = element => {
      const value = element.getBoundingClientRect();
      return { left:value.left, right:value.right, top:value.top, bottom:value.bottom,
        width:value.width, height:value.height };
    };
    const overlaps = (a, b) =>
      Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 &&
      Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1;
    const head = document.querySelector("#overview > .section-head");
    const info = head.querySelector(":scope > div");
    const badge = head.querySelector(":scope > .chip");
    const main = document.querySelector(".main");
    const nav = document.querySelector(".side");
    const headRect = rect(head), infoRect = rect(info), badgeRect = rect(badge);
    const mainRect = rect(main), navRect = rect(nav);
    const headStyle = getComputedStyle(head), mainStyle = getComputedStyle(main);
    return {
      head:headRect,
      info:infoRect,
      badge:badgeRect,
      main:mainRect,
      nav:navRect,
      headDisplay:headStyle.display,
      headColumns:headStyle.gridTemplateColumns,
      mainPaddingBottom:parseFloat(mainStyle.paddingBottom) || 0,
      badgeIntersectsNav:overlaps(badgeRect, navRect),
      headIntersectsNav:overlaps(headRect, navRect)
    };
  });

  assert(!metrics.badgeIntersectsNav && !metrics.headIntersectsNav,
    `overview timestamp intersects navigation at ${width}px: ${JSON.stringify(metrics)}`);
  if (width <= 820) {
    assert(metrics.headDisplay === "grid" && metrics.headColumns !== "none" &&
      metrics.badge.top < metrics.info.bottom - 1,
    `overview timestamp is not in the reserved heading row at ${width}px: ${JSON.stringify(metrics)}`);
    assert(metrics.mainPaddingBottom >= metrics.nav.height + 16,
      `bottom navigation has no reserved scroll space at ${width}px: ${JSON.stringify(metrics)}`);
    assert(metrics.badge.top >= metrics.main.top - 1 && metrics.badge.bottom <= metrics.main.bottom + 1 &&
      metrics.badge.bottom <= metrics.nav.top - 4,
    `overview timestamp is clipped by the scroll viewport/navigation at ${width}px: ${JSON.stringify(metrics)}`);
  }
}

async function verifyIsolationApplyClearance(page, width) {
  await page.waitForSelector("#ctl_isolation .isolation-apply");
  const metrics = await page.evaluate(() => {
    const rect = element => {
      const value = element.getBoundingClientRect();
      return { left:value.left, right:value.right, top:value.top, bottom:value.bottom,
        width:value.width, height:value.height };
    };
    const overlaps = (a, b) =>
      Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 &&
      Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1;
    const apply = document.querySelector("#ctl_isolation .isolation-apply");
    const applyRect = rect(apply);
    const rows = Array.from(document.querySelectorAll("#ctl_isolation [data-dsa-port]")).map(row => {
      const rowRect = rect(row);
      return { port:row.dataset.dsaPort, rect:rowRect, intersectsApply:overlaps(rowRect, applyRect) };
    });
    const lastBottom = Math.max.apply(null, rows.map(row => row.rect.bottom));
    return {
      position:getComputedStyle(apply).position,
      apply:applyRect,
      rows,
      reservedGap:applyRect.top - lastBottom
    };
  });

  assert(metrics.position === "static",
    `Save & Apply is still floating at ${width}px: ${JSON.stringify(metrics)}`);
  assert(metrics.rows.length === 3 && metrics.rows.every(row => !row.intersectsApply),
    `Save & Apply intersects a LAN card at ${width}px: ${JSON.stringify(metrics)}`);
  assert(metrics.reservedGap >= 11,
    `Save & Apply has no real reserved row after LAN3 at ${width}px: ${JSON.stringify(metrics)}`);
}

function topTabs(labels) {
  return `<div id="tabmenu"><ul class="tabs">${labels.map((label, index) =>
    `<li class="tabmenu-item-${index}${index === 0 ? " active" : ""}"><a href="#tab-${index}">${label}</a></li>`
  ).join("")}</ul></div>`;
}

async function verifyArgonTabLayout(page, name, dataPage, labels, className = "tabs") {
  const tabMarkup = className === "tabs"
    ? topTabs(labels)
    : `<div class="cbi-section"><ul class="cbi-tabmenu">${labels.map((label, index) =>
      `<li class="${index === 0 ? "cbi-tab" : "cbi-tab-disabled"}"><a href="#tab-${index}">${label}</a></li>`
    ).join("")}</ul></div>`;
  await page.setContent(argonFixture(dataPage, `${tabMarkup}<div class="cbi-map"><h2>${name}</h2></div>`), {
    waitUntil: "domcontentloaded"
  });
  const selector = className === "tabs" ? ".tabs" : ".cbi-tabmenu";
  const metrics = await page.evaluate((listSelector) => {
    const list = document.querySelector(listSelector);
    const listRect = list.getBoundingClientRect();
    const items = Array.from(list.children).map(item => {
      const itemRect = item.getBoundingClientRect();
      const link = item.querySelector("a");
      const linkRect = link.getBoundingClientRect();
      return {
        text:link.textContent.trim(),
        left:itemRect.left, right:itemRect.right, top:itemRect.top, bottom:itemRect.bottom,
        linkLeft:linkRect.left, linkRight:linkRect.right,
        linkScrollWidth:link.scrollWidth, linkClientWidth:link.clientWidth,
        whiteSpace:getComputedStyle(link).whiteSpace
      };
    });
    return {
      viewport:innerWidth,
      documentScrollWidth:document.documentElement.scrollWidth,
      listLeft:listRect.left,
      listRight:listRect.right,
      listScrollWidth:list.scrollWidth,
      listClientWidth:list.clientWidth,
      flexWrap:getComputedStyle(list).flexWrap,
      rows:new Set(items.map(item => Math.round(item.top))).size,
      items
    };
  }, selector);
  await page.screenshot({ path:path.join(outDir, `argon-${name}-390.png`), fullPage:true });
  assert(metrics.documentScrollWidth <= metrics.viewport + 1,
    `${name} tabs overflow the 390px viewport: ${JSON.stringify(metrics)}`);
  assert(metrics.flexWrap === "wrap" && metrics.rows >= 2,
    `${name} tabs did not wrap into readable rows: ${JSON.stringify(metrics)}`);
  assert(metrics.listScrollWidth <= metrics.listClientWidth + 1,
    `${name} tabs still require hidden horizontal scrolling: ${JSON.stringify(metrics)}`);
  assert(metrics.items.every(item =>
    item.left >= metrics.listLeft - 1 && item.right <= metrics.listRight + 1 &&
    item.linkLeft >= metrics.listLeft - 1 && item.linkRight <= metrics.listRight + 1 &&
    item.linkScrollWidth <= item.linkClientWidth + 1 && item.whiteSpace === "normal"),
  `${name} contains a clipped tab label: ${JSON.stringify(metrics.items)}`);
}

async function verifyArgonSystemTime(page, direction, width) {
  const labels = ["General Settings", "Logging", "Time Synchronization", "Language and Style"];
  const tabs = `<ul class="cbi-tabmenu">${labels.map((label, index) =>
    `<li class="${index === 0 ? "cbi-tab" : "cbi-tab-disabled"}"><a href="#system-${index}">${label}</a></li>`
  ).join("")}</ul>`;
  const localTime = direction === "rtl"
    ? "16 أغسطس 2026، 1:55:26 م غرينتش+3"
    : "Aug 16, 2026, 1:55:26 PM GMT+3";
  const body = `<div class="cbi-map"><div class="cbi-section"><h3>System Properties</h3>${tabs}
    <div class="cbi-section-node"><div class="cbi-value">
      <label class="cbi-value-title" for="localtime">Local Time</label>
      <div class="cbi-value-field"><input id="localtime" type="text" readonly value="${localTime}"><br>
        <span class="control-group"><button class="cbi-button cbi-button-apply">Sync with browser</button>
        <button class="cbi-button cbi-button-apply">Sync with NTP-Server</button></span>
      </div>
    </div></div>
  </div></div>`;
  await page.setViewportSize({ width, height:844 });
  await page.setContent(argonFixture("admin-system-system", body, direction), { waitUntil:"domcontentloaded" });
  await page.waitForFunction(() => document.querySelector("#localtime").classList.contains("cr6608-localtime-bidi"));
  await verifyBidiRefreshRepair(page, "#localtime", true, localTime);
  const metrics = await page.evaluate(() => {
    const input = document.querySelector("#localtime");
    const tabs = document.querySelector(".cbi-tabmenu");
    const menuToggle = document.querySelector(".showSide");
    const menuToggleRect = menuToggle.getBoundingClientRect();
    const menuBeforeStyle = getComputedStyle(menuToggle, "::before");
    const menuLines = Array.from(menuToggle.querySelectorAll(".cr6608-menu-lines > i")).map(line => {
      const rect = line.getBoundingClientRect();
      const style = getComputedStyle(line);
      return {
        left:rect.left, right:rect.right, top:rect.top, bottom:rect.bottom,
        width:rect.width, height:rect.height,
        display:style.display, backgroundColor:style.backgroundColor
      };
    });
    const field = input.parentElement;
    const controls = document.querySelector("#localtime + br + .control-group");
    const inputRect = input.getBoundingClientRect();
    const fieldRect = field.getBoundingClientRect();
    const controlRect = controls.getBoundingClientRect();
    const buttons = Array.from(controls.querySelectorAll("button")).map(button => {
      const rect = button.getBoundingClientRect();
      return { left:rect.left, right:rect.right, top:rect.top, bottom:rect.bottom };
    });
    const style = getComputedStyle(input);
    return {
      viewport:innerWidth,
      documentScrollWidth:document.documentElement.scrollWidth,
      direction:style.direction,
      unicodeBidi:style.unicodeBidi,
      inputLeft:inputRect.left,
      inputRight:inputRect.right,
      inputWidth:inputRect.width,
      fieldWidth:fieldRect.width,
      controlsLeft:controlRect.left,
      controlsRight:controlRect.right,
      tabsFlexWrap:getComputedStyle(tabs).flexWrap,
      tabsScrollWidth:tabs.scrollWidth,
      tabsClientWidth:tabs.clientWidth,
      tabRows:new Set(Array.from(tabs.children).map(tab => Math.round(tab.getBoundingClientRect().top))).size,
      tabs:Array.from(tabs.children).map(tab => {
        const rect = tab.getBoundingClientRect();
        return { left:rect.left, right:rect.right, text:tab.textContent.trim() };
      }),
      menuToggle:{
        role:menuToggle.getAttribute("role"),
        ariaLabel:menuToggle.getAttribute("aria-label"),
        ariaControls:menuToggle.getAttribute("aria-controls"),
        ariaExpanded:menuToggle.getAttribute("aria-expanded"),
        iconAriaHidden:menuToggle.querySelector(".cr6608-menu-lines").getAttribute("aria-hidden"),
        text:menuToggle.textContent.trim(),
        left:menuToggleRect.left, right:menuToggleRect.right,
        top:menuToggleRect.top, bottom:menuToggleRect.bottom,
        display:getComputedStyle(menuToggle).display,
        beforeContent:menuBeforeStyle.content,
        beforeDisplay:menuBeforeStyle.display,
        lines:menuLines
      },
      buttons
    };
  });
  const bidi = await measureBidiOrder(page, "#localtime", true, localTime,
    direction === "rtl"
      ? ["16", "أغسطس", "2026", "1:55:26", "م", "غرينتش", "+3"]
      : ["Aug", "16", "2026", "1:55:26", "PM", "GMT", "+3"]);
  const screenshotName = `argon-system-${direction}-${width}.png`;
  await page.screenshot({ path:path.join(outDir, screenshotName), fullPage:true });
  if (width <= 768) {
    const menu = metrics.menuToggle;
    assert(menu.role === "button" && menu.ariaLabel === "Toggle navigation menu" &&
      menu.ariaControls === "mainmenu" && menu.ariaExpanded === "false" &&
      menu.iconAriaHidden === "true" && menu.text === "",
    `mobile menu toggle lost its accessible contract: ${JSON.stringify(menu)}`);
    assert(menu.display === "inline-flex" && menu.beforeDisplay === "none" &&
      menu.lines.length === 3 && menu.lines.every(line =>
        line.display === "block" && line.width >= 20 && line.height >= 2 &&
        line.backgroundColor !== "rgba(0, 0, 0, 0)" &&
        line.left >= menu.left - 1 && line.right <= menu.right + 1 &&
        line.top >= menu.top - 1 && line.bottom <= menu.bottom + 1) &&
      menu.lines[0].top < menu.lines[1].top && menu.lines[1].top < menu.lines[2].top,
    `mobile menu toggle is not a visible three-line hamburger: ${JSON.stringify(menu)}`);
  }
  assert(metrics.documentScrollWidth <= metrics.viewport + 1,
    `system ${direction}/${width} layout overflows: ${JSON.stringify(metrics)}`);
  assert(bidi.direction === "ltr" && bidi.unicodeBidi === "isolate" &&
    bidi.plain === bidi.expected && bidi.ariaLabel === bidi.expected &&
    bidi.lri + bidi.rli > 0 && bidi.pdi === bidi.lri + bidi.rli && bidi.visuallyOrdered,
  `local time is not visually ordered inside ${direction}/${width}: ${JSON.stringify(bidi)}`);
  assert(metrics.inputLeft >= -1 && metrics.inputRight <= metrics.viewport + 1 &&
    metrics.inputWidth <= metrics.fieldWidth + 1,
  `local time is clipped in ${direction}: ${JSON.stringify(metrics)}`);
  assert(metrics.controlsLeft >= -1 && metrics.controlsRight <= metrics.viewport + 1 &&
    metrics.buttons.length === 2 && metrics.buttons.every(button => button.left >= -1 && button.right <= metrics.viewport + 1),
  `time synchronization controls are clipped in ${direction}: ${JSON.stringify(metrics)}`);
  assert(metrics.tabsScrollWidth <= metrics.tabsClientWidth + 1 &&
    metrics.tabs.every(tab => tab.left >= -1 && tab.right <= metrics.viewport + 1) &&
    (width > 600 || (metrics.tabsFlexWrap === "wrap" && metrics.tabRows >= 2)),
  `system tabs are clipped in ${direction}/${width}: ${JSON.stringify(metrics)}`);
}

async function verifyArgonStatusTime(page, direction, width) {
  const labels = [
    "Hostname", "Model", "Architecture", "Target Platform",
    "Firmware Version", "Kernel Version", "Local Time", "Uptime", "Load Average"
  ];
  const values = [
    "CR6608-D4F3C8", "Xiaomi Mi Router CR6608", "MediaTek MT7621 ver:1 eco:3",
    "ramips/mt7621", "OpenWrt 25.12.5 / LuCI", "6.12.94",
    direction === "rtl" ? "16 أغسطس 2026، 1:55:26 م غرينتش+3" : "Aug 16, 2026, 1:55:26 PM GMT+3",
    "0h 10m 59s", "0.70, 0.52, 0.26"
  ];
  const rows = labels.map((label, index) =>
    `<tr class="tr"><td class="td left" width="33%">${label}</td><td class="td left">${values[index]}</td></tr>`
  ).join("");
  const body = `<div id="view"><div class="cbi-section"><div class="cbi-title"><h3>System</h3></div>
    <div><table class="table"><tbody>${rows}</tbody></table></div></div></div>`;
  await page.setViewportSize({ width, height:844 });
  await page.setContent(argonFixture("admin-status-overview", body, direction), { waitUntil:"domcontentloaded" });
  await page.waitForFunction(() => document.querySelector(
    "#view > .cbi-section:first-child .table .tr:nth-child(7) > .td:last-child"
  ).classList.contains("cr6608-localtime-bidi"));
  await verifyBidiRefreshRepair(page,
    "#view > .cbi-section:first-child .table .tr:nth-child(7) > .td:last-child",
    false,
    values[6]);
  const metrics = await page.evaluate(() => {
    const cell = document.querySelector("#view > .cbi-section:first-child .table .tr:nth-child(7) > .td:last-child");
    const rect = cell.getBoundingClientRect();
    const style = getComputedStyle(cell);
    return {
      viewport:innerWidth,
      documentScrollWidth:document.documentElement.scrollWidth,
      left:rect.left,
      right:rect.right,
      width:rect.width,
      scrollWidth:cell.scrollWidth,
      clientWidth:cell.clientWidth,
      direction:style.direction,
      unicodeBidi:style.unicodeBidi,
      textAlign:style.textAlign,
      whiteSpace:style.whiteSpace,
      textOverflow:style.textOverflow,
      text:cell.textContent.replace(/[\u2066-\u2069]/g, "").trim()
    };
  });
  const bidi = await measureBidiOrder(page,
    "#view > .cbi-section:first-child .table .tr:nth-child(7) > .td:last-child",
    false,
    values[6],
    direction === "rtl"
      ? ["16", "أغسطس", "2026", "1:55:26", "م", "غرينتش", "+3"]
      : ["Aug", "16", "2026", "1:55:26", "PM", "GMT", "+3"]);
  await page.screenshot({ path:path.join(outDir, `argon-status-${direction}-${width}.png`), fullPage:true });
  assert(metrics.documentScrollWidth <= metrics.viewport + 1 && metrics.left >= -1 && metrics.right <= metrics.viewport + 1,
    `status Local Time overflows at ${width}px/${direction}: ${JSON.stringify(metrics)}`);
  assert(metrics.direction === "ltr" && metrics.unicodeBidi === "isolate" && metrics.textAlign === "left" &&
    bidi.plain === bidi.expected && bidi.ariaLabel === bidi.expected &&
    bidi.lri + bidi.rli > 0 && bidi.pdi === bidi.lri + bidi.rli && bidi.visuallyOrdered,
  `status Local Time has unstable bidi ordering at ${width}px/${direction}: ${JSON.stringify({ metrics, bidi })}`);
  assert(metrics.whiteSpace === "normal" && metrics.textOverflow === "clip" &&
    metrics.scrollWidth <= metrics.clientWidth + 1,
  `status Local Time remains clipped at ${width}px/${direction}: ${JSON.stringify(metrics)}`);
  assert(metrics.text === values[6],
    `status Local Time text changed at ${width}px/${direction}: ${JSON.stringify(metrics)}`);
}

async function verifyArgonWirelessLayout(page) {
  const row = (sid, badge, status) => `<div class="tr cbi-section-table-row" data-sid="${sid}">
    <div class="td cbi-value-field" data-name="_badge"><div class="center"><span class="ifacebadge">${badge}</span></div></div>
    <div class="td cbi-value-field" data-name="_stat"><div>${status}</div></div>
    <div class="td cbi-section-actions"><div><button class="cbi-button">Restart</button><button class="cbi-button">Scan</button><button class="cbi-button">Add</button></div></div>
  </div>`;
  const radioStatus = `<big><strong>MediaTek MT7915E 802.11ax/b/g/n</strong></big><div><strong>Channel:</strong> 11 (2.462 GHz) | <strong>Bitrate:</strong> 1201 Mbit/s</div>`;
  const networkStatus = `<strong>SSID:</strong> Smart ap 2.4G | <strong>Mode:</strong> Master<br><strong>BSSID:</strong> D4:35:38:D4:F3:C8 | <strong>Encryption:</strong> WPA3-SAE`;
  const body = `<div id="cbi-wireless" class="cbi-map"><h2>Wireless Overview</h2><div class="cbi-section-node">
    ${row("radio0", "radio0", radioStatus)}${row("wifinet0", "-41/-89 dBm", networkStatus)}
  </div></div>`;
  await page.setContent(argonFixture("admin-network-wireless", body), { waitUntil:"domcontentloaded" });
  const metrics = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll("#cbi-wireless .cbi-section-table-row[data-sid]")).map(row => {
      const rowRect = row.getBoundingClientRect();
      const badge = row.querySelector('[data-name="_badge"]');
      const status = row.querySelector('[data-name="_stat"]');
      const badgeRect = badge.getBoundingClientRect();
      const statusRect = status.getBoundingClientRect();
      const statusBody = status.firstElementChild;
      const statusStyle = getComputedStyle(statusBody);
      return {
        sid:row.dataset.sid,
        rowLeft:rowRect.left,
        rowRight:rowRect.right,
        badgeLeft:badgeRect.left,
        badgeRight:badgeRect.right,
        badgeBottom:badgeRect.bottom,
        statusLeft:statusRect.left,
        statusRight:statusRect.right,
        statusTop:statusRect.top,
        statusScrollWidth:statusBody.scrollWidth,
        statusClientWidth:statusBody.clientWidth,
        statusWhiteSpace:statusStyle.whiteSpace,
        statusTextOverflow:statusStyle.textOverflow,
        text:status.textContent.replace(/\s+/g, " ").trim()
      };
    });
    return {
      viewport:innerWidth,
      documentScrollWidth:document.documentElement.scrollWidth,
      rows
    };
  });
  await page.screenshot({ path:path.join(outDir, "argon-wireless-390.png"), fullPage:true });
  assert(metrics.documentScrollWidth <= metrics.viewport + 1,
    `wireless page overflows the 390px viewport: ${JSON.stringify(metrics)}`);
  assert(metrics.rows.length === 2 && metrics.rows.every(row =>
    row.badgeLeft >= row.rowLeft - 1 && row.badgeRight <= row.rowRight + 1 &&
    row.statusLeft >= row.rowLeft - 1 && row.statusRight <= row.rowRight + 1 &&
    row.statusTop >= row.badgeBottom - 1 &&
    row.statusScrollWidth <= row.statusClientWidth + 1 &&
    row.statusWhiteSpace === "normal" && row.statusTextOverflow === "clip"),
  `wireless status cells remain crowded or clipped: ${JSON.stringify(metrics.rows)}`);
  assert(metrics.rows[0].text.includes("Channel: 11 (2.462 GHz)") &&
    metrics.rows[1].text.includes("BSSID: D4:35:38:D4:F3:C8"),
  `Channel or BSSID text was lost: ${JSON.stringify(metrics.rows)}`);
}

(async () => {
  const argonHeader = fs.readFileSync(argonHeaderPath, "utf8");
  assert(fs.existsSync(argonMobilePath), "dedicated Argon mobile stylesheet is missing");
  assert(fs.existsSync(argonLocalTimePath), "Argon Local Time bidi helper is missing");
  assert(argonHeader.includes('class="cr6608-menu-lines" aria-hidden="true"><i></i><i></i><i></i></span>'),
    "Argon header does not contain the font-independent hamburger icon");
  assert(argonHeader.includes("/css/cr6608-mobile.css?v=20260816-argon-mobile-v64-rtlfix1"),
    "Argon header does not load the mobile compatibility stylesheet last");
  assert(argonHeader.includes("/js/cr6608-localtime.js?v=20260816-argon-localtime-v64-rtlfix1"),
    "Argon header does not load the Local Time bidi helper");
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  const launchOptions = { headless: true };
  const configuredBrowser = process.env.CR6608_BROWSER_PATH;
  if (configuredBrowser) {
    launchOptions.executablePath = configuredBrowser;
  } else if (process.platform === "win32") {
    launchOptions.executablePath = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
  }
  const browser = await chromium.launch(launchOptions);
  try {
    for (const width of [360, 390, 430]) {
      const page = await browser.newPage({
        viewport: { width, height: 844 },
        deviceScaleFactor: 1,
        isMobile: true,
        hasTouch: true
      });
      // The dashboard intentionally performs periodic authenticated polling, so
      // networkidle is not a valid readiness signal once a cookie is reusable.
      await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "domcontentloaded" });
      await page.waitForSelector(".login-card");
      const loginMetrics = await page.evaluate(() => {
        const card = document.querySelector(".login-card").getBoundingClientRect();
        return {
          bodyScrollWidth: document.documentElement.scrollWidth,
          cardLeft: card.left,
          cardRight: card.right,
          viewport: innerWidth
        };
      });
      await page.screenshot({ path: path.join(outDir, `smartap-login-${width}.png`) });
      assert(loginMetrics.bodyScrollWidth <= width + 1,
        `login page has horizontal overflow at ${width}px: ${JSON.stringify(loginMetrics)}`);
      assert(loginMetrics.cardLeft >= 0 && loginMetrics.cardRight <= width,
        `login card is outside the viewport at ${width}px: ${JSON.stringify(loginMetrics)}`);
      await page.fill("#loginPass", "admin");
      await page.click("#loginBtn");
      await page.waitForSelector("#appShell:not([hidden])");
      await page.waitForTimeout(3400);
      assert((await page.locator("#openWrtBtn").count()) === 1,
        `authenticated OpenWrt settings button is missing at ${width}px`);
      assert((await page.locator('a[href^="/cgi-bin/luci"], form[action^="/cgi-bin/luci"]').count()) === 0,
        `LuCI navigation is present in Smart AP at ${width}px`);
      if (width === 390) {
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0 && !window.__smartApDebug?.pendingDataRefresh);
        const baselineRequests = dashApiSeen;
        dashApiMaxActive = dashApiActive;
        dashApiGate = [];
        try {
          await page.evaluate(() => {
            for (let index = 0; index < 8; index++) document.querySelector("#refreshBtn").click();
          });
          await waitForCondition(() => dashApiSeen === baselineRequests + 1 && dashApiActive === 1,
            "one coalesced dashboard GET");
          await new Promise(resolve => setTimeout(resolve, 220));
          assert(dashApiSeen === baselineRequests + 1 && dashApiMaxActive === 1,
            `refresh burst was not latest-wins/max-one: ${JSON.stringify({ baselineRequests, dashApiSeen, dashApiActive, dashApiMaxActive })}`);
        } finally {
          const pending = dashApiGate || [];
          dashApiGate = null;
          pending.forEach(finish => finish());
        }
        await waitForCondition(() => dashApiActive === 0, "coalesced dashboard GET release");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
      }

      async function verifySection(name, selector) {
        if (name !== "overview") {
          await page.click(`[data-section="${name}"]`);
          await page.waitForSelector(selector);
          await page.waitForTimeout(250);
        }
        const metrics = await page.evaluate(() => {
        const visible = Array.from(document.querySelectorAll("body *")).filter(el => {
          const s = getComputedStyle(el);
          const r = el.getBoundingClientRect();
          return s.display !== "none" && s.visibility !== "hidden" && r.width > 1 && r.height > 1;
        });
        function clippedByHorizontalScroller(el) {
          for (let p = el.parentElement; p; p = p.parentElement) {
            const s = getComputedStyle(p);
            if ((s.overflowX === "auto" || s.overflowX === "scroll") && p.scrollWidth > p.clientWidth) return true;
          }
          return false;
        }
        const offenders = visible.filter(el => {
          const r = el.getBoundingClientRect();
          return (r.left < -1 || r.right > innerWidth + 1) && !clippedByHorizontalScroller(el);
        }).slice(0, 12).map(el => {
          const r = el.getBoundingClientRect();
          return `${el.tagName.toLowerCase()}#${el.id}.${el.className} [${r.left.toFixed(1)},${r.right.toFixed(1)}]`;
        });
        const nav = document.querySelector(".side").getBoundingClientRect();
        const navLabelStyle = getComputedStyle(document.querySelector(".nav button span"));
        const navButtons = Array.from(document.querySelectorAll(".nav button")).map(el => {
          const rect = el.getBoundingClientRect();
          return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom };
        });
        const mainElement = document.querySelector(".main");
        const main = mainElement.getBoundingClientRect();
        const hero = document.querySelector(".hero").getBoundingClientRect();
        const heroControls = Array.from(document.querySelectorAll(".controls > *")).map(el => {
          const rect = el.getBoundingClientRect();
          return { visible: rect.width > 1 && rect.height > 1, left: rect.left, right: rect.right };
        });
        const heroInfoRect = document.querySelector(".hero-top > div:first-child").getBoundingClientRect();
        const heroControlsRect = document.querySelector(".controls").getBoundingClientRect();
        const detailTitle = document.querySelector(".branch-detail > h3");
        return {
          viewport: innerWidth,
          viewportHeight: innerHeight,
          bodyScrollWidth: document.documentElement.scrollWidth,
          offenders,
          navTop: nav.top,
          navBottom: nav.bottom,
          navButtons,
          navLabelWhiteSpace: navLabelStyle.whiteSpace,
          navLabelLineClamp: navLabelStyle.webkitLineClamp,
          mainBottom: main.bottom,
          mainScrollTop: mainElement.scrollTop,
          heroTop: hero.top,
          heroHeight: hero.height,
          contentPaddingBottom: parseFloat(getComputedStyle(document.querySelector(".app")).paddingBottom),
          heroControls,
          heroInfoBottom: heroInfoRect.bottom,
          heroControlsTop: heroControlsRect.top,
          detailTitleSize: detailTitle ? parseFloat(getComputedStyle(detailTitle).fontSize) : 0
        };
        });
        await page.screenshot({ path: path.join(outDir, `smartap-${name}-${width}.png`) });
        assert(metrics.bodyScrollWidth <= width + 1, `horizontal overflow in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.offenders.length === 0, `elements outside viewport in ${name} at ${width}px: ${metrics.offenders.join("; ")}`);
        assert(metrics.navTop >= metrics.viewportHeight - 160, `bottom navigation is not anchored at the bottom in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.navButtons.length === 9 && metrics.navButtons.every(button =>
          button.left >= -1 && button.right <= width + 1 &&
          button.top >= metrics.navTop - 1 && button.bottom <= metrics.navBottom + 1),
        `not every primary destination is visible in the phone navigation for ${name} at ${width}px: ${JSON.stringify(metrics.navButtons)}`);
        assert(metrics.navLabelWhiteSpace === "normal" && metrics.navLabelLineClamp === "2",
          `bottom navigation labels are not readable on two lines in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.contentPaddingBottom >= 160, `bottom navigation can cover ${name} content at ${width}px`);
        assert(metrics.mainBottom <= metrics.navTop - 2,
          `scrolling content extends behind bottom navigation in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.mainScrollTop <= 1 && metrics.heroTop >= -1,
          `section did not open at its top in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.heroHeight >= 120,
          `mobile header was compressed in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.heroControls.length === 6 && metrics.heroControls.every(c => c.visible && c.left >= -1 && c.right <= width + 1),
          `header controls are clipped in ${name} at ${width}px: ${JSON.stringify(metrics.heroControls)}`);
        assert(metrics.heroControlsTop >= metrics.heroInfoBottom - 1,
          `header controls overlap the title in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        if (name === "quick" || name === "isolation")
          assert(metrics.detailTitleSize > 0 && metrics.detailTitleSize <= 21,
            `${name} detail title is oversized at ${width}px: ${metrics.detailTitleSize}`);
      }
      async function waitForStableCanvas(id, afterGeneration = -1) {
        const handle = await page.waitForFunction(({ canvasId, generation }) => {
          const canvas = document.getElementById(canvasId);
          if (!canvas || !canvas.isConnected || canvas.dataset.chartStable !== "1") return false;
          const currentGeneration = Number(canvas.dataset.chartGeneration || 0);
          if (!(currentGeneration > generation)) return false;
          const rect = canvas.getBoundingClientRect();
          if (rect.width < 2 || rect.height < 2 || canvas.width < 2 || canvas.height < 2) return false;
          const pixels = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data;
          let painted = 0;
          for (let i = 3; i < pixels.length; i += 4) if (pixels[i] !== 0) painted++;
          return painted > 100 ? {
            generation:currentGeneration,
            stable:canvas.dataset.chartStable,
            rectWidth:rect.width, rectHeight:rect.height,
            width:canvas.width, height:canvas.height, painted
          } : false;
        }, { canvasId:id, generation:afterGeneration }, { timeout:10000 });
        const metrics = await handle.jsonValue();
        await handle.dispose();
        return metrics;
      }
      async function verifyAccessibleTables(selector) {
        const tables = await page.evaluate(rootSelector => Array.from(
          document.querySelectorAll(`${rootSelector} table`)
        ).map(table => ({
          caption:(table.querySelector(":scope > caption")?.textContent || "").trim(),
          headers:Array.from(table.querySelectorAll("thead th")).map(header => header.getAttribute("scope"))
        })), selector);
        assert(tables.length > 0 && tables.every(table =>
          table.caption.length > 0 && table.headers.length > 0 && table.headers.every(scope => scope === "col")),
        `table captions or column scopes are incomplete in ${selector} at ${width}px: ${JSON.stringify(tables)}`);
      }
      async function holdAnimationFrames() {
        await page.evaluate(() => {
          if (window.__smartApHeldAnimationFrames) throw new Error("animation frames are already held");
          const original = window.requestAnimationFrame;
          const callbacks = [];
          window.__smartApHeldAnimationFrames = { original, callbacks };
          window.requestAnimationFrame = callback => {
            callbacks.push(callback);
            return callbacks.length;
          };
        });
      }
      async function releaseAnimationFrames() {
        await page.evaluate(() => {
          const held = window.__smartApHeldAnimationFrames;
          if (!held) return;
          window.requestAnimationFrame = held.original;
          delete window.__smartApHeldAnimationFrames;
          held.callbacks.splice(0).forEach(callback => held.original.call(window, callback));
        });
      }
      async function verifyIsolationControls() {
        const metrics = await page.evaluate(() => {
          const specs = ["lan1", "lan2", "lan3"].flatMap(port => [
            { port, role: "enabled", name: `${port}_enabled`, value: "1" },
            { port, role: "mode", name: `${port}_vlan_mode`, value: "plain" },
            { port, role: "vlan", name: `${port}_vlan`, value: "1" },
            { port, role: "isolation", name: `${port}_isolate`, value: "0" }
          ]);
          const rect = element => {
            const r = element.getBoundingClientRect();
            return { left:r.left, right:r.right, top:r.top, bottom:r.bottom, width:r.width, height:r.height };
          };
          const overlaps = (a, b) =>
            Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 &&
            Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1;
          const fields = specs.map(spec => {
            const row = document.querySelector(`[data-dsa-port="${spec.port}"]`);
            const wrap = row && row.querySelector(`[data-dsa-control="${spec.role}"]`);
            const control = wrap && wrap.querySelector(`[data-ctl-field="${spec.name}"]`);
            const label = wrap && wrap.querySelector(":scope > span");
            if (!row || !wrap || !control || !label)
              return Object.assign({}, spec, { found:false });
            const rowRect = rect(row), wrapRect = rect(wrap), controlRect = rect(control), labelRect = rect(label);
            const style = getComputedStyle(control);
            return Object.assign({}, spec, {
              found:true,
              rendered:control.offsetParent !== null && style.display !== "none" && style.visibility !== "hidden",
              actualValue:control.value,
              label:label.textContent.trim(),
              width:controlRect.width,
              height:controlRect.height,
              contained:wrapRect.left >= rowRect.left - 1 && wrapRect.right <= rowRect.right + 1,
              labelAboveControl:labelRect.bottom <= controlRect.top + 1
            });
          });
          const fieldCollisions = [];
          const headerCollisions = [];
          const rows = ["lan1", "lan2", "lan3"].map(port => {
            const row = document.querySelector(`[data-dsa-port="${port}"]`);
            const head = row.querySelector(".dsa-port-head");
            const controls = row.querySelector(".dsa-port-controls");
            const wrappers = Array.from(controls.querySelectorAll("[data-dsa-control]"));
            for (let i = 0; i < wrappers.length; i++) {
              for (let j = i + 1; j < wrappers.length; j++) {
                if (overlaps(rect(wrappers[i]), rect(wrappers[j])))
                  fieldCollisions.push(`${port}:${wrappers[i].dataset.dsaControl}/${wrappers[j].dataset.dsaControl}`);
              }
            }
            if (overlaps(rect(head), rect(controls))) headerCollisions.push(port);
            return { port, rect:rect(row), controlCount:wrappers.length };
          });
          const rowCollisions = [];
          for (let i = 0; i < rows.length - 1; i++) {
            if (overlaps(rows[i].rect, rows[i + 1].rect))
              rowCollisions.push(`${rows[i].port}/${rows[i + 1].port}`);
          }
          return {
            total:document.querySelectorAll("#ctl_isolation [data-dsa-control] [data-ctl-field]").length,
            fields,
            rows,
            fieldCollisions,
            headerCollisions,
            rowCollisions
          };
        });
        assert(metrics.total === 12,
          `isolation controls count is wrong at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.fields.every(field =>
          field.found && field.rendered && field.label && field.width >= 80 && field.height >= 36 &&
          field.contained && field.labelAboveControl && field.actualValue === field.value),
        `an isolation field is missing, hidden, unclear, or mis-sized at ${width}px: ${JSON.stringify(metrics.fields)}`);
        assert(metrics.rows.every(row => row.controlCount === 4),
          `a LAN row does not expose enabled/mode/VLAN/isolation at ${width}px: ${JSON.stringify(metrics.rows)}`);
        assert(metrics.fieldCollisions.length === 0 && metrics.headerCollisions.length === 0 && metrics.rowCollisions.length === 0,
          `isolation fields or LAN rows overlap at ${width}px: ${JSON.stringify(metrics)}`);

        for (const port of ["lan1", "lan2", "lan3"]) {
          await page.locator(`[data-dsa-port="${port}"]`).evaluate(row =>
            row.scrollIntoView({ block:"center", inline:"nearest" }));
          await page.waitForTimeout(30);
          const visible = await page.evaluate(portName => {
            const main = document.querySelector(".main").getBoundingClientRect();
            const nav = document.querySelector(".side").getBoundingClientRect();
            const apply = document.querySelector(".isolation-apply").getBoundingClientRect();
            const controls = Array.from(document.querySelectorAll(
              `[data-dsa-port="${portName}"] [data-dsa-control] [data-ctl-field]`
            )).map(control => {
              const r = control.getBoundingClientRect();
              const intersectsApply = Math.min(r.right, apply.right) - Math.max(r.left, apply.left) > 1 &&
                Math.min(r.bottom, apply.bottom) - Math.max(r.top, apply.top) > 1;
              return {
                top:r.top, bottom:r.bottom, left:r.left, right:r.right,
                insideMain:r.top >= main.top - 1 && r.bottom <= main.bottom + 1 &&
                  r.left >= main.left - 1 && r.right <= main.right + 1,
                aboveNav:r.bottom <= nav.top - 1,
                intersectsApply
              };
            });
            return controls;
          }, port);
          assert(visible.length === 4 && visible.every(control =>
            control.insideMain && control.aboveNav && !control.intersectsApply),
          `${port} controls are not fully visible or overlap fixed UI at ${width}px: ${JSON.stringify(visible)}`);
        }
      }

      async function verifyInsightTabs() {
        const categoryTabs = page.locator("#insights .insight-tabs button");
        const categoryCount = await categoryTabs.count();
        assert(categoryCount > 1,
          `Smart Insights did not render enough categories at ${width}px`);

        await categoryTabs.last().click();
        await page.waitForSelector('#insights .insight-tabs button[aria-selected="true"].active');
        await page.locator('#insights .insight-tabs button[aria-selected="true"]').evaluate(element =>
          element.scrollIntoView({ block:"nearest", inline:"nearest" }));

        const metrics = await page.evaluate(() => {
          const list = document.querySelector("#insights .insight-tabs");
          const listRect = list.getBoundingClientRect();
          const active = list.querySelector('button[aria-selected="true"].active');
          const activeRect = active.getBoundingClientRect();
          const panel = document.querySelector("#insight-panel");
          const buttons = Array.from(list.querySelectorAll("button")).map(button => {
            const rect = button.getBoundingClientRect();
            const label = button.querySelector("span");
            return {
              label:(label ? label.textContent : button.textContent).trim(),
              id:button.id,
              selected:button.getAttribute("aria-selected"),
              controls:button.getAttribute("aria-controls"),
              tabIndex:button.tabIndex,
              left:rect.left,
              right:rect.right,
              top:rect.top,
              bottom:rect.bottom,
              labelScrollWidth:label ? label.scrollWidth : 0,
              labelClientWidth:label ? label.clientWidth : 0
            };
          });
          return {
            direction:document.documentElement.dir,
            listLabel:list.getAttribute("aria-label"),
            panel:panel ? {
              role:panel.getAttribute("role"),
              labelledBy:panel.getAttribute("aria-labelledby"),
              tabIndex:panel.tabIndex
            } : null,
            activeId:active.id,
            display:getComputedStyle(list).display,
            columns:getComputedStyle(list).gridTemplateColumns,
            scrollWidth:list.scrollWidth,
            clientWidth:list.clientWidth,
            scrollLeft:list.scrollLeft,
            listLeft:listRect.left,
            listRight:listRect.right,
            activeLeft:activeRect.left,
            activeRight:activeRect.right,
            rows:new Set(buttons.map(button => Math.round(button.top))).size,
            buttons
          };
        });
        await page.screenshot({
          path:path.join(outDir, `smartap-insights-tabs-rtl-${width}.png`),
          fullPage:true
        });

        assert(metrics.direction === "rtl" && metrics.display === "grid" && metrics.rows >= 2,
          `Smart Insights mobile categories are not an RTL-safe grid at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.scrollWidth <= metrics.clientWidth + 1 && Math.abs(metrics.scrollLeft) <= 1,
          `Smart Insights still hides categories in a horizontal scroller at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.buttons.length === categoryCount && metrics.buttons.every(button =>
          button.left >= metrics.listLeft - 1 && button.right <= metrics.listRight + 1 &&
          button.labelScrollWidth <= button.labelClientWidth + 1),
        `a Smart Insights category is clipped at ${width}px: ${JSON.stringify(metrics.buttons)}`);
        assert(metrics.activeLeft >= metrics.listLeft - 1 && metrics.activeRight <= metrics.listRight + 1,
          `the active Smart Insights category is not fully visible at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.listLabel && metrics.panel && metrics.panel.role === "tabpanel" &&
          metrics.panel.labelledBy === metrics.activeId && metrics.panel.tabIndex === 0 &&
          metrics.buttons.every(button => button.id && button.controls === "insight-panel") &&
          metrics.buttons.filter(button => button.selected === "true" && button.tabIndex === 0).length === 1 &&
          metrics.buttons.filter(button => button.selected === "false" && button.tabIndex === -1).length === categoryCount - 1,
        `Smart Insights ARIA tabs/tabpanel contract is incomplete at ${width}px: ${JSON.stringify(metrics)}`);

        await page.locator('#insights .insight-tabs button[aria-selected="true"]').press("Home");
        await page.waitForFunction(() => {
          const first = document.querySelector("#insights .insight-tabs button");
          return first?.getAttribute("aria-selected") === "true" && document.activeElement === first;
        });
        await page.locator('#insights .insight-tabs button[aria-selected="true"]').press("ArrowLeft");
        await page.waitForFunction(() => {
          const tabs = Array.from(document.querySelectorAll("#insights .insight-tabs button"));
          return tabs[1]?.getAttribute("aria-selected") === "true" && document.activeElement === tabs[1];
        });
        await page.locator('#insights .insight-tabs button[aria-selected="true"]').press("End");
        const keyboardState = await page.evaluate(() => {
          const tabs = Array.from(document.querySelectorAll("#insights .insight-tabs button"));
          const active = tabs.find(tab => tab.getAttribute("aria-selected") === "true");
          const panel = document.querySelector("#insight-panel");
          return {
            lastSelected:active === tabs[tabs.length - 1],
            focusRetained:document.activeElement === active,
            labelledBy:panel?.getAttribute("aria-labelledby"),
            activeId:active?.id
          };
        });
        assert(keyboardState.lastSelected && keyboardState.focusRetained &&
          keyboardState.labelledBy === keyboardState.activeId,
        `Smart Insights RTL keyboard activation lost selection/focus linkage at ${width}px: ${JSON.stringify(keyboardState)}`);
        if (width === 390) {
          const refreshCategory = await page.evaluate(() => {
            const active = document.querySelector('#insights .insight-tabs button[aria-selected="true"]');
            const panel = document.querySelector("#insight-panel");
            const root = document.querySelector("#insights");
            window.__stableInsightProbe = { active, panel, generation:Number(root.dataset.uiPatchGeneration || 0) };
            active.focus();
            document.querySelector("#refreshBtn").click();
            return active.dataset.insightCategory;
          });
          await page.waitForFunction(() =>
            Number(document.querySelector("#insights")?.dataset.uiPatchGeneration || 0) > window.__stableInsightProbe.generation);
          const refreshFocus = await page.evaluate(category => {
            const active = document.querySelector('#insights .insight-tabs button[aria-selected="true"]');
            const panel = document.querySelector("#insight-panel");
            return {
              category:active?.dataset.insightCategory,
              focused:document.activeElement === active,
              labelledBy:panel?.getAttribute("aria-labelledby"),
              activeId:active?.id,
              sameTab:active === window.__stableInsightProbe.active,
              samePanel:panel === window.__stableInsightProbe.panel
            };
          }, refreshCategory);
          assert(refreshFocus.category === refreshCategory && refreshFocus.focused &&
            refreshFocus.labelledBy === refreshFocus.activeId && refreshFocus.sameTab && refreshFocus.samePanel,
          `Smart Insights refresh lost the focused tab at ${width}px: ${JSON.stringify(refreshFocus)}`);
        }
      }
      await verifySection("overview", "#overview:not([hidden])");
      await verifyOverviewNavigationClearance(page, width);
      await verifySection("quick", "#ctl_wizard .wizard-tabs");
      await page.locator("#wizard-tab-advanced").click();
      await page.waitForSelector("#wizard-pane-advanced:not([hidden]) fieldset.txpower-fieldset");
      const txPowerSemantics = await page.evaluate(() => Array.from(
        document.querySelectorAll("#quick fieldset.txpower-fieldset")
      ).map(fieldset => {
        const range = fieldset.querySelector("[data-tx-range]");
        const number = fieldset.querySelector("[data-ctl-field]");
        const presetGroup = fieldset.querySelector('.txpower-presets[role="group"]');
        const preset = fieldset.querySelector('[data-tx-preset][data-value="23"]');
        const fieldRect = fieldset.getBoundingClientRect();
        const rangeRect = range?.closest("label")?.getBoundingClientRect();
        const numberRect = number?.closest("label")?.getBoundingClientRect();
        if (preset) preset.click();
        const hintId = range?.getAttribute("aria-describedby") || "";
        return {
          legend:(fieldset.querySelector("legend")?.textContent || "").trim(),
          rangeLabel:(range?.labels?.[0]?.textContent || "").trim(),
          numberLabel:(number?.labels?.[0]?.textContent || "").trim(),
          sameHint:hintId && hintId === number?.getAttribute("aria-describedby") && !!document.getElementById(hintId),
          presetLabel:(presetGroup?.getAttribute("aria-label") || "").trim(),
          synchronized:range?.value === "23" && number?.value === "23",
          visible:fieldset.offsetParent !== null && fieldRect.width > 1 && fieldRect.height > 1,
          contained:fieldset.scrollWidth <= fieldset.clientWidth + 1 &&
            rangeRect && numberRect && rangeRect.left >= fieldRect.left - 1 &&
            rangeRect.right <= fieldRect.right + 1 && numberRect.left >= fieldRect.left - 1 &&
            numberRect.right <= fieldRect.right + 1 &&
            Math.min(rangeRect.right, numberRect.right) - Math.max(rangeRect.left, numberRect.left) <= 1
        };
      }));
      assert(txPowerSemantics.length > 0 && txPowerSemantics.every(field =>
        field.legend && field.rangeLabel && field.numberLabel && field.rangeLabel !== field.numberLabel &&
        field.sameHint && field.presetLabel && field.synchronized && field.visible && field.contained),
      `TX power controls lack fieldset/labels/hint wiring or synchronization at ${width}px: ${JSON.stringify(txPowerSemantics)}`);
      if (width === 390) {
        await page.click("#wizard-tab-device");
        await page.waitForSelector('#wizard-pane-device:not([hidden]) [data-ctl-field="device_ip"]');
        await page.evaluate(() => {
          const input = document.querySelector('[data-control-section="wizard"] [data-ctl-field="device_ip"]');
          const tab = document.querySelector("#wizard-tab-device");
          input.value = "10.23.45.67";
          input.dispatchEvent(new Event("input", { bubbles:true }));
          input.focus();
          input.setSelectionRange(3, 8, "forward");
          window.__stableControlProbe = { input, tab };
        });
        const controlRefreshBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > controlRefreshBaseline, "quick-section telemetry refresh");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
        const afterRefresh = await page.evaluate(() => {
          const input = document.querySelector('[data-control-section="wizard"] [data-ctl-field="device_ip"]');
          const tab = document.querySelector("#wizard-tab-device");
          return {
            sameInput:input === window.__stableControlProbe.input,
            sameTab:tab === window.__stableControlProbe.tab,
            value:input.value,
            focused:document.activeElement === input,
            start:input.selectionStart,
            end:input.selectionEnd,
            dirty:input.dataset.uiDirty
          };
        });
        assert(afterRefresh.sameInput && afterRefresh.sameTab && afterRefresh.value === "10.23.45.67" &&
          afterRefresh.focused && afterRefresh.start === 3 && afterRefresh.end === 8 && afterRefresh.dirty === "1",
        `telemetry refresh lost control identity/draft/caret: ${JSON.stringify(afterRefresh)}`);

        const controlGetsBeforeLanguage = dashCtlGetRequests;
        const arabicLoadedCopy = await page.evaluate(() => ({
          label:document.querySelector('[data-ctl-field="program_mode"]')?.closest("label")?.querySelector("span")?.textContent.trim(),
          tab:document.querySelector("#wizard-tab-device")?.textContent.trim()
        }));
        await page.click("#langEn");
        await page.waitForFunction(() => document.documentElement.lang === "en" && document.documentElement.dir === "ltr");
        const themeBefore = await page.evaluate(() => document.documentElement.dataset.theme);
        await page.click("#themeBtn");
        await page.waitForFunction(previous => document.documentElement.dataset.theme !== previous, themeBefore);
        const afterChrome = await page.evaluate(() => {
          const input = document.querySelector('[data-control-section="wizard"] [data-ctl-field="device_ip"]');
          const tab = document.querySelector("#wizard-tab-device");
          return {
            sameInput:input === window.__stableControlProbe.input,
            sameTab:tab === window.__stableControlProbe.tab,
            value:input.value,
            start:input.selectionStart,
            end:input.selectionEnd,
            selected:tab.getAttribute("aria-selected"),
            label:document.querySelector('[data-ctl-field="program_mode"]')?.closest("label")?.querySelector("span")?.textContent.trim(),
            tabText:tab.textContent.trim(),
            hint:document.querySelector("#quick .mode-hint")?.textContent.trim()
          };
        });
        assert(afterChrome.sameInput && afterChrome.sameTab && afterChrome.value === "10.23.45.67" &&
          afterChrome.start === 3 && afterChrome.end === 8 && afterChrome.selected === "true" &&
          arabicLoadedCopy.label === "وضع البرمجة" && afterChrome.label === "Programming mode" &&
          arabicLoadedCopy.tab !== afterChrome.tabText && afterChrome.tabText === "1. Device settings" &&
          afterChrome.hint.startsWith("After applying") && dashCtlGetRequests === controlGetsBeforeLanguage,
        `language/theme update lost control identity/draft/tab/caret: ${JSON.stringify(afterChrome)}`);
        await page.click("#langAr");
        await page.waitForFunction(() => document.documentElement.lang === "ar" && document.documentElement.dir === "rtl");
        for (let attempt = 0; attempt < 3 && await page.evaluate(() => document.documentElement.dataset.theme !== "dark"); attempt++)
          await page.click("#themeBtn");
      }
      await verifySection("isolation", '#ctl_isolation [data-dsa-port="lan1"] [data-ctl-field="lan1_enabled"]');
      assert(!(await page.locator("#toast").evaluate(element => element.classList.contains("show"))),
        `a passive Safe Apply control read opened an overlay toast at ${width}px`);
      await verifyIsolationControls();
      await verifyIsolationApplyClearance(page, width);
      const toastStart = await page.evaluate(() => {
        const toastNode = document.querySelector("#toast");
        const toast = toastNode.getBoundingClientRect();
        const nav = document.querySelector(".side").getBoundingClientRect();
        return {
          shown:toastNode.classList.contains("show"),
          transform:getComputedStyle(toastNode).transform,
          toastBottom:toast.bottom,
          navTop:nav.top
        };
      });
      assert(!toastStart.shown && toastStart.toastBottom <= toastStart.navTop + 1,
        `mobile toast starts inside the navigation lane at ${width}px: ${JSON.stringify(toastStart)}`);
      await page.click('[data-ctl-action="apply_isolation"]');
      await page.waitForSelector('#ctl_isolation [data-dsa-port="lan1"] [data-ctl-field="lan1_enabled"]');
      const firstVisibleToastHandle = await page.waitForFunction(() => {
        const toastNode = document.querySelector("#toast");
        if (!toastNode.classList.contains("show")) return false;
        const toast = toastNode.getBoundingClientRect();
        const main = document.querySelector(".main").getBoundingClientRect();
        const nav = document.querySelector(".side").getBoundingClientRect();
        return {
          sample:"first-visible",
          shown:true,
          transform:getComputedStyle(toastNode).transform,
          toastTop:toast.top,
          toastBottom:toast.bottom,
          mainBottom:main.bottom,
          navTop:nav.top
        };
      });
      const toastSamples = [await firstVisibleToastHandle.jsonValue()];
      // Cover the complete desktop transition duration. A prior mobile rule
      // inherited translateY(12px), crossing four pixels into the bottom nav
      // until the animation settled; a single delayed sample was host-timing
      // dependent and could miss the visible overlap.
      for (let sample = 0; sample < 7; sample++) {
        toastSamples.push(await page.evaluate(index => {
          const toastNode = document.querySelector("#toast");
          const toast = toastNode.getBoundingClientRect();
          const main = document.querySelector(".main").getBoundingClientRect();
          const nav = document.querySelector(".side").getBoundingClientRect();
          return {
            sample:index,
            shown:toastNode.classList.contains("show"),
            transform:getComputedStyle(toastNode).transform,
            toastTop:toast.top,
            toastBottom:toast.bottom,
            mainBottom:main.bottom,
            navTop:nav.top
          };
        }, sample));
        if (sample < 6) await page.waitForTimeout(50);
      }
      const visibleToastSamples = toastSamples.filter(metrics => metrics.shown);
      assert(visibleToastSamples.length > 0 && visibleToastSamples.every(metrics =>
        metrics.mainBottom <= metrics.toastTop + 1 &&
        metrics.toastBottom <= metrics.navTop + 1),
      `mobile action toast overlaps content or navigation during transition at ${width}px: ${JSON.stringify(toastSamples)}`);
      await page.waitForFunction(() => !document.querySelector("#toast").classList.contains("show"));
      // Hold every deferred animation frame while the network section is built.
      // Its current canvas must still be sized and painted synchronously by the
      // post-innerHTML flush; releasing the frames then proves the stable pass.
      if (width === 390) await holdAnimationFrames();
      try {
        await verifySection("network", "#network:not([hidden])");
        await verifyAccessibleTables("#network");
        if (width === 390) {
          const immediateChart = await page.evaluate(() => {
            const canvas = document.getElementById("networkTrafficCanvas");
            if (!canvas) return { missing:true };
            const rect = canvas.getBoundingClientRect();
            const dpr = window.devicePixelRatio || 1;
            const pixels = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data;
            let painted = 0;
            for (let i = 3; i < pixels.length; i += 4) if (pixels[i] !== 0) painted++;
            return {
              generation:Number(canvas.dataset.chartGeneration || 0),
              rectWidth:rect.width,
              rectHeight:rect.height,
              width:canvas.width,
              height:canvas.height,
              expectedWidth:Math.floor(Math.max(260, Math.floor(rect.width)) * dpr),
              expectedHeight:Math.floor(Math.max(160, Math.floor(rect.height)) * dpr),
              painted
            };
          });
          assert(!immediateChart.missing && immediateChart.generation > 0 &&
            immediateChart.width === immediateChart.expectedWidth &&
            immediateChart.height === immediateChart.expectedHeight &&
            immediateChart.painted > 100,
          `network chart depends on a deferred animation frame: ${JSON.stringify(immediateChart)}`);
        }
      } finally {
        if (width === 390) await releaseAnimationFrames();
      }
      if (width === 390) {
        let chartMetrics = await waitForStableCanvas("networkTrafficCanvas");
        assert(chartMetrics.stable === "1" && chartMetrics.rectWidth >= 280 && chartMetrics.rectHeight >= 160 && chartMetrics.painted > 100,
          `network chart was blank or mis-sized at 390px: ${JSON.stringify(chartMetrics)}`);
        await page.evaluate(() => {
          const root = document.querySelector("#network");
          window.__stableNetworkProbe = {
            root,
            canvas:document.querySelector("#networkTrafficCanvas"),
            row:document.querySelector('[data-ui-key="interface:lan1"]'),
            childListMutations:0
          };
          window.__stableNetworkProbe.observer = new MutationObserver(records => {
            window.__stableNetworkProbe.childListMutations += records.filter(record => record.type === "childList").length;
          });
          window.__stableNetworkProbe.observer.observe(root, { subtree:true, childList:true });
        });
        // Repeated full refreshes repaint the same mounted canvas and rows.
        for (let repaint = 0; repaint < 5; repaint++) {
          const previousGeneration = chartMetrics.generation;
          await page.evaluate(() => document.querySelector("#refreshBtn").click());
          chartMetrics = await waitForStableCanvas("networkTrafficCanvas", previousGeneration);
          const stableNodes = await page.evaluate(() => ({
            root:window.__stableNetworkProbe.root === document.querySelector("#network"),
            canvas:window.__stableNetworkProbe.canvas === document.querySelector("#networkTrafficCanvas"),
            row:window.__stableNetworkProbe.row === document.querySelector('[data-ui-key="interface:lan1"]'),
            childListMutations:window.__stableNetworkProbe.childListMutations
          }));
          assert(chartMetrics.stable === "1" && chartMetrics.generation > previousGeneration && chartMetrics.painted > 100,
            `network chart repaint was blank/unstable on pass ${repaint + 1}: ${JSON.stringify(chartMetrics)}`);
          assert(stableNodes.root && stableNodes.canvas && stableNodes.row && stableNodes.childListMutations === 0,
            `network refresh changed mounted structure on pass ${repaint + 1}: ${JSON.stringify(stableNodes)}`);
        }
        await page.evaluate(() => window.__stableNetworkProbe.observer.disconnect());
        const originalInterfaces = mock.interfaces;
        await page.evaluate(() => {
          window.__networkRowProbe = {
            survivor:document.querySelector('[data-ui-key="interface:lan1"]'),
            removed:document.querySelector('[data-ui-key="interface:lan2"]')
          };
        });
        const byInterface = Object.fromEntries(originalInterfaces.map(row => [row.name, row]));
        mock.interfaces = [
          Object.assign({}, byInterface.lan1, { rx_bps:777777 }),
          { name:"wan0", connected:true, speed_mbps:1000, rx_bps:321, tx_bps:123 },
          byInterface["br-lan"], byInterface["phy0-ap0"], byInterface.lan3
        ];
        const reorderBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > reorderBaseline, "keyed interface reorder");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
        const keyedInterfaces = await page.evaluate(() => {
          const rows = Array.from(document.querySelectorAll('#network [data-ui-key^="interface:"]'));
          const survivor = document.querySelector('[data-ui-key="interface:lan1"]');
          return {
            sameSurvivor:survivor === window.__networkRowProbe.survivor,
            survivorText:survivor?.textContent || "",
            removedDisconnected:window.__networkRowProbe.removed?.isConnected === false,
            hasNew:!!document.querySelector('[data-ui-key="interface:wan0"]'),
            keys:rows.map(row => row.dataset.uiKey),
            order:rows.map(row => row.querySelector(".traffic-iface")?.textContent.trim())
          };
        });
        assert(keyedInterfaces.sameSurvivor && keyedInterfaces.survivorText.includes("6.22 Mbps") &&
          keyedInterfaces.removedDisconnected && keyedInterfaces.hasNew &&
          new Set(keyedInterfaces.keys).size === keyedInterfaces.keys.length &&
          JSON.stringify(keyedInterfaces.order) === JSON.stringify(["lan1","wan0","br-lan","phy0-ap0","lan3"]),
        `keyed interface reconciliation failed: ${JSON.stringify(keyedInterfaces)}`);
        mock.interfaces = originalInterfaces;
        const restoreInterfacesBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > restoreInterfacesBaseline, "interface fixture restore");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);

        // Change keyed content above the viewport and prove that the actual
        // .main/window scroll containers retain their numeric positions.
        mock.interfaces = Array.from({ length:12 }, (_, index) => ({
          name:`fixture${index}`,
          connected:index % 2 === 0,
          speed_mbps:1000,
          rx_bps:1000 + index,
          tx_bps:500 + index
        })).concat(originalInterfaces);
        const tallFixtureBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > tallFixtureBaseline, "tall interface fixture");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
        const heightChangingScroll = await page.evaluate(() => {
          const main = document.querySelector(".main");
          const mainTarget = Math.min(280, Math.max(0, main.scrollHeight - main.clientHeight));
          const windowTarget = Math.min(280, Math.max(0, document.documentElement.scrollHeight - innerHeight));
          main.scrollTop = mainTarget;
          window.scrollTo(0, windowTarget);
          return { mainTop:main.scrollTop, windowTop:window.scrollY };
        });
        assert(heightChangingScroll.mainTop > 100 || heightChangingScroll.windowTop > 100,
          `network did not provide a height-changing scroll fixture: ${JSON.stringify(heightChangingScroll)}`);
        mock.interfaces = Array.from({ length:6 }, (_, index) => ({
          name:`inserted${index}`,
          connected:true,
          speed_mbps:1000,
          rx_bps:5000 + index,
          tx_bps:2500 + index
        })).concat(mock.interfaces);
        const heightChangeBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > heightChangeBaseline, "height-changing keyed interface update");
        await page.waitForFunction(expected => {
          if (window.__smartApDebug?.activeDataRequests !== 0) return false;
          const main = document.querySelector(".main");
          return Math.abs(main.scrollTop - expected.mainTop) <= 1 &&
            Math.abs(window.scrollY - expected.windowTop) <= 1;
        }, heightChangingScroll);
        const afterHeightChange = await page.evaluate(() => ({
          mainTop:document.querySelector(".main").scrollTop,
          windowTop:window.scrollY,
          insertedAbove:!!document.querySelector('[data-ui-key="interface:inserted0"]')
        }));
        assert(afterHeightChange.insertedAbove &&
          Math.abs(afterHeightChange.mainTop - heightChangingScroll.mainTop) <= 1 &&
          Math.abs(afterHeightChange.windowTop - heightChangingScroll.windowTop) <= 1,
        `height-changing keyed update reset page scroll: ${JSON.stringify({ heightChangingScroll, afterHeightChange })}`);
        mock.interfaces = originalInterfaces;
        const heightFixtureRestoreBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > heightFixtureRestoreBaseline, "height fixture restore");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
      }
      await verifySection("devices", "#devices:not([hidden])");
      await verifyAccessibleTables("#devices");
      await verifySection("wifi", "#wifi:not([hidden])");
      const wifiStatus = (await page.locator("#wifi > .section-head > .chip").innerText()).trim().toLowerCase();
      assert(wifiStatus !== "offline",
        `a live Wi-Fi radio is labeled offline at ${width}px`);
      const phyText = await page.locator("#wifi").innerText();
      assert(phyText.includes("24.3 MBit/s 20MHz HE-MCS 2 HE-NSS 1 HE-GI 1") &&
        phyText.includes("1.0 MBit/s 20MHz HE-MCS 0 HE-NSS 1 HE-GI 2") &&
        phyText.includes("270.8 MBit/s 20MHz HE-MCS 11 HE-NSS 2 HE-GI 1"),
      `full station PHY details are missing at ${width}px: ${phyText}`);
      assert(phyText.includes("ليس سرعة نقل البيانات") && phyText.includes("إعادات الإرسال 4") &&
        phyText.includes("فشل الإرسال 0") && phyText.includes("الخمول 1.2 s"),
      `PHY/throughput explanation or station counters are missing at ${width}px: ${phyText}`);
      if (width === 390) {
        const originalStations = mock.wifi[0].stations;
        await page.evaluate(() => {
          window.__stationRowProbe = {
            survivor:document.querySelector('[data-ui-key="station:phy0-ap0:1c:9f:4e:56:e0:98"]'),
            removed:document.querySelector('[data-ui-key="station:phy0-ap0:02:11:22:33:44:55"]')
          };
        });
        const survivorStation = Object.assign({}, originalStations[0], {
          mac:originalStations[0].mac.toLowerCase(), signal_dbm:-29
        });
        const newStation = Object.assign({}, originalStations[0], {
          mac:"AA:BB:CC:DD:EE:FF", ip:"192.168.1.199", signal_dbm:-55
        });
        mock.wifi[0].stations = [newStation, survivorStation];
        mock.wifi[0].clients = 2;
        const stationBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > stationBaseline, "keyed station reorder");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
        const keyedStations = await page.evaluate(() => {
          const rows = Array.from(document.querySelectorAll('#wifi [data-ui-key^="station:phy0-ap0:"]'));
          const survivor = document.querySelector('[data-ui-key="station:phy0-ap0:1c:9f:4e:56:e0:98"]');
          return {
            sameSurvivor:survivor === window.__stationRowProbe.survivor,
            survivorText:survivor?.textContent || "",
            removedDisconnected:window.__stationRowProbe.removed?.isConnected === false,
            hasNew:!!document.querySelector('[data-ui-key="station:phy0-ap0:aa:bb:cc:dd:ee:ff"]'),
            keys:rows.map(row => row.dataset.uiKey)
          };
        });
        assert(keyedStations.sameSurvivor && keyedStations.survivorText.includes("-29 dBm") &&
          keyedStations.removedDisconnected && keyedStations.hasNew &&
          new Set(keyedStations.keys).size === keyedStations.keys.length &&
          JSON.stringify(keyedStations.keys) === JSON.stringify([
            "station:phy0-ap0:aa:bb:cc:dd:ee:ff", "station:phy0-ap0:1c:9f:4e:56:e0:98"
          ]), `keyed station reconciliation failed: ${JSON.stringify(keyedStations)}`);
        mock.wifi[0].stations = originalStations;
        const stationRestoreBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > stationRestoreBaseline, "station fixture restore");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
      }
      await verifySection("insights", "#insights:not([hidden])");
      await verifyInsightTabs();
      await page.click('#insights .insight-tabs button[data-insight-category="Traffic & Bandwidth"]');
      await page.waitForSelector('#insights .insight-tabs button[data-insight-category="Traffic & Bandwidth"][aria-selected="true"]');
      const measuredConsumerCards = await page.evaluate(() => {
        const wanted = new Set(["استهلاك العملاء الفعلي", "ملتهم النطاق", "أكثر العملاء استهلاكاً"]);
        return Array.from(document.querySelectorAll("#insights article.card")).map(card => ({
          title:(card.querySelector(".card-head .title > span")?.textContent || "").trim(),
          text:(card.textContent || "").trim()
        })).filter(card => wanted.has(card.title));
      });
      assert(measuredConsumerCards.length === 3 && measuredConsumerCards.every(card =>
        card.text.includes("192.168.1.101") && !card.text.includes("192.168.1.102") &&
        card.text.includes("فروق عدادات البايت")),
      `PHY-only client leaked into traffic-consumer cards at ${width}px: ${JSON.stringify(measuredConsumerCards)}`);
      const trafficSemantics = await page.evaluate(() => {
        const cards = Array.from(document.querySelectorAll("#insights article.card"));
        const byTitle = title => {
          const card = cards.find(node => (node.querySelector(".card-head .title > span")?.textContent || "").trim() === title);
          return card ? {
            text:(card.textContent || "").trim(),
            chip:(card.querySelector(".card-head .chip")?.textContent || "").trim()
          } : null;
        };
        return {
          live:byTitle("حركة العملاء الحية"),
          edge:byTitle("حركة حافة العملاء"),
          balance:byTitle("توازن التنزيل والرفع"),
          raw:byTitle("نشاط كل واجهة"),
          independent:byTitle("نشاط الواجهات المستقل"),
          counters:byTitle("لقطة عدادات كل واجهة"),
          capacity:byTitle("استخدام منفذ الرفع الموثق")
        };
      });
      for (const key of ["live", "edge", "balance", "capacity"]) {
        assert(trafficSemantics[key] && trafficSemantics[key].text.includes("تنزيل") && trafficSemantics[key].text.includes("رفع"),
          `client traffic direction is unclear in ${key}: ${JSON.stringify(trafficSemantics[key])}`);
      }
      assert(trafficSemantics.raw && trafficSemantics.raw.text.includes("Interface RX") &&
        trafficSemantics.raw.text.includes("Interface TX") && trafficSemantics.raw.text.includes("ليست تنزيل/رفع"),
      `raw interface directions are mislabeled: ${JSON.stringify(trafficSemantics.raw)}`);
      assert(trafficSemantics.independent && trafficSemantics.independent.text.includes("لا جمع ولا إزالة تكرار"),
        `per-interface activity implies an additive share: ${JSON.stringify(trafficSemantics.independent)}`);
      assert(trafficSemantics.counters && !trafficSemantics.counters.chip && trafficSemantics.counters.text.includes("لا يوجد إجمالي جامع"),
        `layered interface counters still expose a doubled grand total: ${JSON.stringify(trafficSemantics.counters)}`);
      assert(trafficSemantics.capacity && trafficSemantics.capacity.chip === "lan1" && /%/.test(trafficSemantics.capacity.text),
        `verified uplink utilization did not bind to the documented uplink: ${JSON.stringify(trafficSemantics.capacity)}`);

      await page.click('#insights .insight-tabs button[data-insight-category="Automation & UX"]');
      await page.waitForSelector('#insights .insight-tabs button[data-insight-category="Automation & UX"][aria-selected="true"]');
      await verifyAccessibleTables("#insights");
      const runtimeCounterText = await page.locator("#insights").innerText();
      assert(runtimeCounterText.includes("لقطة عدادات وقت التشغيل") && runtimeCounterText.includes("ليست فترة أسبوعية"),
        `runtime counters are still presented as a weekly digest: ${runtimeCounterText}`);
      const dsaSummary = await page.evaluate(() => Array.from(
        document.querySelectorAll("#insights .insight-summary-item")
      ).map(node => ({
        label:(node.querySelector("span")?.textContent || "").trim(),
        value:(node.querySelector("b")?.textContent || "").trim(),
        hint:(node.querySelector("small")?.textContent || "").trim()
      })));
      const dsaErrors = dsaSummary.find(item => item.label === "أخطاء DSA");
      const dsaDrops = dsaSummary.find(item => item.label === "إسقاطات DSA");
      assert(dsaErrors && dsaErrors.value === "0" && dsaErrors.hint === "منذ إعادة ضبط الواجهة",
        `logical-interface counters were misreported as DSA errors: ${JSON.stringify(dsaSummary)}`);
      assert(dsaDrops && dsaDrops.value === "19" && dsaDrops.hint === "منذ إعادة ضبط الواجهة",
        `DSA drops were double-counted across logical interfaces: ${JSON.stringify(dsaSummary)}`);
      await verifySection("system", "#system:not([hidden])");
      const gaugeSemantics = await page.evaluate(() => Array.from(
        document.querySelectorAll("#system .gauge-card")
      ).map(card => {
        const visible = Array.from(card.querySelectorAll(".gauge text")).map(node => node.textContent.trim());
        const summary = (card.querySelector(".gauge-summary")?.textContent || "").trim();
        const sparks = Array.from(card.querySelectorAll("svg.spark"));
        return {
          summary,
          title:visible[0] || "",
          value:visible[1] || "",
          gaugeHidden:card.querySelector(".gauge")?.getAttribute("aria-hidden"),
          sparksDecorative:sparks.length > 0 && sparks.every(svg =>
            svg.getAttribute("aria-hidden") === "true" && svg.getAttribute("focusable") === "false")
        };
      }));
      assert(gaugeSemantics.length >= 4 && gaugeSemantics.every(gauge =>
        gauge.summary && gauge.title && gauge.value && gauge.summary.includes(gauge.title) &&
        gauge.summary.includes(gauge.value) && gauge.gaugeHidden === "true" && gauge.sparksDecorative),
      `system gauges lack accessible summaries or expose decorative SVGs at ${width}px: ${JSON.stringify(gaugeSemantics)}`);
      await verifySection("actions", "#actions:not([hidden])");
      if (width === 390) {
        await page.click('[data-section="insights"]');
        await page.waitForSelector("#insights:not([hidden])");
        const storedScroll = await page.evaluate(() => {
          const main = document.querySelector(".main");
          const mainTarget = Math.min(360, Math.max(0, main.scrollHeight - main.clientHeight));
          const windowTarget = Math.min(360, Math.max(0, document.documentElement.scrollHeight - innerHeight));
          main.scrollTop = mainTarget;
          window.scrollTo(0, windowTarget);
          return { mainTop:main.scrollTop, windowTop:window.scrollY };
        });
        assert(storedScroll.mainTop > 100 || storedScroll.windowTop > 100,
          `insights did not provide a real scroll restoration fixture: ${JSON.stringify(storedScroll)}`);
        await page.click('[data-section="network"]');
        await page.waitForSelector("#network:not([hidden])");
        await page.click('[data-section="insights"]');
        await page.waitForFunction(expected => {
          const main = document.querySelector(".main");
          return Math.abs(main.scrollTop - expected.mainTop) <= 1 && Math.abs(window.scrollY - expected.windowTop) <= 1;
        }, storedScroll);
        const scrollRefreshBaseline = dashApiSeen;
        await page.evaluate(() => document.querySelector("#refreshBtn").click());
        await waitForCondition(() => dashApiSeen > scrollRefreshBaseline, "scrolled insights refresh");
        await page.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
        const refreshedScroll = await page.evaluate(() => ({
          mainTop:document.querySelector(".main").scrollTop,
          windowTop:window.scrollY
        }));
        assert(Math.abs(refreshedScroll.mainTop - storedScroll.mainTop) <= 1 &&
          Math.abs(refreshedScroll.windowTop - storedScroll.windowTop) <= 1,
        `poll refresh reset active-section scroll: ${JSON.stringify({ storedScroll, refreshedScroll })}`);

        const redirectProbe = await page.context().request.get(
          `http://127.0.0.1:${port}/cgi-bin/luci/admin/network/wireless`,
          { maxRedirects: 0 }
        );
        assert(redirectProbe.status() === 302,
          `legacy LuCI path returned ${redirectProbe.status()} instead of 302`);
        assert(redirectProbe.headers().location === "/",
          `legacy LuCI path redirected to ${redirectProbe.headers().location || "nothing"}`);
        await page.goto(`http://127.0.0.1:${port}/cgi-bin/luci/admin/network/wireless`, {
          waitUntil: "domcontentloaded"
        });
        await page.waitForSelector("#appShell:not([hidden])");
        assert(new URL(page.url()).pathname === "/", `browser remained on a LuCI path: ${page.url()}`);
        await page.screenshot({ path: path.join(outDir, "smartap-luci-redirect-390.png") });
      }
      await page.close();
    }

    // When uplink topology is unresolved, the overview must not present the
    // fail-closed Wi-Fi subtotal as whole-network traffic.
    const originalTraffic = mock.traffic;
    mock.traffic = Object.assign({}, originalTraffic, { topology_complete:false, uplink_device:"" });
    const partialPage = await browser.newPage({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
    try {
      await partialPage.goto(`http://127.0.0.1:${port}/`, { waitUntil:"domcontentloaded" });
      await partialPage.fill("#loginPass", "admin");
      await partialPage.click("#loginBtn");
      await partialPage.waitForSelector("#appShell:not([hidden])");
      await partialPage.waitForFunction(() => {
        const card = Array.from(document.querySelectorAll("#overview article.card")).find(node =>
          (node.querySelector(".card-head .title > span")?.textContent || "").trim().startsWith("الشبكة"));
        return card && /حواف Wi-Fi فقط/.test(card.textContent || "");
      });
      const partialOverview = await partialPage.evaluate(() => {
        const card = Array.from(document.querySelectorAll("#overview article.card")).find(node =>
          (node.querySelector(".card-head .title > span")?.textContent || "").trim().startsWith("الشبكة"));
        return {
          text:(card?.textContent || "").trim(),
          chip:(card?.querySelector(".card-head .chip")?.textContent || "").trim()
        };
      });
      assert(partialOverview.chip === "حواف Wi-Fi فقط" && partialOverview.text.includes("حُجبت عدادات منافذ DSA") &&
        partialOverview.text.includes("حواف عملاء Wi-Fi المعروفة فقط"),
      `partial overview still looks like whole-network traffic: ${JSON.stringify(partialOverview)}`);
      await partialPage.screenshot({ path:path.join(outDir, "smartap-overview-partial-390.png"), fullPage:true });
    } finally {
      await partialPage.close();
      mock.traffic = originalTraffic;
    }

    // Language/theme updates keep the authoritative transaction nodes mounted.
    applyStatusControl = {
      ok:true, busy:false, pending:true, safe_state:"armed", confirmation_ready:true,
      remaining_s:119, rollback_token:"abcdef0123456789abcdef0123456789",
      summary:"Confirmation pending", text:"Test access, then keep or roll back.", actions:[]
    };
    const rebuildPage = await browser.newPage({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
    try {
      await rebuildPage.goto(`http://127.0.0.1:${port}/`, { waitUntil:"domcontentloaded" });
      await rebuildPage.fill("#loginPass", "admin");
      await rebuildPage.click("#loginBtn");
      await rebuildPage.waitForSelector('#quick:not([hidden]) [data-ctl-action="keep_changes"]');
      await rebuildPage.evaluate(() => {
        window.__safeApplyStableProbe = {
          box:document.querySelector("#ctl_wizard"),
          keep:document.querySelector('#quick [data-ctl-action="keep_changes"]'),
          rollback:document.querySelector('#quick [data-ctl-action="rollback_last"]')
        };
      });
      await rebuildPage.click("#langEn");
      await rebuildPage.waitForSelector('#quick:not([hidden]) [data-ctl-action="keep_changes"]');
      assert((await rebuildPage.locator('#quick [data-ctl-action="keep_changes"]').innerText()).trim() === "Keep changes",
        "language update failed to translate pending Safe Apply controls");
      assert(await rebuildPage.evaluate(() =>
        window.__safeApplyStableProbe.box === document.querySelector("#ctl_wizard") &&
        window.__safeApplyStableProbe.keep === document.querySelector('#quick [data-ctl-action="keep_changes"]') &&
        window.__safeApplyStableProbe.rollback === document.querySelector('#quick [data-ctl-action="rollback_last"]')),
      "language update replaced pending Safe Apply nodes");
      await rebuildPage.click("#themeBtn");
      await rebuildPage.waitForSelector('#quick:not([hidden]) [data-ctl-action="keep_changes"]');
      assert(await rebuildPage.locator('#quick [data-ctl-action="rollback_last"]').count() === 1,
        "theme update erased pending Safe Apply controls");
      assert(await rebuildPage.evaluate(() =>
        window.__safeApplyStableProbe.box === document.querySelector("#ctl_wizard") &&
        window.__safeApplyStableProbe.keep === document.querySelector('#quick [data-ctl-action="keep_changes"]') &&
        window.__safeApplyStableProbe.rollback === document.querySelector('#quick [data-ctl-action="rollback_last"]')),
      "theme update replaced pending Safe Apply nodes");
    } finally {
      await rebuildPage.close();
      applyStatusControl = null;
    }

    // The no-retention Smart UI must reject a stale/non-live hardware snapshot
    // instead of painting cached radio or client values. Keep this separate
    // from the normal live-layout assertions.
    const originalWifi = mock.wifi;
    mock.snapshot_live = false;
    mock.snapshot_stale = true;
    mock.snapshot_age_s = 4;
    mock.devices = [];
    mock.wifi = originalWifi.map(radio => Object.assign({}, radio, { clients:0, stations:[] }));
    const stalePage = await browser.newPage({
      viewport: { width:390, height:844 },
      deviceScaleFactor:1,
      isMobile:true,
      hasTouch:true
    });
    await stalePage.goto(`http://127.0.0.1:${port}/`, { waitUntil:"domcontentloaded" });
    await stalePage.fill("#loginPass", "admin");
    await stalePage.click("#loginBtn");
    await stalePage.waitForSelector("#appShell:not([hidden])");
    await stalePage.click("#langEn");
    await stalePage.waitForFunction(() =>
      document.querySelector("#connectionState")?.textContent.trim() === "Live data unavailable");
    await stalePage.click('[data-section="wifi"]');
    await stalePage.waitForSelector("#wifi:not([hidden])");
    await stalePage.waitForFunction(() =>
      /no previous snapshot is displayed/i.test(document.querySelector("#wifi")?.textContent || ""));
    const staleWifiState = await stalePage.evaluate(() => {
      return {
        connection:document.querySelector("#connectionState").textContent.trim(),
        text:document.querySelector("#wifi").textContent.trim(),
        sectionChips:document.querySelectorAll("#wifi > .section-head > .chip").length,
        unavailableCards:document.querySelectorAll('#wifi [data-ui-key="live-unavailable:wifi"]').length,
        radioCards:document.querySelectorAll('#wifi [data-ui-key^="card:wifi-radio:"]').length
      };
    });
    assert(staleWifiState.connection === "Live data unavailable" &&
      /no previous snapshot is displayed/i.test(staleWifiState.text) &&
      staleWifiState.sectionChips === 1 && staleWifiState.unavailableCards === 1 && staleWifiState.radioCards === 0,
    `non-live Wi-Fi snapshot was not rejected fail-closed: ${JSON.stringify(staleWifiState)}`);
    await stalePage.click('[data-section="devices"]');
    await stalePage.waitForSelector("#devices:not([hidden])");
    await stalePage.waitForFunction(() =>
      /no previous snapshot is displayed/i.test(document.querySelector("#devices")?.textContent || ""));
    const staleDevicesState = await stalePage.evaluate(() => ({
      text:document.querySelector("#devices").textContent.trim(),
      liveRows:document.querySelectorAll('#devices [data-ui-key^="device:"]').length,
      unavailableCards:document.querySelectorAll('#devices [data-ui-key="live-unavailable:devices"]').length
    }));
    assert(/no previous snapshot is displayed/i.test(staleDevicesState.text) &&
      staleDevicesState.liveRows === 0 && staleDevicesState.unavailableCards === 1,
      `non-live device snapshot was not rejected fail-closed: ${JSON.stringify(staleDevicesState)}`);
    await stalePage.screenshot({ path:path.join(outDir, "smartap-nonlive-rejected-390.png") });
    await stalePage.click('[data-section="actions"]');
    await stalePage.waitForFunction(() =>
      /no previous snapshot is displayed/i.test(document.querySelector("#actions")?.textContent || ""));
    const staleActionsState = await stalePage.evaluate(() => ({
      text:document.querySelector("#actions").textContent.trim(),
      actions:document.querySelectorAll("#actions [data-action]").length,
      unavailableCards:document.querySelectorAll('#actions [data-ui-key="live-unavailable:actions"]').length
    }));
    assert(/no previous snapshot is displayed/i.test(staleActionsState.text) &&
      staleActionsState.actions === 0 && staleActionsState.unavailableCards === 1,
    `first-load Actions state was blank or exposed stale controls: ${JSON.stringify(staleActionsState)}`);
    await stalePage.close();
    mock.snapshot_live = true;
    mock.snapshot_stale = false;
    mock.snapshot_age_s = 0;
    mock.wifi = originalWifi;

    // A stale payload received after a live render must clear old values while
    // preserving the mounted section/head shell; invalidated is equally fatal.
    const transitionPage = await browser.newPage({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
    try {
      await transitionPage.goto(`http://127.0.0.1:${port}/`, { waitUntil:"domcontentloaded" });
      await transitionPage.fill("#loginPass", "admin");
      await transitionPage.click("#loginBtn");
      await transitionPage.waitForSelector("#appShell:not([hidden])");
      await transitionPage.click('[data-section="wifi"]');
      await transitionPage.waitForFunction(() => document.querySelector("#wifi")?.textContent.includes("Smart ap 2.4G"));
      await transitionPage.evaluate(() => {
        window.__staleTransitionProbe = {
          root:document.querySelector("#wifi"),
          head:document.querySelector('#wifi [data-ui-key="section-head"]')
        };
      });

      mock.snapshot_live = false;
      mock.snapshot_stale = true;
      mock.snapshot_invalidated = false;
      mock.wifi = originalWifi;
      const liveToStaleBaseline = dashApiSeen;
      await transitionPage.evaluate(() => document.querySelector("#refreshBtn").click());
      await waitForCondition(() => dashApiSeen > liveToStaleBaseline, "live-to-stale payload");
      await transitionPage.waitForFunction(() => document.body.dataset.liveState === "unavailable");
      const staleTransition = await transitionPage.evaluate(() => {
        const root = document.querySelector("#wifi");
        const head = document.querySelector('#wifi [data-ui-key="section-head"]');
        return {
          sameRoot:root === window.__staleTransitionProbe.root,
          sameHead:head === window.__staleTransitionProbe.head,
          text:root.textContent,
          rows:root.querySelectorAll('[data-ui-key^="station:"],[data-ui-key^="card:wifi-radio:"]').length,
          actions:root.querySelectorAll("[data-steer-mac]").length,
          state:root.dataset.liveState
        };
      });
      assert(staleTransition.sameRoot && staleTransition.sameHead && staleTransition.state === "unavailable" &&
        staleTransition.rows === 0 && staleTransition.actions === 0 &&
        !staleTransition.text.includes("Smart ap 2.4G") && !staleTransition.text.includes("192.168.1.101"),
      `live-to-stale transition retained old telemetry or replaced its shell: ${JSON.stringify(staleTransition)}`);

      mock.snapshot_stale = false;
      mock.snapshot_invalidated = true;
      const invalidatedBaseline = dashApiSeen;
      await transitionPage.evaluate(() => document.querySelector("#refreshBtn").click());
      await waitForCondition(() => dashApiSeen > invalidatedBaseline, "snapshot-invalidated payload");
      await transitionPage.waitForFunction(() => window.__smartApDebug?.activeDataRequests === 0);
      assert(!(await transitionPage.locator("#wifi").innerText()).includes("Smart ap 2.4G"),
        "snapshot_invalidated restored old Wi-Fi values");

      const freshWifi = originalWifi.map((radio, index) => Object.assign({}, radio,
        index === 0 ? {
          ssid:"Fresh 2.4G",
          stations:radio.stations.map((station, stationIndex) => Object.assign({}, station,
            stationIndex === 0 ? { mac:"12:34:56:78:9A:BC", ip:"192.168.1.210" } : {}))
        } : {}));
      mock.snapshot_live = true;
      mock.snapshot_invalidated = false;
      mock.wifi = freshWifi;
      const staleToLiveBaseline = dashApiSeen;
      await transitionPage.evaluate(() => document.querySelector("#refreshBtn").click());
      await waitForCondition(() => dashApiSeen > staleToLiveBaseline, "stale-to-live payload");
      await transitionPage.waitForFunction(() => document.querySelector("#wifi")?.dataset.liveState === "live" &&
        document.querySelector("#wifi")?.textContent.includes("Fresh 2.4G"));
      const recoveredTransition = await transitionPage.evaluate(() => ({
        sameRoot:document.querySelector("#wifi") === window.__staleTransitionProbe.root,
        sameHead:document.querySelector('#wifi [data-ui-key="section-head"]') === window.__staleTransitionProbe.head,
        text:document.querySelector("#wifi").textContent
      }));
      assert(recoveredTransition.sameRoot && recoveredTransition.sameHead &&
        recoveredTransition.text.includes("Fresh 2.4G") && recoveredTransition.text.includes("192.168.1.210") &&
        !recoveredTransition.text.includes("Smart ap 2.4G") && !recoveredTransition.text.includes("192.168.1.101"),
      `stale-to-live transition did not recover with new-only values: ${JSON.stringify(recoveredTransition)}`);
    } finally {
      await transitionPage.close();
      mock.snapshot_live = true;
      mock.snapshot_stale = false;
      mock.snapshot_invalidated = false;
      mock.snapshot_age_s = 0;
      mock.wifi = originalWifi;
    }

    // API-derived card/section metadata must remain text, even when it looks
    // like an executable element. This exercises the real DOM sinks.
    const originalHostname = mock.hostname;
    const originalGrade = mock.health.grade;
    const xssPayload = '<img src=x onerror="globalThis.__smartapXss=1" data-xss>';
    mock.hostname = xssPayload;
    mock.health.grade = xssPayload;
    const xssPage = await browser.newPage({ viewport:{ width:390, height:844 }, deviceScaleFactor:1 });
    await xssPage.goto(`http://127.0.0.1:${port}/`, { waitUntil:"domcontentloaded" });
    await xssPage.fill("#loginPass", "admin");
    await xssPage.click("#loginBtn");
    await xssPage.waitForSelector("#appShell:not([hidden])");
    await xssPage.click('[data-section="insights"]');
    await xssPage.waitForSelector('#insights .insight-tabs button[data-insight-category="Automation & UX"]');
    await xssPage.click('#insights .insight-tabs button[data-insight-category="Automation & UX"]');
    await xssPage.waitForFunction(payload => document.querySelector("#insights")?.textContent.includes(payload), xssPayload);
    const xssState = await xssPage.evaluate(() => ({
      elements:document.querySelectorAll("img[data-xss]").length,
      executed:globalThis.__smartapXss === 1
    }));
    assert(xssState.elements === 0 && xssState.executed === false,
      `API metadata created/executed an injected element: ${JSON.stringify(xssState)}`);
    await xssPage.close();
    mock.hostname = originalHostname;
    mock.health.grade = originalGrade;

    // Desktop smoke test: every primary section must open in the redesigned
    // control-room shell without horizontal overflow or clipped controls.
    const desktopPage = await browser.newPage({
      viewport: { width: 1440, height: 1000 },
      deviceScaleFactor: 1
    });
    await desktopPage.goto(`http://127.0.0.1:${port}/`, { waitUntil: "domcontentloaded" });
    await desktopPage.fill("#loginPass", "admin");
    await desktopPage.click("#loginBtn");
    await desktopPage.waitForSelector("#appShell:not([hidden])");
    await desktopPage.waitForTimeout(3400);
    const desktopSections = ["overview", "quick", "isolation", "network", "devices", "wifi", "insights", "system", "actions"];
    for (const sectionName of desktopSections) {
      await desktopPage.click(`[data-section="${sectionName}"]`);
      await desktopPage.waitForSelector(`#${sectionName}:not([hidden])`);
      await desktopPage.waitForTimeout(120);
      const desktopMetrics = await desktopPage.evaluate(() => {
        const shell = document.querySelector(".app").getBoundingClientRect();
        const side = document.querySelector(".side").getBoundingClientRect();
        const main = document.querySelector(".main").getBoundingClientRect();
        const controls = Array.from(document.querySelectorAll(".controls > *")).map(element => {
          const rect = element.getBoundingClientRect();
          return { left:rect.left, right:rect.right, top:rect.top, bottom:rect.bottom };
        });
        return {
          viewport:innerWidth,
          bodyScrollWidth:document.documentElement.scrollWidth,
          shellLeft:shell.left,
          shellRight:shell.right,
          sideWidth:side.width,
          mainWidth:main.width,
          controls
        };
      });
      assert(desktopMetrics.bodyScrollWidth <= desktopMetrics.viewport + 1,
        `desktop horizontal overflow in ${sectionName}: ${JSON.stringify(desktopMetrics)}`);
      assert(desktopMetrics.shellLeft >= -1 && desktopMetrics.shellRight <= desktopMetrics.viewport + 1,
        `desktop shell is outside the viewport in ${sectionName}: ${JSON.stringify(desktopMetrics)}`);
      assert(desktopMetrics.sideWidth >= 210 && desktopMetrics.mainWidth >= 900,
        `desktop information hierarchy collapsed in ${sectionName}: ${JSON.stringify(desktopMetrics)}`);
      assert(desktopMetrics.controls.length === 6 && desktopMetrics.controls.every(control =>
        control.left >= -1 && control.right <= desktopMetrics.viewport + 1 &&
        control.top >= -1 && control.bottom <= 1000 + 1),
      `desktop header controls are clipped in ${sectionName}: ${JSON.stringify(desktopMetrics.controls)}`);
      if (sectionName === "overview")
        await verifyOverviewNavigationClearance(desktopPage, 1440);
      if (sectionName === "isolation") {
        await verifyIsolationApplyClearance(desktopPage, 1440);
        await desktopPage.screenshot({
          path:path.join(outDir, "smartap-isolation-clearance-1440.png"),
          fullPage:true
        });
      }
    }
    await desktopPage.click('[data-section="overview"]');
    await desktopPage.waitForSelector("#overview:not([hidden])");
    await desktopPage.screenshot({ path: path.join(outDir, "smartap-overview-desktop-1440.png") });

    // Lightweight visual/system matrix: exercise the unified stylesheet in
    // both writing directions and both themes at every supported phone width
    // plus the desktop shell. This intentionally reuses one authenticated page
    // so it adds no control reads and keeps the behavioral suite bounded.
    for (const matrixWidth of [360, 390, 430, 1440]) {
      const matrixHeight = matrixWidth === 1440 ? 1000 : 844;
      await desktopPage.setViewportSize({ width:matrixWidth, height:matrixHeight });
      for (const matrixLanguage of ["ar", "en"]) {
        await desktopPage.evaluate(language => {
          document.querySelector(language === "ar" ? "#langAr" : "#langEn").click();
          document.querySelector(".main").scrollTop = 0;
          window.scrollTo(0, 0);
        }, matrixLanguage);
        await desktopPage.waitForFunction(language =>
          document.documentElement.lang === language &&
          document.documentElement.dir === (language === "ar" ? "rtl" : "ltr"), matrixLanguage);
        for (const matrixTheme of ["dark", "light"]) {
          await desktopPage.evaluate(theme => {
            // This matrix validates the CSS themes themselves. Theme-button
            // behavior is covered above; setting the public theme attribute
            // here avoids coupling 16 visual captures to asynchronous chart
            // redraw work between rapid toggles.
            document.documentElement.dataset.theme = theme;
            document.querySelector(".main").scrollTop = 0;
            window.scrollTo(0, 0);
          }, matrixTheme);
          await desktopPage.waitForFunction(theme => document.documentElement.dataset.theme === theme, matrixTheme);
          const matrixMetrics = await desktopPage.evaluate(() => {
            const rect = element => {
              const value = element.getBoundingClientRect();
              return { left:value.left, right:value.right, top:value.top, bottom:value.bottom,
                width:value.width, height:value.height };
            };
            const side = document.querySelector(".side");
            const main = document.querySelector(".main");
            const controls = document.querySelector(".controls");
            const activeNav = document.querySelector('.nav button[aria-current="page"]');
            const navButtons = Array.from(document.querySelectorAll(".nav button")).map(rect);
            const navLabel = document.querySelector(".nav button span");
            const select = document.querySelector("#intervalSelect");
            const card = document.querySelector("#overview .card");
            const styleVisible = element => {
              const style = getComputedStyle(element);
              return style.backgroundImage !== "none" || !/rgba?\([^)]*,\s*0\s*\)$/.test(style.backgroundColor);
            };
            return {
              lang:document.documentElement.lang,
              dir:document.documentElement.dir,
              theme:document.documentElement.dataset.theme,
              width:innerWidth,
              scrollWidth:document.documentElement.scrollWidth,
              side:rect(side),
              main:rect(main),
              navButtons,
              navLabelWhiteSpace:getComputedStyle(navLabel).whiteSpace,
              controlsDisplay:getComputedStyle(controls).display,
              controlColumns:getComputedStyle(controls).gridTemplateColumns,
              formBackground:getComputedStyle(select).backgroundColor,
              formColor:getComputedStyle(select).color,
              activeNav:!!activeNav,
              surfaceVisible:styleVisible(card),
              brandPseudo:getComputedStyle(document.querySelector(".brand"), "::after").content
            };
          });
          assert(matrixMetrics.lang === matrixLanguage &&
            matrixMetrics.dir === (matrixLanguage === "ar" ? "rtl" : "ltr") &&
            matrixMetrics.theme === matrixTheme,
          `design matrix lost language/theme state: ${JSON.stringify(matrixMetrics)}`);
          assert(matrixMetrics.scrollWidth <= matrixWidth + 1 && matrixMetrics.activeNav &&
            matrixMetrics.surfaceVisible && matrixMetrics.formBackground !== "rgba(0, 0, 0, 0)" &&
            matrixMetrics.formColor !== matrixMetrics.formBackground &&
            (matrixMetrics.brandPseudo === "none" || matrixMetrics.brandPseudo === "normal"),
          `design matrix has overflow/invisible surfaces or pseudo-copy: ${JSON.stringify(matrixMetrics)}`);
          if (matrixWidth <= 520) {
            assert(matrixMetrics.navButtons.length === 9 && matrixMetrics.navButtons.every(button =>
              button.left >= -1 && button.right <= matrixWidth + 1 &&
              button.top >= matrixMetrics.side.top - 1 && button.bottom <= matrixMetrics.side.bottom + 1) &&
              matrixMetrics.navLabelWhiteSpace === "normal" &&
              matrixMetrics.main.bottom <= matrixMetrics.side.top - 2 &&
              matrixMetrics.controlsDisplay === "grid" &&
              matrixMetrics.controlColumns.split(" ").length === 2,
            `phone design matrix broke navigation/control geometry: ${JSON.stringify(matrixMetrics)}`);
          } else {
            assert(matrixMetrics.side.width >= 210 && matrixMetrics.main.width >= 900,
              `desktop design matrix collapsed the shell: ${JSON.stringify(matrixMetrics)}`);
          }
          await desktopPage.screenshot({
            path:path.join(outDir, `smartap-design-${matrixLanguage}-${matrixTheme}-${matrixWidth}.png`)
          });
        }
      }
    }
    await desktopPage.close();

    // LuCI/Argon uses separate markup from Smart AP. Keep a dedicated 390px
    // regression matrix for the real menu, CBI tabs and wireless status rows.
    const argonPage = await browser.newPage({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 1,
      isMobile: true,
      hasTouch: true
    });
    await verifyArgonTabLayout(argonPage, "admin", "admin-system-admin", [
      "Router Password", "SSH Access", "SSH-Keys", "Dropbear Instances"
    ]);
    await verifyArgonTabLayout(argonPage, "interfaces", "admin-network-network", [
      "Interfaces", "Devices", "Global network options"
    ]);
    await verifyArgonWirelessLayout(argonPage);
    for (const argonWidth of [390, 1440]) {
      await verifyArgonSystemTime(argonPage, "ltr", argonWidth);
      await verifyArgonSystemTime(argonPage, "rtl", argonWidth);
      await verifyArgonStatusTime(argonPage, "ltr", argonWidth);
      await verifyArgonStatusTime(argonPage, "rtl", argonWidth);
    }
    await argonPage.close();

    // A configured but disabled radio must remain visible with a truthful
    // reason and no fabricated/default/unknown TX-power value.
    mock.wifi[1] = Object.assign({}, mock.wifi[1], {
      iface: "",
      up: false,
      disabled: true,
      state: "disabled",
      reason: "Radio disabled in UCI",
      radio_reason: "Radio disabled in UCI",
      power_status: "disabled",
      power_reason: "Radio disabled in UCI",
      signal_dbm: null,
      noise_dbm: null,
      bitrate_mbps: null,
      applied_dbm: null,
      txpower: {
        requested_dbm: 30,
        applied_dbm: null,
        max_dbm: 23,
        status: "disabled",
        reason: "Radio disabled in UCI"
      },
      stations: []
    });
    const disabledPage = await browser.newPage({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 1,
      isMobile: true,
      hasTouch: true
    });
    await disabledPage.goto(`http://127.0.0.1:${port}/`, { waitUntil: "domcontentloaded" });
    await disabledPage.fill("#loginPass", "admin");
    await disabledPage.click("#loginBtn");
    await disabledPage.waitForSelector("#appShell:not([hidden])");
    await disabledPage.waitForTimeout(3400);
    await disabledPage.click('[data-section="wifi"]');
    await disabledPage.waitForSelector("#wifi:not([hidden])");
    const disabledText = await disabledPage.locator("#wifi").innerText();
    assert(disabledText.includes("Radio disabled in UCI"),
      `disabled radio reason is missing: ${disabledText}`);
    assert(!/Generic unknown|Current power:\\s*unknown|driver default/i.test(disabledText),
      `disabled radio exposes a fake/unknown power label: ${disabledText}`);
    await disabledPage.screenshot({ path: path.join(outDir, "smartap-wifi-disabled-390.png") });
    await disabledPage.close();

    assert(dashluciRequests === 0,
      `Smart AP browser tests issued ${dashluciRequests} dashluci bridge requests`);
    assert(luciRouteRequests >= 2,
      `legacy LuCI redirect was not exercised by both HTTP and browser navigation: ${luciRouteRequests}`);
    console.log("stable_dom=pass");
    console.log("design_matrix=pass");
    console.log("mobile_layout_tests=pass");
    console.log(`dashluci_bridge_requests=${dashluciRequests}`);
    console.log(`luci_redirect_requests=${luciRouteRequests}`);
    console.log(`screenshots=${outDir}`);
  } finally {
    await browser.close();
    server.close();
  }
})().catch(error => {
  console.error(error.stack || String(error));
  server.close();
  process.exit(1);
});

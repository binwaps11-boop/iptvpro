#!/usr/bin/env node

const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("../../tools/playwright/node_modules/playwright-core");

const root = path.resolve(__dirname, "..", "files", "www");
const outDir = path.resolve(__dirname, "..", ".mobile-layout");
fs.mkdirSync(outDir, { recursive: true });

const mock = {
  ok: true,
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
  backhaul: { online: true, gateway: "192.168.1.254" },
  traffic: { rx_bytes: 1200000, tx_bytes: 430000, rx_bps: 120000, tx_bps: 42000 },
  interfaces: [
    { name: "lan1", connected: true, speed_mbps: 1000, rx_bps: 90000, tx_bps: 31000 },
    { name: "lan2", connected: false, speed_mbps: 0, rx_bps: 0, tx_bps: 0 },
    { name: "lan3", connected: false, speed_mbps: 0, rx_bps: 0, tx_bps: 0 }
  ],
  wifi: [
    {
      iface: "phy0-ap0", ssid: "Smart ap 2.4G", mode: "ap", band: "2.4G",
      channel: 11, htmode: "HE20", signal_dbm: -34, noise_dbm: -95, clients: 1,
      txpower: { requested_dbm: 38, applied_dbm: 38, max_dbm: 38 },
      survey: { busy_pct: 7 }, stations: []
    },
    {
      iface: "phy1-ap0", ssid: "Smart ap 5G", mode: "ap", band: "5G",
      channel: 36, htmode: "HE80", signal_dbm: -31, noise_dbm: -95, clients: 1,
      txpower: { requested_dbm: 38, applied_dbm: 38, max_dbm: 38 },
      survey: { busy_pct: 9 }, stations: []
    }
  ],
  devices: []
};

const wizardControl = {
  ok: true,
  cards: [
    { label: "Mode", value: "Access Point" },
    { label: "TX Power", value: "38 / 38 dBm" }
  ],
  form: [
    { name: "program_mode", label: "Programming mode", value: "ap", type: "select", options: "ap:Access Point,ap_vlan:Access Point + VLAN", group: "device" },
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

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  if (url.pathname === "/cgi-bin/dashlogin") {
    send(res, 200, "application/json", '{"ok":true}');
    return;
  }
  if (url.pathname === "/cgi-bin/dashapi2") {
    send(res, 200, "application/json", JSON.stringify(mock));
    return;
  }
  if (url.pathname === "/cgi-bin/dashlogout" || url.pathname === "/cgi-bin/dashluci") {
    send(res, 200, "application/json", '{"ok":true}');
    return;
  }
  if (url.pathname === "/cgi-bin/dashctl") {
    let body = "";
    req.on("data", chunk => { body += chunk; });
    req.on("end", () => {
      const section = new URLSearchParams(body).get("section");
      send(res, 200, "application/json", JSON.stringify(section === "isolation" ? isolationControl : wizardControl));
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

(async () => {
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  const executablePath = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    for (const width of [360, 390, 430]) {
      const page = await browser.newPage({
        viewport: { width, height: 844 },
        deviceScaleFactor: 1,
        isMobile: true,
        hasTouch: true
      });
      await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "networkidle" });
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
        const main = document.querySelector(".main").getBoundingClientRect();
        return {
          viewport: innerWidth,
          bodyScrollWidth: document.documentElement.scrollWidth,
          offenders,
          navTop: nav.top,
          navLabelWhiteSpace: navLabelStyle.whiteSpace,
          navLabelLineClamp: navLabelStyle.webkitLineClamp,
          mainBottom: main.bottom,
          contentPaddingBottom: parseFloat(getComputedStyle(document.querySelector(".app")).paddingBottom)
        };
        });
        await page.screenshot({ path: path.join(outDir, `smartap-${name}-${width}.png`) });
        assert(metrics.bodyScrollWidth <= width + 1, `horizontal overflow in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.offenders.length === 0, `elements outside viewport in ${name} at ${width}px: ${metrics.offenders.join("; ")}`);
        assert(metrics.navTop >= 740, `bottom navigation is not anchored at the bottom in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.navLabelWhiteSpace === "normal" && metrics.navLabelLineClamp === "2",
          `bottom navigation labels are not readable on two lines in ${name} at ${width}px: ${JSON.stringify(metrics)}`);
        assert(metrics.contentPaddingBottom >= 84, `bottom navigation can cover ${name} content at ${width}px`);
      }
      await verifySection("overview", "#overview:not([hidden])");
      await verifySection("quick", "#ctl_wizard .wizard-tabs");
      await verifySection("isolation", "#ctl_isolation .dsa-port-list");
      await page.close();
    }
    console.log("mobile_layout_tests=pass");
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

#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const playwrightCore = [
  path.resolve(__dirname, "..", "..", "tools", "playwright", "node_modules", "playwright-core"),
  path.resolve(__dirname, "..", "..", "..", "tools", "playwright", "node_modules", "playwright-core")
].find(candidate => fs.existsSync(path.join(candidate, "package.json")));
if (!playwrightCore) {
  throw new Error("playwright-core is missing from the CR6608 test tools directory");
}
const { chromium } = require(playwrightCore);

const baseUrl = (process.env.SMARTAP_ROUTER_URL || "http://192.168.1.1").replace(/\/$/, "");
const password = process.env.SMARTAP_UI_PASSWORD;
const outDir = path.resolve(process.env.SMARTAP_ROUTER_UI_OUT || path.join(__dirname, "..", ".router-mobile-ui"));

if (!password) {
  throw new Error("SMARTAP_UI_PASSWORD is required");
}

fs.mkdirSync(outDir, { recursive: true });

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function metrics(page) {
  return page.evaluate(() => {
    const visible = Array.from(document.querySelectorAll("body *")).filter(el => {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 1 && rect.height > 1;
    });
    const clippedByScroller = el => {
      for (let parent = el.parentElement; parent; parent = parent.parentElement) {
        const style = getComputedStyle(parent);
        if (["auto", "scroll"].includes(style.overflowX) && parent.scrollWidth > parent.clientWidth) return true;
      }
      return false;
    };
    const offenders = visible.filter(el => {
      const rect = el.getBoundingClientRect();
      return (rect.left < -1 || rect.right > innerWidth + 1) && !clippedByScroller(el);
    }).slice(0, 12).map(el => {
      const rect = el.getBoundingClientRect();
      return `${el.tagName.toLowerCase()}#${el.id}.${el.className} [${rect.left.toFixed(1)},${rect.right.toFixed(1)}]`;
    });
    const navElement = document.querySelector(".side");
    const nav = navElement ? navElement.getBoundingClientRect() : null;
    const navButtons = Array.from(document.querySelectorAll(".nav button")).map(el => {
      const rect = el.getBoundingClientRect();
      return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom };
    });
    const navLabel = document.querySelector(".nav button span");
    const navStyle = navLabel ? getComputedStyle(navLabel) : null;
    const app = document.querySelector(".app");
    const heroControls = Array.from(document.querySelectorAll(".controls > *")).map(el => {
      const rect = el.getBoundingClientRect();
      return { visible: rect.width > 1 && rect.height > 1, left: rect.left, right: rect.right };
    });
    const detailTitle = document.querySelector(".branch-detail > h3");
    return {
      scrollWidth: document.documentElement.scrollWidth,
      viewport: innerWidth,
      viewportHeight: innerHeight,
      offenders,
      navTop: nav ? nav.top : null,
      navBottom: nav ? nav.bottom : null,
      navButtons,
      navWhiteSpace: navStyle ? navStyle.whiteSpace : null,
      navLineClamp: navStyle ? navStyle.webkitLineClamp : null,
      appPaddingBottom: app ? parseFloat(getComputedStyle(app).paddingBottom) : 0,
      heroControls,
      detailTitleSize: detailTitle ? parseFloat(getComputedStyle(detailTitle).fontSize) : 0
    };
  });
}

(async () => {
  const launchOptions = { headless: true };
  if (process.env.CR6608_BROWSER_PATH) {
    launchOptions.executablePath = process.env.CR6608_BROWSER_PATH;
  } else if (process.platform === "win32") {
    launchOptions.executablePath = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
  }
  const browser = await chromium.launch(launchOptions);
  try {
    for (const width of [360, 390, 430]) {
      const context = await browser.newContext({
        viewport: { width, height: 844 },
        deviceScaleFactor: 1,
        isMobile: true,
        hasTouch: true,
        ignoreHTTPSErrors: true
      });
      const page = await context.newPage();
      await page.goto(`${baseUrl}/`, { waitUntil: "networkidle" });
      await page.screenshot({ path: path.join(outDir, `router-login-${width}.png`) });

      await page.fill("#loginUser", width === 390 ? "admin" : "root");
      await page.fill("#loginPass", password);
      await page.click("#loginBtn");
      await page.waitForSelector("#appShell:not([hidden])", { timeout: 15000 });
      await page.waitForTimeout(3500);
      assert((await page.locator("#openWrtBtn").count()) === 1,
        `authenticated OpenWrt settings button is missing at ${width}px`);
      assert((await page.locator('a[href^="/cgi-bin/luci"], form[action^="/cgi-bin/luci"]').count()) === 0,
        `LuCI navigation is present in Smart AP at ${width}px`);
      assert(await page.evaluate(() =>
        document.querySelector('meta[name="smartap-stable-dom"]')?.content === "pass" &&
        window.__smartApDebug?.stable_dom === "pass"),
      `stable_dom marker is missing at ${width}px`);

      const apiContract = await page.evaluate(async () => {
        // The dashboard may still own the single-flight CGI lock while its
        // first full snapshot is being collected on slow hardware. Retry a
        // bounded number of times instead of misclassifying that busy reply
        // as an authentication failure.
        let result = null;
        for (let attempt = 0; attempt < 5; attempt += 1) {
          const response = await fetch("/cgi-bin/dashapi2", { credentials: "same-origin", cache: "no-store" });
          result = { status: response.status, data: await response.json() };
          if (result.status === 200 && result.data && result.data.ok === true) return result;
          await new Promise(resolve => setTimeout(resolve, 3500));
        }
        return result;
      });
      assert(apiContract.status === 200 && apiContract.data.ok === true,
        `dashboard status API did not return an authenticated snapshot at ${width}px`);
      const radioRows = Array.isArray(apiContract.data.wifi) ? apiContract.data.wifi : [];
      assert(radioRows.length === 2, `dashboard status API returned ${radioRows.length} radio rows`);
      for (const radio of ["radio0", "radio1"]) {
        const row = radioRows.find(item => item && item.radio === radio);
        assert(row, `dashboard status API omitted ${radio}`);
        for (const field of ["up", "disabled", "state", "reason", "requested_dbm",
          "applied_dbm", "max_dbm", "regulatory_max_dbm", "channel_max_dbm",
          "driver_accepted_dbm", "current_reported_dbm", "radio_reason",
          "power_status", "power_reason"]) {
          assert(Object.prototype.hasOwnProperty.call(row, field), `${radio} omitted status field ${field}`);
        }
        assert(row.txpower && row.requested_dbm === row.txpower.requested_dbm,
          `${radio} requested power differs between flat and compatibility contracts`);
        assert(row.applied_dbm === row.txpower.applied_dbm,
          `${radio} applied power differs between flat and compatibility contracts`);
        assert(row.max_dbm === row.txpower.max_dbm,
          `${radio} maximum power differs between flat and compatibility contracts`);
        assert(row.power_status === row.txpower.status,
          `${radio} power status differs between flat and compatibility contracts`);
        assert(row.power_reason === row.txpower.reason,
          `${radio} power reason differs between flat and compatibility contracts`);
        if (row.power_status === "limited") {
          assert(row.power_reason && row.reason === row.power_reason,
            `${radio} did not expose its power limit reason on the flat status contract`);
        }
      }

      for (const section of ["overview", "quick", "isolation"]) {
        if (section !== "overview") {
          await page.click(`[data-section="${section}"]`);
          if (section === "quick") {
            await page.waitForSelector("#ctl_wizard .wizard-tabs", { timeout: 15000 });
          } else if (section === "isolation") {
            await page.waitForSelector("#ctl_isolation .isolation-tabs", { timeout: 15000 });
          }
          await page.waitForTimeout(300);
        }
        const result = await metrics(page);
        await page.screenshot({ path: path.join(outDir, `router-${section}-${width}.png`), fullPage: false });
        if (section === "overview") {
          assert(!/\bLoading\b/i.test(await page.locator("#overview").innerText()),
            `overview was still loading at ${width}px`);
        }
        assert(result.scrollWidth <= width + 1, `${section} overflows at ${width}px: ${JSON.stringify(result)}`);
        assert(result.offenders.length === 0, `${section} has off-screen elements at ${width}px: ${result.offenders.join("; ")}`);
        assert(result.navTop >= result.viewportHeight - 160, `${section} navigation is not bottom anchored at ${width}px`);
        assert(result.navButtons.length === 9 && result.navButtons.every(button =>
          button.left >= -1 && button.right <= width + 1 &&
          button.top >= result.navTop - 1 && button.bottom <= result.navBottom + 1),
        `${section} does not expose every primary destination at ${width}px: ${JSON.stringify(result.navButtons)}`);
        assert(result.navWhiteSpace === "normal" && result.navLineClamp === "2",
          `${section} navigation labels are not readable on two lines at ${width}px`);
        assert(result.appPaddingBottom >= 160, `${section} content can be covered by navigation at ${width}px`);
        assert(result.heroControls.length === 6 && result.heroControls.every(c => c.visible && c.left >= -1 && c.right <= width + 1),
          `${section} header controls are clipped at ${width}px: ${JSON.stringify(result.heroControls)}`);
        if (section !== "overview")
          assert(result.detailTitleSize > 0 && result.detailTitleSize <= 21,
            `${section} detail title is oversized at ${width}px: ${result.detailTitleSize}`);
      }

      if (width === 390) {
        await page.click('[data-section="network"]');
        await page.waitForSelector('#network:not([hidden]) #networkTrafficCanvas', { timeout:15000 });
        await page.waitForFunction(() => document.querySelector("#networkTrafficCanvas")?.dataset.chartStable === "1");
        await page.evaluate(() => {
          const root = document.querySelector("#network");
          window.__routerStableProbe = {
            root,
            head:root.querySelector('[data-ui-key="section-head"]'),
            canvas:document.querySelector("#networkTrafficCanvas"),
            row:root.querySelector('[data-ui-key^="interface:"]'),
            generation:Number(document.querySelector("#networkTrafficCanvas").dataset.chartGeneration || 0)
          };
          document.querySelector("#refreshBtn").click();
        });
        await page.waitForFunction(() => {
          const canvas = document.querySelector("#networkTrafficCanvas");
          return Number(canvas?.dataset.chartGeneration || 0) > window.__routerStableProbe.generation &&
            canvas?.dataset.chartStable === "1";
        }, null, { timeout:20000 });
        const stableRefresh = await page.evaluate(() => ({
          root:window.__routerStableProbe.root === document.querySelector("#network"),
          head:window.__routerStableProbe.head === document.querySelector('#network [data-ui-key="section-head"]'),
          canvas:window.__routerStableProbe.canvas === document.querySelector("#networkTrafficCanvas"),
          row:!window.__routerStableProbe.row || window.__routerStableProbe.row.isSameNode(document.querySelector('[data-ui-key="' + window.__routerStableProbe.row.dataset.uiKey + '"]')),
          active:window.__smartApDebug?.activeDataRequests,
          maxActive:window.__smartApDebug?.maxActiveDataRequests
        }));
        assert(stableRefresh.root && stableRefresh.head && stableRefresh.canvas && stableRefresh.row &&
          stableRefresh.active === 0 && stableRefresh.maxActive <= 1,
        `safe live GET replaced mounted nodes or overlapped: ${JSON.stringify(stableRefresh)}`);

        const redirectProbe = await context.request.get(
          `${baseUrl}/cgi-bin/luci/admin/network/wireless`,
          { maxRedirects: 0 }
        );
        assert(redirectProbe.status() === 302,
          `legacy LuCI path returned ${redirectProbe.status()} instead of 302`);
        assert(redirectProbe.headers().location === "/",
          `legacy LuCI path redirected to ${redirectProbe.headers().location || "nothing"} instead of Smart AP root`);
        const response = await page.goto(`${baseUrl}/cgi-bin/luci/admin/network/wireless`, {
          waitUntil: "domcontentloaded",
          timeout: 15000
        });
        assert(response && response.status() === 200,
          `Smart AP redirect ended with ${response ? response.status() : "no response"}`);
        await page.waitForSelector("#appShell:not([hidden])", { timeout: 15000 });
        assert(new URL(page.url()).pathname === "/", `browser remained on a LuCI path: ${page.url()}`);
        assert(!(await page.locator("input[name=luci_password]").count()),
          "legacy LuCI path displayed a second login form");
        await page.screenshot({ path: path.join(outDir, "router-smartap-luci-redirect-390.png"), fullPage: false });
      }

      await context.close();
    }
    console.log("router_mobile_ui_tests=pass");
    console.log(`router=${baseUrl}`);
    console.log(`screenshots=${outDir}`);
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error.stack || error.message || String(error));
  process.exit(1);
});

#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { chromium } = require("../../tools/playwright/node_modules/playwright-core");

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
    const navLabel = document.querySelector(".nav button span");
    const navStyle = navLabel ? getComputedStyle(navLabel) : null;
    const app = document.querySelector(".app");
    return {
      scrollWidth: document.documentElement.scrollWidth,
      viewport: innerWidth,
      offenders,
      navTop: nav ? nav.top : null,
      navWhiteSpace: navStyle ? navStyle.whiteSpace : null,
      navLineClamp: navStyle ? navStyle.webkitLineClamp : null,
      appPaddingBottom: app ? parseFloat(getComputedStyle(app).paddingBottom) : 0
    };
  });
}

(async () => {
  const browser = await chromium.launch({
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    headless: true
  });
  try {
    for (const width of [360, 390, 430]) {
      const context = await browser.newContext({
        viewport: { width, height: 844 },
        deviceScaleFactor: 1,
        isMobile: true,
        hasTouch: true
      });
      const page = await context.newPage();
      await page.goto(`${baseUrl}/`, { waitUntil: "networkidle" });
      await page.screenshot({ path: path.join(outDir, `router-login-${width}.png`) });

      await page.fill("#loginUser", "root");
      await page.fill("#loginPass", password);
      await page.click("#loginBtn");
      await page.waitForSelector("#appShell:not([hidden])", { timeout: 15000 });
      await page.waitForTimeout(3500);

      for (const section of ["overview", "quick", "isolation"]) {
        if (section !== "overview") {
          await page.click(`[data-section="${section}"]`);
          await page.waitForTimeout(600);
        }
        const result = await metrics(page);
        await page.screenshot({ path: path.join(outDir, `router-${section}-${width}.png`), fullPage: false });
        assert(result.scrollWidth <= width + 1, `${section} overflows at ${width}px: ${JSON.stringify(result)}`);
        assert(result.offenders.length === 0, `${section} has off-screen elements at ${width}px: ${result.offenders.join("; ")}`);
        assert(result.navTop >= 740, `${section} navigation is not bottom anchored at ${width}px`);
        assert(result.navWhiteSpace === "normal" && result.navLineClamp === "2",
          `${section} navigation labels are not readable on two lines at ${width}px`);
        assert(result.appPaddingBottom >= 84, `${section} content can be covered by navigation at ${width}px`);
      }

      if (width === 390) {
        const navigation = page.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 15000 });
        await page.click("#openWrtBtn");
        const response = await navigation;
        assert(response && response.status() === 200,
          `LuCI navigation returned ${response ? response.status() : "no response"}`);
        assert(!response.headers()["x-luci-login-required"], "LuCI requested another login");
        assert(!(await page.locator("input[name=luci_password]").count()), "LuCI displayed its login form");
        assert((await page.locator("body").getAttribute("data-page")) || (await page.locator("[data-page]").count()),
          "LuCI did not render an authenticated page");
        await page.screenshot({ path: path.join(outDir, "router-argon-authenticated-390.png"), fullPage: false });
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

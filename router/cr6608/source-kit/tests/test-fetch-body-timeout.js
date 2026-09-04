#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const dashboard = fs.readFileSync(
  path.resolve(__dirname, "..", "files", "www", "dashboard.js"),
  "utf8"
);
const start = dashboard.indexOf("  function fetchWithTimeout(");
const end = dashboard.indexOf("  function requireLogin(", start);
if (start < 0 || end < 0) throw new Error("fetchWithTimeout source not found");
const source = dashboard.slice(start, end);

function makeHelper(fakeFetch, Controller, defaultTimeout) {
  return new Function(
    "fetch", "AbortController", "AUTH_TIMEOUT_MS", "setTimeout", "clearTimeout",
    `"use strict";\n${source}\nreturn fetchWithTimeout;`
  )(fakeFetch, Controller, defaultTimeout, setTimeout, clearTimeout);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function expectBodyTimeout(withAbortController) {
  let aborted = false;
  class Controller {
    constructor() { this.signal = {}; }
    abort() { aborted = true; }
  }
  const helper = makeHelper(
    async () => ({ status: 200, json: () => new Promise(() => {}) }),
    withAbortController ? Controller : undefined,
    35
  );
  const response = await helper("/stalled", {}, 35);
  let error;
  try {
    await response.json();
  } catch (caught) {
    error = caught;
  }
  assert(error && error.code === "SMARTAP_TIMEOUT", "stalled response body did not time out");
  assert(aborted === withAbortController, "AbortController state does not match availability");
}

async function expectCompletedBodyClearsTimer() {
  let aborted = false;
  class Controller {
    constructor() { this.signal = {}; }
    abort() { aborted = true; }
  }
  const helper = makeHelper(
    async () => ({ status: 200, json: async () => ({ ok: true }) }),
    Controller,
    35
  );
  const response = await helper("/complete", {}, 35);
  const body = await response.json();
  assert(body.ok === true, "completed JSON body was changed");
  await new Promise(resolve => setTimeout(resolve, 60));
  assert(!aborted, "completed response left its timeout armed");
}

(async () => {
  await expectBodyTimeout(true);
  await expectBodyTimeout(false);
  await expectCompletedBodyClearsTimer();
  console.log("fetch_body_timeout=pass");
})().catch(error => {
  console.error(error.stack || String(error));
  process.exit(1);
});

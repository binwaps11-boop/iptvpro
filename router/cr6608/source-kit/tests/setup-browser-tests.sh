#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RUNTIME_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/../test-tools/playwright" && pwd)"
NODE_BIN="${CR6608_NODE_BIN:-${HOME}/tools/node20/bin/node}"

[ -x "${NODE_BIN}" ] || {
	printf 'Node.js runtime is missing: %s\n' "${NODE_BIN}" >&2
	exit 1
}

NODE_DIR="${NODE_BIN%/node}"
PATH="${NODE_DIR}:${PATH}"
export PATH

major="$(${NODE_BIN} -p 'process.versions.node.split(".")[0]')"
[ "${major}" -ge 18 ] || {
	printf 'Node.js 18 or newer is required\n' >&2
	exit 1
}

cd "${RUNTIME_DIR}"
npm ci --ignore-scripts
"${NODE_BIN}" node_modules/playwright-core/cli.js install chromium
"${NODE_BIN}" -e 'const p=require("playwright-core/package.json"); if (p.version !== "1.58.2") process.exit(1)'

printf 'browser_test_runtime=playwright-core-1.58.2\n'
